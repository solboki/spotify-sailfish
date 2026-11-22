import QtQuick 2.6
import Nemo.DBus 2.0

// D-Bus name of the app. Sailplay uses it to start Hutspot from the car
// (D-Bus activation, see /usr/share/dbus-1/services/org.solboki.hutspot.service).
// What to play arrives through MPRIS (OpenUri).
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
         + '</interface>\n'

    function playUri(uri) {
        app.playFromRemote(uri)
        return true
    }
}
