*English | [Français](README.fr.md)*

# Native Spotify on Sailfish OS (Jolla Phone)

A personal project, shared for testing. It gathers everything needed to listen to Spotify natively on a Jolla Phone, without the Android app, and to browse the library from a car screen through [Sailplay](https://github.com/0312birdzhang/harbour-sailplay).

Two pieces do the work:

- **Spotify Soloist**, the official Spotify player for Linux, plays the music on the phone and shows up as a Spotify Connect device.
- **Hutspot**, a free Sailfish application, is the remote control. Its original version no longer worked with the 2026 Spotify API; this repository contains an adapted fork.

Librespot is not used: since 2025-2026 Spotify refuses decryption keys to recent accounts (error `audio key 0 1`), and there is no workaround.

## Before you try it

- A **Spotify Premium** account is required (Soloist and the playback API need it).
- **Soloist is not included.** It is proprietary and must be downloaded from Spotify. Each build stops working 90 days after it was compiled.
- **The Spotify application ID built into Hutspot belongs to its original author and is limited to five users.** Someone outside that list can most likely not log in to Hutspot. The code, the car service and the D-Bus interface can still be read and reviewed without logging in; see [Sailplay integration](#sailplay-integration-car-screen).
- Everything was built and tested on one device: a Jolla Phone (aarch64) with Sailfish OS 5.

## What is in this repository

| Folder | Content |
|---|---|
| `hutspot/` | Source code of the fork, with the full history of the original project (MIT licence) |
| `soloist-audiores/` | Companion program: Soloist launcher, audio-role fix, systemd service file |
| `soloist-netwatch/` | Companion program: restarts Soloist after a network change |
| `releases/` | Every delivered version, ready to install |
| `binaires/` | The compiled part of Hutspot, ready to copy to the phone without recompiling |

## Full installation on a fresh phone

### 1. Create a Soloist key and download Soloist

1. Sign in to Spotify for Developers (developer.spotify.com) with the Premium account.
2. Create a **Soloist API key**, following the Soloist documentation there. The key starts with `spak_`. Keep it for step 4.
3. Download `soloist_release_arm64.tar.gz` from the "Downloads and updates" page of the Soloist documentation and copy it to the phone.

Then, in a terminal on the phone:

```
devel-su pkcon install libatomic
mkdir -p ~/soloist && tar -xzf soloist_release_arm64.tar.gz -C ~/soloist
```

If Spotify stops playing one day, download Soloist again first (90-day limit).

### 2. Install Hutspot and the fork

Install Hutspot from Chum, then the MPRIS module its interface needs:

```
devel-su pkcon install mpris-qt5-qml-plugin
```

Then install the latest version of the fork:

```
tar xzf releases/hutspot-fork-0.16.0.tar.gz && cd hutspot-fork-0.16.0
devel-su sh install-hutspot-fork.sh
```

The script backs up the original files, then installs:

- the interface (QML) and the French translation;
- a replacement `.desktop` file: SailJail sandbox disabled (otherwise the login is asked again at every start), audio-player category, Sailplay declaration;
- the "Browse" service for the car screen, with its D-Bus activation files;
- the Soloist scripts used by the Settings page (`/usr/share/hutspot/scripts/`).

`uninstall-hutspot-fork.sh` reverts everything. A Hutspot update from Chum overwrites the fork: run the install script again.

The fork also needs its own compiled program (network fixes, session handling). Either copy the one from `binaires/`, after checking it was not damaged in transfer:

```
cd binaires && sha256sum -c SHA256SUMS
devel-su cp /usr/bin/hutspot /usr/bin/hutspot.orig    # first time only
devel-su install -m 755 hutspot-0.13.0-aarch64 /usr/bin/hutspot
```

or compile it on the phone (a few minutes) with `build-hutspot-binary.sh` from the release folder. The program in `binaires/` was compiled in November 2026 on Sailfish OS 5 for the Jolla Phone (64-bit ARM). If a major Sailfish update changes the Qt version it may no longer start: recompile it.

### 3. Install the launcher and the volume fix (`soloist-audiores`)

Without it, the volume keys set the ringtone instead of the music, and Soloist plays over other players.

- The launcher `soloist-audiores` follows Soloist's playback state through its local interface (`--ws` option). It reserves the "audio playback" resource from the Sailfish resource manager when music starts, releases it on pause, and pauses Soloist when another application (or a call) takes the resource.
- The library `libforcerole` replaces the `music` role of Soloist's audio stream with `x-maemo`, the only role the volume keys apply to.

```
devel-su pkcon install gcc libresource-devel glib2-devel
tar xzf releases/soloist-audiores-2.1.0.tar.gz && cd soloist-audiores-2.1.0
sh install.sh
systemctl --user enable soloist
```

The installer ends by printing the state of the `soloist` service. If it is not `active` at this point, continue: the key is only saved in the next step. The launcher's log is `~/.cache/soloist-audiores.log`.

### 4. Enter the Soloist key in Hutspot

1. Open Hutspot, then **Settings**, section **Player on the phone (Soloist)**.
2. Paste the key in **New Soloist key** and tap **Save the key**. Hutspot stores it in `~/.config/soloist/env` (readable by the user only) and restarts Soloist.
3. The status line then reads either "Connected to your Spotify account" or "Not paired: use Pair again".

The same can be done from a terminal; the key is asked without being displayed:

```
/usr/share/hutspot/scripts/soloist-setkey.sh
```

### 5. Pair the phone with the Spotify account

1. In the same Settings section, tap **Pair again**.
2. Within three minutes, open a Spotify app on another device (computer, other phone) **on the same Wi-Fi** and choose the device "JollaPhone".
3. Hutspot shows "Paired. Soloist is connected."

Terminal equivalent: `/usr/share/hutspot/scripts/soloist-pair.sh`. To check the session: `~/soloist/soloist ctl status` shows `logged in: yes`.

Changing or revoking the key cancels the session: pair again afterwards.

Finally, log in to the Spotify account in Hutspot itself (see the five-user limit above) and choose "JollaPhone" on its Devices page.

### 6. Automatic restart after a network change (`soloist-netwatch`)

Soloist does not restore its connection to Spotify's servers when the phone changes network (Wi-Fi to mobile data, another Wi-Fi) or loses internet for a few seconds: it then disappears from the device list. The `soloist-netwatch` service watches the network and restarts Soloist once the connection is stable. It also restarts Soloist when it loses its session, and leaves it alone while it waits for pairing.

```
tar xzf releases/soloist-netwatch-1.3.0.tar.gz && cd soloist-netwatch-1.3.0
sh install.sh
```

The restart log is `~/.cache/soloist-netwatch.log`. Delays are set in `~/.config/soloist/netwatch.conf` (template: `netwatch.conf.example`).

## Sailplay integration (car screen)

This section is for the Sailplay developer and anyone adapting another music application.

### What the fork does

- **Playback on the car screen.** Hutspot exposes an MPRIS player (`hutspot/qml/components/PlaybackState.qml`): title, cover, progress bar, seeking, previous / play-pause / next.
- **"Browse" page.** A separate service, `hutspot/python/sailplay_service.py`, answers Sailplay's `content.browse` requests using the Sailplay SDK from `/opt/sailplay`. Without Sailplay installed the service does not start and Hutspot works as before.

### Declaration

The `.desktop` file of the fork (in each release archive) declares:

```
Categories=AudioVideo;Audio;Player;
X-Sailplay-ApiVersion=1
X-Sailplay-Service=org.solboki.Hutspot
X-Sailplay-ObjectPath=/org/sailplay/v1/App
X-Sailplay-Presentation=template
X-Sailplay-Capabilities=content;
X-Sailplay-BackgroundService=org.solboki.hutspot
```

Two D-Bus activation files are installed in `/usr/share/dbus-1/services/`:

| Bus name | Started program | Role |
|---|---|---|
| `org.solboki.Hutspot` | `python3 /usr/share/hutspot/python/sailplay_service.py` | Content service for Sailplay; stops after ten idle seconds |
| `org.solboki.hutspot` | `/usr/bin/hutspot` (single instance) | The application itself, started from the car when needed |

### The "Browse" page

It uses the music arrangement of the presentation hints proposed in [harbour-sailplay pull request #9](https://github.com/0312birdzhang/harbour-sailplay/pull/9):

```
root          tabs=true, side="queue"   Playlists, Albums, Podcasts, Audiobooks, Recent
  Albums      cards with cover          one album per card
    <album>   list                      first row plays the whole album;
                                        a track adds itself to the play queue
  queue       side panel (right)        play queue, current track marked "playing",
                                        options Shuffle and Repeat
```

With a Sailplay that does not know the hints (the official one today), the service detects it at import time and the same pages are shown as plain lists.

After each action that changes the queue or an option, the service raises the `version` of the root page and publishes it again, so that Sailplay reloads the side panel.

### Where the data comes from, and where the token stays

- Tabs and cards come from a summary of the library that Hutspot keeps in its LocalStorage database (key `car_library`). They appear at once, even without network.
- Tracks, the queue and the options are asked to the running Hutspot over D-Bus: method `request(id, method, path, body)` and signal `reply(id, status, body)` on interface `org.solboki.HutspotApp`, object `/app`, bus name `org.solboki.hutspot` (`hutspot/qml/components/DBusControl.qml`).
- Hutspot alone holds the Spotify session and renews it. **The car service never sees a token.**
- Hutspot only accepts a closed list of requests (`carRoutes` in `DBusControl.qml`): tracks of an album, items of a playlist, episodes of a show, reading the player and the queue, adding a track or episode to the queue, next, shuffle, repeat. Anything else is refused.

### Test status

Used in a car on 25 November 2026 (Fiat Scudo 2024, wireless CarPlay) with a Sailplay test build that includes the presentation hints: tabs, cards, adding tracks to the queue, Shuffle and Repeat all worked.

The service can also be exercised without a car and without a Spotify account: a stub application answering on another bus name, a fake Spotify HTTP server, and the service started with the environment variables `HUTSPOT_APP_SERVICE` and `HUTSPOT_CAR_SERVICE` set to test names, the host being simulated with `sailplay_sdk.content.ContentClient`.

## Versions

### Hutspot fork

| Version | Content |
|---|---|
| 0.5.1 | Adaptation to the February 2026 Spotify API |
| 0.6.0 | French interface, Sailfish pulley menu, mini player |
| 0.7.0 | "Featured" page, album sorting (title, artist, genre, date) |
| 0.8.0 | Podcasts and audiobooks, cache of the album list |
| 0.9.0 | Add to library (star, long press); touching a title plays it |
| 0.9.1 | Cover on the lock screen (Amber MPRIS), Sailfish notifications |
| 0.9.2 | Playback resumes when the Spotify session has disappeared (Soloist restart) |
| 0.9.3 | JollaPhone stays in the device list on mobile data |
| 0.10.0 | Car screen (Sailplay): progress bar and seeking, "Browse" button, start from the car; headset buttons |
| 0.11.0 | Settings: Soloist state, "Pair again", new key; scripts `soloist-pair.sh` and `soloist-setkey.sh` |
| 0.12.0 | Compiled part fixed: network requests work again after switching between Wi-Fi and mobile data (Qt 5 defect); compilation on the phone with `build-hutspot-binary.sh` |
| 0.12.1 | Faster recovery after a network change: Qt forgets the connections of the old network, requests unanswered for 12 s are cancelled, playback state is rechecked every 2 s while Spotify is unreachable; no more 403 error on the first tap when the displayed state was stale; the build script installs with zypper |
| 0.13.0 | Account session robust to network changes: a network failure during token renewal no longer erases the session (only an explicit refusal from Spotify does); background renewal with silent retries; a request refused for an expired token waits for the new token and is sent again; no more "Network connection lost. Quit?" dialog or login page opening by itself; network error banners limited to one per minute; "Manage network connection" setting removed |
| 0.14.0 | Car "Browse" page (Sailplay presentation hints): tabs Albums, Playlists, Podcasts, Audiobooks, Recent; cards with cover; tracks of an album or playlist, a tap adds to the queue; right panel with the play queue, Shuffle and Repeat. Tracks and queue are requested from Hutspot over D-Bus (closed list of requests); the service sees no token. Compiled part unchanged (0.13.0). Falls back to plain lists with the official Sailplay |
| 0.15.0 | Car screen (Sailplay 0.1.1-158 and later): the mode button of the player sets normal playback, repeat track, repeat list and shuffle (MPRIS `LoopStatus` and `Shuffle`); timed lyrics, asked to lrclib.net when the setting "Lyrics on the car screen" is on (off by default) |
| 0.16.0 | Car screen: the Spotify play queue is served to the "Queue" button of the Sailplay player (capability `queue`, actions `queue.read` and `queue.play`); needs a Sailplay that knows this capability, no effect with the others |

The archive `hutspot-rpm-0.7.0.tar.gz` contains an RPM build file, unused: installation by script was preferred.

### soloist-audiores

| Version | Content |
|---|---|
| 1.2.0 | Launcher, `x-maemo` audio role, interception of PulseAudio loading |
| 2.0.0 | Hand-over with other players (Audiobook, SailCast): Soloist pauses the application that was playing, and pauses itself when another takes over |
| 2.1.0 | PulseAudio monitoring: Soloist pauses when another player starts, even if Sailfish does not report the loss of the resource; log in `~/.cache/soloist-audiores.log` |

### soloist-netwatch

| Version | Content |
|---|---|
| 1.0.0 | Restarts Soloist after a network change or an internet outage |
| 1.0.1 | Internet test without the `timeout` command, absent from Sailfish OS |
| 1.1.0 | Ignores the launcher's `soloist ctl` commands |
| 1.2.0 | No longer restarts a Soloist that is logged out (waiting for pairing) |
| 1.3.0 | Also restarts when Soloist loses its session; restarts at the latest 45 s after a network change even if the internet test fails; internet test on several servers |

## Known limits

- **Mobile data.** Local discovery (mDNS) is impossible there: Spotify then no longer lists JollaPhone among the devices, although it still accepts commands sent to its identifier. Since 0.9.3 Hutspot adds the last chosen device to the list itself. If that device is not the phone, it stays listed even when switched off.
- **Closed parts of the Spotify API.** For applications in developer mode Spotify has closed editorial new releases, categories, recommendations, radio, and the content of playlists one does not own. The "Featured" page is rebuilt from what remains open.
- **Application ID.** The one built into Hutspot is its original author's, limited to five users: it is not suitable for public distribution.

## Licences

Hutspot's code is under the MIT licence (Willem-Jan de Hoog and contributors); the fork's modifications follow the same licence. Soloist is proprietary Spotify software and is not included. The Sailplay SDK used by the car service is provided by Sailplay (GPL-3.0-or-later) and is not copied here.
