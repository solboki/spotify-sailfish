import QtQuick 2.6
import Nemo.DBus 2.0
import "../Spotify.js" as Spotify

// D-Bus name of the app. Sailplay uses it to start Hutspot from the car
// (D-Bus activation, see /usr/share/dbus-1/services/org.solboki.hutspot.service).
// What to play arrives through MPRIS (OpenUri).
//
// The "Browse" page of the car (python/sailplay_service.py) also asks here for
// what only the app can get from Spotify: the tracks of an album, the play
// queue, the shuffle and repeat options. The app holds the session and renews
// it; the service never sees a token. Only the requests listed in carRoutes
// are accepted. The answer comes back in the "reply" signal.
// Loaded by a Loader: without Nemo.DBus the app works as before.
DBusAdaptor {
    bus: DBus.SessionBus
    service: "org.solboki.hutspot"
    path: "/app"
    iface: "org.solboki.HutspotApp"
    xml: '<interface name="org.solboki.HutspotApp">\n'
         + '  <method name="playUri">\n'
         + '    <arg name="uri" type="s" direction="in"/>\n'
         + '    <arg name="accepted" type="b" direction="out"/>\n'
         + '  </method>\n'
         + '  <method name="request">\n'
         + '    <arg name="id" type="s" direction="in"/>\n'
         + '    <arg name="method" type="s" direction="in"/>\n'
         + '    <arg name="path" type="s" direction="in"/>\n'
         + '    <arg name="body" type="s" direction="in"/>\n'
         + '    <arg name="accepted" type="b" direction="out"/>\n'
         + '  </method>\n'
         + '  <signal name="reply">\n'
         + '    <arg name="id" type="s"/>\n'
         + '    <arg name="status" type="s"/>\n'
         + '    <arg name="body" type="s"/>\n'
         + '  </signal>\n'
         + '</interface>\n'

    function playUri(uri) {
        app.playFromRemote(uri)
        return true
    }

    readonly property var carRoutes: [
        ["GET",  /^\/albums\/[A-Za-z0-9]+\/tracks\?[a-z_=&0-9]*$/],
        ["GET",  /^\/playlists\/[A-Za-z0-9]+\/items\?[a-z_=&0-9]*$/],
        ["GET",  /^\/shows\/[A-Za-z0-9]+\/episodes\?[a-z_=&0-9]*$/],
        ["GET",  /^\/me\/player\/queue$/],
        ["GET",  /^\/me\/player$/],
        ["POST", /^\/me\/player\/queue\?uri=spotify%3A(track|episode)%3A[A-Za-z0-9]+$/],
        ["POST", /^\/me\/player\/next$/],
        ["PUT",  /^\/me\/player\/shuffle\?state=(true|false)$/],
        ["PUT",  /^\/me\/player\/repeat\?state=(off|context|track)$/]
    ]

    function request(id, method, path, body) {
        var allowed = false
        for (var i = 0; i < carRoutes.length && !allowed; i++)
            allowed = carRoutes[i][0] === method && carRoutes[i][1].test(path)
        if (!allowed) {
            console.log("car request refused: " + method + " " + path)
            return false
        }
        Spotify.apiRequest(method, path, function(error, data) {
            var status = error ? (error.status ? error.status : 0) : 200
            var text = ""
            if (!error && data) {
                try { text = JSON.stringify(data) } catch (e) { text = "" }
            }
            emitSignal("reply", ["" + id, "" + status, text])
            // a queue or an option changed from the car: show it on the phone too
            if (method !== "GET")
                app.controller.delayedRefreshPlaybackState()
        })
        return true
    }
}
