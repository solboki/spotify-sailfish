#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sailplay service of Hutspot: "Browse" page of the car screen.

Music arrangement of the Sailplay presentation hints:

    left    tabs (Playlists, Albums, Podcasts, Audiobooks, Recent), then the
            albums / playlists / podcasts as cards, then their tracks.
            Touching a track adds it to the play queue; the first row of an
            album or playlist plays it whole.
    right   side panel: what is playing with previous / play-pause / next
            (drawn by Sailplay from the MPRIS player of Hutspot), the play
            queue, and the Shuffle and Repeat options.

Where the data comes from:

  * the tabs and their cards come from a summary of the library that Hutspot
    keeps in its LocalStorage database (key "car_library"): they are shown at
    once, even without network;
  * tracks, queue and options are asked to the running Hutspot over D-Bus
    (org.solboki.HutspotApp.request, see qml/components/DBusControl.qml).
    Hutspot alone holds the Spotify session and renews it; this service never
    sees a token. Hutspot is started by D-Bus when needed.

With a Sailplay that does not know the presentation hints, the same pages are
shown as plain lists.

The service is started on demand by D-Bus and stops after ten idle seconds.
The SDK is provided by Sailplay (/opt/sailplay, GPL-3.0-or-later): without
Sailplay this service does not start and Hutspot does not depend on it.
"""
import glob
import json
import os
import signal
import sqlite3
import subprocess
import sys
import time
from urllib.parse import quote

sys.path.insert(0, "/opt/sailplay")

import dbus  # noqa: E402
import dbus.mainloop.glib  # noqa: E402
from gi.repository import GLib  # noqa: E402

from sailplay_sdk.content import ContentBackend, wire_content  # noqa: E402
from sailplay_sdk.content_model import content_item, content_page  # noqa: E402
from sailplay_sdk.model import Fault  # noqa: E402

try:  # presentation hints: images, playback status, cards, tabs, side panel
    from sailplay_sdk.content import content_result  # noqa: E402
    from sailplay_sdk.content_model import LAYOUTS  # noqa: E402
    HINTS = "split" in LAYOUTS
except ImportError:  # older Sailplay: plain lists
    HINTS = False

if not HINTS:
    def content_result(value):  # noqa: F811
        return {"content": wire_content(value)}

SERVICE = os.environ.get("HUTSPOT_CAR_SERVICE", "org.solboki.Hutspot")
APPLICATION_ID = "hutspot"
# the application itself (session, Spotify requests)
APP_SERVICE = os.environ.get("HUTSPOT_APP_SERVICE", "org.solboki.hutspot")
APP_PATH = "/app"
APP_INTERFACE = "org.solboki.HutspotApp"
REQUEST_SECONDS = 12
START_SECONDS = 40

MPRIS_PREFIX = "org.mpris.MediaPlayer2."
DESKTOP_ENTRY = "hutspot"
MPRIS_PATH = "/org/mpris/MediaPlayer2"
MPRIS_PLAYER = "org.mpris.MediaPlayer2.Player"
PROPERTIES = "org.freedesktop.DBus.Properties"
LAUNCH = ["/usr/bin/invoker", "--type=silica-qt5", "--single-instance", "/usr/bin/hutspot"]
LAUNCH_TIMEOUT = 40
# time left to Hutspot to get its Spotify token before playing
START_DELAY_MS = 4000
IDLE_SECONDS = 10
PAGE_MAX = 50
QUEUE = "queue"
QUEUE_FRESH_SECONDS = 3
TRACKS_FRESH_SECONDS = 300
# Spotify needs a moment before the queue shows what was just asked
SETTLE_MS = 700

_FR = os.environ.get("LANG", "").startswith("fr")
# key, French, English, how the entries are shown: "folder" opens the list of
# tracks, "play" plays the entry, "queue" adds it to the queue
SECTIONS = [
    ("albums", "Albums", "Albums", "folder"),
    ("playlists", "Playlists", "Playlists", "folder"),
    ("shows", "Podcasts", "Podcasts", "folder"),
    ("audiobooks", "Livres audio", "Audiobooks", "play"),
    ("recent", "Récents", "Recent", "queue"),
]


def _t(fr, en):
    return fr if _FR else en


TEXT = {
    "empty": _t("Ouvrez Hutspot une fois sur le téléphone pour charger la bibliothèque",
                "Open Hutspot once on the phone to load the library"),
    "folder_empty": _t("Rien ici", "Nothing here"),
    "none": _t("Aucun résultat", "No results"),
    "queue": _t("File d'attente", "Queue"),
    "queue_empty": _t("Rien dans la file", "Nothing in the queue"),
    "unreachable": _t("Spotify injoignable pour le moment", "Spotify cannot be reached for now"),
    "tracks_hidden": _t("Spotify ne communique pas le contenu de cette playlist",
                        "Spotify does not disclose the content of this playlist"),
    "play_album": _t("Lire l'album", "Play the album"),
    "play_playlist": _t("Lire la playlist", "Play the playlist"),
    "play_all": _t("Tout lire", "Play all"),
    "shuffle_on": _t("Aléatoire : oui", "Shuffle: on"),
    "shuffle_off": _t("Aléatoire : non", "Shuffle: off"),
    "repeat_off": _t("Répéter : non", "Repeat: off"),
    "repeat_context": _t("Répéter : tout", "Repeat: all"),
    "repeat_track": _t("Répéter : titre", "Repeat: track"),
}


# --- Library summary written by Hutspot ---------------------------------------

def _databases():
    """LocalStorage databases of Hutspot (the exact folder depends on Qt)."""
    patterns = [
        "~/.local/share/*/QML/OfflineStorage/Databases/*.sqlite",
        "~/.local/share/*/*/QML/OfflineStorage/Databases/*.sqlite",
    ]
    found = []
    for pattern in patterns:
        for path in glob.glob(os.path.expanduser(pattern)):
            if "hutspot" in path:
                found.append(path)
    return found


def load_library():
    """Most recent car library summary written by Hutspot, or None."""
    best = None
    for path in _databases():
        try:
            con = sqlite3.connect("file:%s?mode=ro" % path, uri=True, timeout=2)
            try:
                row = con.execute("SELECT v, ts FROM kv WHERE k = 'car_library'").fetchone()
            finally:
                con.close()
        except sqlite3.Error:
            continue
        if row and (best is None or row[1] > best[1]):
            best = row
    if not best:
        return None
    try:
        value = json.loads(best[0])
    except ValueError:
        return None
    return value if isinstance(value, dict) else None


def _section(key):
    for entry in SECTIONS:
        if entry[0] == key:
            return entry
    return None


def _title(key):
    entry = _section(key)
    return (entry[1] if _FR else entry[2]) if entry else key


def _image(value):
    """An image address usable as a hint, or nothing."""
    value = value if isinstance(value, str) else ""
    return value if value.startswith(("https://", "http://")) and len(value) <= 2048 else ""


def _hints(**values):
    """Keyword arguments for the SDK, dropped with a Sailplay that has no hints."""
    return {key: value for key, value in values.items() if value not in ("", False)} if HINTS else {}


def _names(entries):
    return ", ".join(str(e.get("name", "")) for e in (entries or []) if isinstance(e, dict) and e.get("name"))


def _smallest(images):
    """The smallest picture of a Spotify image list (they are sorted, largest first)."""
    images = [i for i in (images or []) if isinstance(i, dict) and i.get("url")]
    return _image(images[-1]["url"]) if images else ""


def _kind_of(uri):
    parts = uri.split(":")
    return parts[1] if len(parts) == 3 and parts[0] == "spotify" else ""


def library_row(mode, entry, playing=""):
    """A row for an entry of the library summary."""
    uri = str(entry.get("uri", ""))
    title = (entry.get("title") or uri)[:1024]
    subtitle = (entry.get("subtitle") or "")[:1024]
    image = _image(entry.get("image"))
    if mode == "folder":
        return content_item(uri[:256], title, subtitle, **_hints(image=image))
    if mode == "queue":
        return content_item(uri[:256], title, subtitle, kind="action", action="queue.add",
                            parameters={"uri": uri},
                            **_hints(image=image, playback="playing" if uri == playing else ""))
    return content_item(uri[:256], title, subtitle, kind="action", action="content.select",
                        parameters={"uri": uri}, **_hints(image=image))


# --- Requests to the running Hutspot --------------------------------------------

class Remote:
    """Spotify requests made by Hutspot on behalf of this service.

    call(method, path, done) -> done(status, data): status is the HTTP status,
    0 when Hutspot or Spotify could not be reached.
    """

    def __init__(self, bus):
        self.bus = bus
        self.pending = {}
        self.counter = 0
        bus.add_signal_receiver(self._reply, signal_name="reply", dbus_interface=APP_INTERFACE,
                                path=APP_PATH)

    def running(self):
        try:
            return bool(self.bus.name_has_owner(APP_SERVICE))
        except dbus.exceptions.DBusException:
            return False

    def call(self, method, path, done, start=True):
        """start=False: do not start Hutspot for this (background refresh)."""
        running = self.running()
        if not running and not start:
            done(0, None)
            return
        self.counter += 1
        identity = "%d-%d" % (os.getpid(), self.counter)
        seconds = REQUEST_SECONDS if running else START_SECONDS
        source = GLib.timeout_add_seconds(seconds, lambda: (self._finish(identity, 0, None), False)[1])
        self.pending[identity] = (done, source)
        try:
            # a call to a service that is not running starts it (D-Bus activation)
            app = self.bus.get_object(APP_SERVICE, APP_PATH, introspect=False)
            app.request(identity, method, path, "", dbus_interface=APP_INTERFACE, timeout=seconds,
                        reply_handler=lambda accepted: None if accepted else self._finish(identity, 403, None),
                        error_handler=lambda error: self._finish(identity, 0, None))
        except dbus.exceptions.DBusException:
            self._finish(identity, 0, None)

    def _reply(self, identity, status, body):
        try:
            status = int(str(status))
        except ValueError:
            status = 0
        data = None
        if body:
            try:
                data = json.loads(str(body))
            except ValueError:
                data = None
        self._finish(str(identity), status, data)

    def _finish(self, identity, status, data):
        entry = self.pending.pop(identity, None)
        if entry is None:
            return
        done, source = entry
        try:
            GLib.source_remove(source)
        except Exception:  # the timeout that brought us here is already gone
            pass
        done(status, data)


def ok(status):
    return 200 <= status < 300


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()
    idle = [0]
    # Every page carries the same version; it grows when something shown may
    # have changed (queue, track being played), so that the car reads again.
    shown = {"version": int(time.time()), "playing": "", "signature": None, "check": 0}
    queue_cache = {"time": 0.0, "status": 0, "queue": None, "player": None}
    tracks_cache = {}

    def lifecycle(backend):
        if idle[0]:
            GLib.source_remove(idle[0])
            idle[0] = 0
        if not backend.session_count and not backend.pending_count:
            def quit_if_idle():
                idle[0] = 0
                if not backend.session_count and not backend.pending_count:
                    loop.quit()
                return False
            idle[0] = GLib.timeout_add_seconds(IDLE_SECONDS, quit_if_idle)

    # --- pages built from the library summary (no network) -------------------

    def root_page():
        lib = load_library()
        if lib is None:
            return content_page("root", "Spotify", [], message=TEXT["empty"], message_kind="info",
                                version=shown["version"], **_hints(side=QUEUE))
        folders = [content_item(key, _title(key)) for key, _fr, _en, _mode in SECTIONS if lib.get(key)]
        return content_page("root", "Spotify", folders, search_enabled=True,
                            message="" if folders else TEXT["empty"],
                            message_kind="none" if folders else "info", version=shown["version"],
                            **_hints(tabs=bool(folders), side=QUEUE))

    def listing(identity, title, rows, offset, limit, layout, empty):
        chunk = rows[offset:offset + limit]
        return content_page(identity, title, chunk, search_enabled=True, offset=offset,
                            has_more=offset + limit < len(rows),
                            message="" if rows else empty, message_kind="none" if rows else "info",
                            version=shown["version"], **_hints(layout=layout))

    def section_page(key, offset, limit):
        lib = load_library() or {}
        mode = _section(key)[3]
        rows = [library_row(mode, e, shown["playing"]) for e in lib.get(key, []) if e.get("uri")]
        return listing(key, _title(key), rows, offset, limit,
                       "list" if mode == "queue" else "wide", TEXT["folder_empty"])

    def search_page(query, offset, limit):
        lib = load_library() or {}
        q = query.casefold()
        rows, seen = [], set()
        for key, _fr, _en, mode in SECTIONS:
            for e in lib.get(key, []):
                text = ("%s %s" % (e.get("title", ""), e.get("subtitle", ""))).casefold()
                if q in text and e.get("uri") and e.get("uri") not in seen:
                    seen.add(e.get("uri"))
                    rows.append(library_row(mode, e, shown["playing"]))
        return listing("root", query, rows, offset, limit, "wide", TEXT["none"])

    def library_entry(uri):
        lib = load_library() or {}
        for key, _fr, _en, _mode in SECTIONS:
            for e in lib.get(key, []):
                if e.get("uri") == uri:
                    return e
        return {}

    # --- tracks of an album, a playlist or a podcast (asked to Hutspot) -------

    def tracks_request(uri, offset, limit):
        kind, identity = _kind_of(uri), quote(uri.split(":")[2], safe="")
        if kind == "album":
            return "/albums/%s/tracks?limit=%d&offset=%d&market=from_token" % (identity, limit, offset)
        if kind == "playlist":
            return "/playlists/%s/items?limit=%d&offset=%d&market=from_token" % (identity, limit, offset)
        return "/shows/%s/episodes?limit=%d&offset=%d&market=from_token" % (identity, limit, offset)

    def track_rows(kind, entries, first):
        rows = []
        for index, entry in enumerate(entries):
            if kind == "playlist" and isinstance(entry, dict):
                entry = entry.get("item") or entry.get("track")
            if not isinstance(entry, dict) or not entry.get("uri") or not entry.get("name"):
                continue
            uri = str(entry["uri"])
            row_id = ("%d:%s" % (first + index, uri))[:256]
            if kind == "show":
                point = entry.get("resume_point") or {}
                playback = ("finished" if point.get("fully_played")
                            else "started" if point.get("resume_position_ms") else "unplayed")
                if uri == shown["playing"]:
                    playback = "playing"
                rows.append(content_item(row_id, str(entry["name"])[:1024],
                                         str(entry.get("release_date") or "")[:1024],
                                         kind="action", action="content.select",
                                         parameters={"uri": uri}, **_hints(playback=playback)))
            else:
                rows.append(content_item(row_id, str(entry["name"])[:1024],
                                         _names(entry.get("artists"))[:1024],
                                         kind="action", action="queue.add", parameters={"uri": uri},
                                         **_hints(playback="playing" if uri == shown["playing"] else "")))
        return rows

    def tracks_page(uri, offset, limit, invocation):
        kind = _kind_of(uri)
        title = (library_entry(uri).get("title") or _title(kind + "s"))[:1024]
        # An album or a playlist starts with a row that plays it whole, so the
        # rows of the car are one further than the tracks of Spotify.
        head = [] if kind == "show" else [content_item(
            ("play:" + uri)[:256],
            TEXT["play_album"] if kind == "album" else TEXT["play_playlist"],
            kind="action", action="content.select", parameters={"uri": uri})]
        shift = len(head)
        first = max(0, offset - shift)
        count = limit - shift if offset == 0 else limit
        if count <= 0:
            invocation.complete(content_result(content_page(
                uri[:256], title, head[:limit], offset=offset, has_more=True, version=shown["version"],
                **_hints(layout="list"))))
            return

        def answer(status, data):
            if ok(status) and isinstance(data, dict) and isinstance(data.get("items"), list):
                tracks_cache[(uri, first, count)] = (time.monotonic(), data)
                rows = track_rows(kind, data["items"], first)
                total = data.get("total") if isinstance(data.get("total"), int) else 0
                more = bool(rows) and first + len(data["items"]) < total
                items = (head if offset == 0 else []) + rows
                message, message_kind = ("", "none") if items else (TEXT["folder_empty"], "info")
            else:
                items, more = (head if offset == 0 else []), False
                hidden = kind == "playlist" and status in (403, 404)
                message = TEXT["tracks_hidden"] if hidden else TEXT["unreachable"]
                message_kind = "info" if hidden else "warning"
            invocation.complete(content_result(content_page(
                uri[:256], title, items, offset=offset, has_more=more, message=message,
                message_kind=message_kind, version=shown["version"], **_hints(layout="list"))))

        cached = tracks_cache.get((uri, first, count))
        if cached and time.monotonic() - cached[0] < TRACKS_FRESH_SECONDS:
            answer(200, cached[1])
        else:
            remote.call("GET", tracks_request(uri, first, count), answer)

    # --- play queue (side panel) ------------------------------------------------

    def fetch_queue(done, start=True, fresh=QUEUE_FRESH_SECONDS):
        """done(): queue_cache then holds the queue and the player options."""
        if time.monotonic() - queue_cache["time"] < fresh:
            done()
            return

        def got_queue(status, data):
            queue_cache.update(status=status, queue=data if ok(status) and isinstance(data, dict) else None)
            current = (queue_cache["queue"] or {}).get("currently_playing")
            shown["playing"] = str(current.get("uri", "")) if isinstance(current, dict) else ""
            if not ok(status):
                queue_cache.update(time=time.monotonic(), player=None)
                done()
                return
            remote.call("GET", "/me/player", got_player, start)

        def got_player(status, data):
            queue_cache.update(time=time.monotonic(),
                               player=data if ok(status) and isinstance(data, dict) else None)
            done()

        remote.call("GET", "/me/player/queue", got_queue, start)

    def queue_row(index, entry, playing):
        uri = str(entry.get("uri", ""))
        artists = _names(entry.get("artists"))
        if not artists and isinstance(entry.get("show"), dict):
            artists = str(entry["show"].get("name", ""))
        album = entry.get("album") if isinstance(entry.get("album"), dict) else entry
        return content_item("q%d" % index, str(entry.get("name") or uri)[:1024], artists[:1024],
                            kind="action", action="queue.jump", parameters={"steps": str(index)},
                            **_hints(image=_smallest(album.get("images")),
                                     playback="playing" if playing else ""))

    def queue_page(offset, limit):
        queue = queue_cache["queue"]
        if queue is None:
            return content_page(QUEUE, TEXT["queue"], [], message=TEXT["unreachable"],
                                message_kind="warning", version=shown["version"])
        rows = []
        current = queue.get("currently_playing")
        if isinstance(current, dict) and current.get("uri"):
            rows.append(queue_row(0, current, True))
        steps = 0  # how many "next" lead to the row
        for entry in queue.get("queue") or []:
            steps += 1
            if isinstance(entry, dict) and entry.get("uri") and len(rows) < PAGE_MAX:
                rows.append(queue_row(steps, entry, False))
        actions = []
        player = queue_cache["player"]
        if player:
            shuffle = bool(player.get("shuffle_state"))
            repeat = str(player.get("repeat_state") or "off")
            following = {"off": "context", "context": "track", "track": "off"}.get(repeat, "off")
            actions = [
                content_item("shuffle", TEXT["shuffle_on" if shuffle else "shuffle_off"], kind="action",
                             action="player.shuffle", parameters={"state": "false" if shuffle else "true"}),
                content_item("repeat", TEXT.get("repeat_" + repeat, TEXT["repeat_off"]), kind="action",
                             action="player.repeat", parameters={"state": following}),
            ]
        chunk = rows[offset:offset + limit]
        return content_page(QUEUE, TEXT["queue"], chunk, actions=actions, offset=offset,
                            has_more=offset + limit < len(rows),
                            message="" if rows else TEXT["queue_empty"],
                            message_kind="none" if rows else "info", version=shown["version"])

    # --- Content1 queries ---------------------------------------------------------

    def browse(parameters, invocation):
        identity, offset = parameters["id"], parameters["offset"]
        limit = max(1, min(parameters["limit"], PAGE_MAX))
        query = parameters.get("query", "")
        if query:
            invocation.complete(content_result(search_page(query, offset, limit)))
        elif identity == "root":
            invocation.complete(content_result(root_page()))
        elif identity == QUEUE:
            fetch_queue(lambda: invocation.complete(content_result(queue_page(offset, limit))))
        elif _section(identity):
            invocation.complete(content_result(section_page(identity, offset, limit)))
        elif _kind_of(identity) in ("album", "playlist", "show"):
            tracks_page(identity, offset, limit, invocation)
        else:
            raise Fault("NotFound", "content folder is unavailable")

    # --- actions --------------------------------------------------------------------

    def changed():
        """Something shown may have changed: let the car read the pages again."""
        shown["version"] += 1
        backend.publish({"content": root_page()})

    def changed_soon(invocation=None, result=None, delay=SETTLE_MS):
        """Read the queue again once Spotify has settled, then answer."""
        def after():
            fetch_queue(lambda: (changed(),
                                 invocation.complete(result or {}) if invocation else None),
                        start=False, fresh=0)
            return False
        GLib.timeout_add(delay, after)

    def find_player():
        """MPRIS name of Hutspot, recognised by its DesktopEntry."""
        for name in backend.bus.list_names():
            name = str(name)
            if not name.startswith(MPRIS_PREFIX):
                continue
            try:
                obj = backend.bus.get_object(name, MPRIS_PATH, introspect=False)
                entry = obj.Get("org.mpris.MediaPlayer2", "DesktopEntry",
                                dbus_interface=PROPERTIES, timeout=2)
            except dbus.exceptions.DBusException:
                continue
            if str(entry) == DESKTOP_ENTRY or name.endswith("." + DESKTOP_ENTRY):
                return name
        return None

    def open_uri(service, uri, invocation):
        player = backend.bus.get_object(service, MPRIS_PATH, introspect=False)
        player.OpenUri(uri, dbus_interface=MPRIS_PLAYER, timeout=30,
                       reply_handler=lambda *a: changed_soon(invocation, {"uri": uri}, 1500),
                       error_handler=lambda e: invocation.fail("Failed", str(e)))

    def launch():
        for command in (LAUNCH, ["/usr/bin/hutspot"]):
            try:
                subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                 stderr=subprocess.DEVNULL, start_new_session=True)
                return True
            except OSError:
                continue
        return False

    def spotify_uri(parameters):
        uri = str(parameters.get("uri", ""))
        if not uri.startswith("spotify:") or any(c in uri for c in " \t\r\n&?#/"):
            raise Fault("NotFound", "unknown Spotify item")
        return uri

    def select(parameters, invocation):
        """Play an album, a playlist, an episode... now."""
        uri = spotify_uri(parameters)
        service = find_player()
        if service:
            open_uri(service, uri, invocation)
            return
        # Hutspot is not running: start it, then wait for its MPRIS player.
        if not launch():
            invocation.fail("Failed", "Hutspot could not be started")
            return
        state = {"done": False, "tries": 0}

        def poll():
            if state["done"]:
                return False
            state["tries"] += 1
            found = find_player()
            if found:
                state["done"] = True
                # Hutspot also queues the URI until it has a valid token
                GLib.timeout_add(START_DELAY_MS, lambda: (open_uri(found, uri, invocation), False)[1])
                return False
            if state["tries"] >= LAUNCH_TIMEOUT:
                state["done"] = True
                invocation.fail("Failed", "Hutspot did not start")
                return False
            return True

        GLib.timeout_add_seconds(1, poll)

    def queue_add(parameters, invocation):
        """Add a track to the queue. With nothing being played, play it."""
        uri = spotify_uri(parameters)

        def answer(status, data):
            if ok(status):
                changed_soon(invocation, {"uri": uri})
            elif status in (0, 404):
                # no player at the moment (or Hutspot was not running)
                select(parameters, invocation)
            else:
                invocation.fail("Failed", "Spotify refused the track (%d)" % status)

        remote.call("POST", "/me/player/queue?uri=" + quote(uri, safe=""), answer)

    def queue_jump(parameters, invocation):
        """Go to a row of the queue: skip the rows before it."""
        try:
            steps = int(str(parameters.get("steps", "0")))
        except ValueError:
            steps = 0
        steps = max(0, min(steps, PAGE_MAX))
        if steps == 0:
            invocation.complete({})
            return

        def skip(left):
            def answer(status, data):
                if not ok(status):
                    invocation.fail("Failed", "Spotify refused to skip (%d)" % status)
                elif left > 1:
                    GLib.timeout_add(350, lambda: (skip(left - 1), False)[1])
                else:
                    changed_soon(invocation)
            remote.call("POST", "/me/player/next", answer)

        skip(steps)

    def option(path, allowed):
        def handler(parameters, invocation):
            state = str(parameters.get("state", ""))
            if state not in allowed:
                raise Fault("InvalidArgument", "unknown option state")

            def answer(status, data):
                if ok(status):
                    changed_soon(invocation)
                else:
                    invocation.fail("Failed", "Spotify refused the option (%d)" % status)
            remote.call("PUT", "%s?state=%s" % (path, state), answer)
        return handler

    # --- follow the player: the row being played moves by itself -----------------

    def player_signature():
        service = find_player()
        if not service:
            return None
        try:
            obj = backend.bus.get_object(service, MPRIS_PATH, introspect=False)
            metadata = obj.Get(MPRIS_PLAYER, "Metadata", dbus_interface=PROPERTIES, timeout=2)
        except dbus.exceptions.DBusException:
            return None
        return (str(metadata.get("xesam:title", "")), str(metadata.get("xesam:album", "")))

    def check():
        shown["check"] = 0
        if not backend.session_count:
            return False
        current = player_signature()
        if current != shown["signature"]:
            shown["signature"] = current
            changed_soon(delay=300)
        return False

    def check_soon(*args, **kwargs):
        if not shown["check"]:
            shown["check"] = GLib.timeout_add(800, check)

    backend = ContentBackend(SERVICE, APPLICATION_ID,
                             {"content.browse": browse, "content.search": browse,
                              "content.select": select, "queue.add": queue_add,
                              "queue.jump": queue_jump,
                              "player.shuffle": option("/me/player/shuffle", ("true", "false")),
                              "player.repeat": option("/me/player/repeat", ("off", "context", "track"))},
                             {"content": root_page()}, on_lifecycle=lifecycle)
    remote = Remote(backend.bus)
    if HINTS:
        backend.bus.add_signal_receiver(check_soon, signal_name="PropertiesChanged",
                                        dbus_interface=PROPERTIES, path=MPRIS_PATH, arg0=MPRIS_PLAYER)
    backend.bus.call_on_disconnection(lambda connection: loop.quit())
    for number in (signal.SIGINT, signal.SIGTERM):
        signal.signal(number, lambda number, frame: loop.quit())
    lifecycle(backend)
    try:
        loop.run()
    finally:
        if idle[0]:
            GLib.source_remove(idle[0])
        backend.close()


if __name__ == "__main__":
    main()
