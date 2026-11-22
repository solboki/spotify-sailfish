#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sailplay service of Hutspot: "Browse" button of the car Music card.

Shows the user's Spotify library on the car screen (Content1 contract of the
Sailplay SDK): playlists, saved albums, podcasts, audiobooks and recently
played tracks. Choosing an entry sends its Spotify URI to Hutspot with the
standard MPRIS OpenUri command, starting Hutspot first if needed.

The library comes from a summary that Hutspot keeps in its LocalStorage
database (key "car_library"), so this service needs no Spotify token.
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

sys.path.insert(0, "/opt/sailplay")

import dbus  # noqa: E402
import dbus.mainloop.glib  # noqa: E402
from gi.repository import GLib  # noqa: E402

from sailplay_sdk.content import ContentBackend, wire_content  # noqa: E402
from sailplay_sdk.content_model import content_item, content_page  # noqa: E402
from sailplay_sdk.model import Fault  # noqa: E402

SERVICE = "org.solboki.Hutspot"
APPLICATION_ID = "hutspot"
MPRIS_PREFIX = "org.mpris.MediaPlayer2."
DESKTOP_ENTRY = "hutspot"
MPRIS_PATH = "/org/mpris/MediaPlayer2"
MPRIS_PLAYER = "org.mpris.MediaPlayer2.Player"
LAUNCH = ["/usr/bin/invoker", "--type=silica-qt5", "--single-instance", "/usr/bin/hutspot"]
LAUNCH_TIMEOUT = 40
# time left to Hutspot to get its Spotify token before playing
START_DELAY_MS = 4000
IDLE_SECONDS = 10
PAGE_MAX = 50

HOME = os.path.expanduser("~")

_FR = os.environ.get("LANG", "").startswith("fr")
SECTIONS = [
    ("playlists", "Playlists", "Playlists"),
    ("albums", "Albums", "Albums"),
    ("shows", "Podcasts", "Podcasts"),
    ("audiobooks", "Livres audio", "Audiobooks"),
    ("recent", "Écoutés récemment", "Recently played"),
]
TEXT = {
    "empty": ("Ouvrez Hutspot une fois sur le téléphone pour charger la bibliothèque"
              if _FR else "Open Hutspot once on the phone to load the library"),
    "folder_empty": "Rien ici" if _FR else "Nothing here",
    "none": "Aucun résultat" if _FR else "No results",
}


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
        return json.loads(best[0])
    except ValueError:
        return None


def _title(key):
    for k, fr, en in SECTIONS:
        if k == key:
            return fr if _FR else en
    return key


def _entry_item(entry):
    uri = str(entry.get("uri", ""))
    return content_item(uri[:256], (entry.get("title") or uri)[:1024],
                        (entry.get("subtitle") or "")[:1024],
                        kind="action", action="content.select", parameters={"uri": uri})


def page(identity, offset, limit, query=""):
    limit = max(1, min(limit, PAGE_MAX))
    lib = load_library()
    if lib is None:
        return content_page(identity, "Spotify", [], search_enabled=False,
                            message=TEXT["empty"], message_kind="info")
    if query:
        q = query.casefold()
        entries, seen = [], set()
        for key, _fr, _en in SECTIONS:
            for e in lib.get(key, []):
                text = ("%s %s" % (e.get("title", ""), e.get("subtitle", ""))).casefold()
                if q in text and e.get("uri") not in seen:
                    seen.add(e.get("uri"))
                    entries.append(e)
        chunk = entries[offset:offset + limit]
        return content_page(identity, query, [_entry_item(e) for e in chunk],
                            search_enabled=True, offset=offset,
                            has_more=offset + limit < len(entries),
                            message="" if entries else TEXT["none"],
                            message_kind="none" if entries else "info")
    if identity == "root":
        folders = [content_item(key, _title(key), "%d" % len(lib.get(key, [])))
                   for key, _fr, _en in SECTIONS if lib.get(key)]
        return content_page("root", "Spotify", folders, search_enabled=True,
                            message="" if folders else TEXT["empty"],
                            message_kind="none" if folders else "info")
    if identity not in [k for k, _fr, _en in SECTIONS]:
        raise Fault("NotFound", "content folder is unavailable")
    entries = lib.get(identity, [])
    chunk = entries[offset:offset + limit]
    return content_page(identity, _title(identity), [_entry_item(e) for e in chunk],
                        search_enabled=True, offset=offset,
                        has_more=offset + limit < len(entries),
                        message="" if entries else TEXT["folder_empty"],
                        message_kind="none" if entries else "info")



def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()
    idle = [0]

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

    def browse(parameters, invocation):
        result = page(str(parameters.get("id", "root")), int(parameters.get("offset", 0)),
                      int(parameters.get("limit", PAGE_MAX)), str(parameters.get("query", "")))
        invocation.complete({"content": wire_content(result)})

    def find_player():
        """MPRIS name of Hutspot, recognised by its DesktopEntry."""
        for name in backend.bus.list_names():
            name = str(name)
            if not name.startswith(MPRIS_PREFIX):
                continue
            try:
                obj = backend.bus.get_object(name, MPRIS_PATH, introspect=False)
                entry = obj.Get("org.mpris.MediaPlayer2", "DesktopEntry",
                                dbus_interface="org.freedesktop.DBus.Properties", timeout=2)
            except dbus.exceptions.DBusException:
                continue
            if str(entry) == DESKTOP_ENTRY or name.endswith("." + DESKTOP_ENTRY):
                return name
        return None

    def open_uri(service, uri, invocation):
        player = backend.bus.get_object(service, MPRIS_PATH, introspect=False)
        player.OpenUri(uri, dbus_interface=MPRIS_PLAYER, timeout=30,
                       reply_handler=lambda *a: invocation.complete({"uri": uri}),
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

    def select(parameters, invocation):
        uri = str(parameters.get("uri", ""))
        if not uri.startswith("spotify:"):
            raise Fault("NotFound", "unknown Spotify item")
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

    root = page("root", 0, PAGE_MAX)
    backend = ContentBackend(SERVICE, APPLICATION_ID,
                             {"content.browse": browse, "content.search": browse,
                              "content.select": select},
                             {"content": root}, on_lifecycle=lifecycle)
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
