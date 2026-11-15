import QtQuick 2.0
import Nemo.Notifications 1.0

// Short messages shown as a standard Sailfish notification banner at the
// top of the screen (transient: nothing is left in the notification list).
Item {
    id: messagebox

    Notification {
        id: banner
        appName: "Hutspot"
        appIcon: "hutspot"
        isTransient: true
        urgency: Notification.Normal
    }

    function showMessage(message, delay) {
        banner.close()
        banner.previewSummary = ""
        // texts can contain a little HTML (<b>, <br>): the banner shows plain text
        banner.previewBody = message.replace(/<br\s*\/?>/gi, " ").replace(/<[^>]*>/g, "")
        banner.expireTimeout = (delay > 0) ? delay : 3000
        banner.publish()
    }
}
