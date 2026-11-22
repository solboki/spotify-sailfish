import QtQuick 2.6
import Nemo.Policy 1.0
import Sailfish.Media 1.0

// Headset buttons (wired or Bluetooth). On Sailfish an app must reserve the
// buttons with the resource manager, as a player, and then listen to the
// media keys. Loaded by a Loader: without these modules the app works as
// before.
Item {
    readonly property bool active: app.playbackState.item
                                   && app.playbackState.item.duration_ms > 0

    Permissions {
        enabled: active
        autoRelease: true
        applicationClass: "player"

        Resource {
            id: keysResource
            type: Resource.HeadsetButtons
            optional: true
        }
    }

    MediaKey {   // single button of wired headsets
        enabled: keysResource.acquired
        key: Qt.Key_ToggleCallHangup
        onReleased: app.controller.playPause()
    }
    MediaKey {
        enabled: keysResource.acquired
        key: Qt.Key_MediaTogglePlayPause
        onReleased: app.controller.playPause()
    }
    MediaKey {
        enabled: keysResource.acquired
        key: Qt.Key_MediaPlay
        onReleased: app.controller.play()
    }
    MediaKey {
        enabled: keysResource.acquired
        key: Qt.Key_MediaPause
        onReleased: app.controller.pause()
    }
    MediaKey {
        enabled: keysResource.acquired
        key: Qt.Key_MediaStop
        onReleased: app.controller.pause()
    }
    MediaKey {
        enabled: keysResource.acquired
        key: Qt.Key_MediaNext
        onReleased: app.controller.next()
    }
    MediaKey {
        enabled: keysResource.acquired
        key: Qt.Key_MediaPrevious
        onReleased: app.controller.previous()
    }
}
