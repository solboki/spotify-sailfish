import QtQuick 2.2
import Sailfish.Silica 1.0

IconButton {
    id: menuIcon

    anchors.verticalCenter: parent._titleItem.verticalCenter
    anchors.right: parent._titleItem.left
    icon.height: Theme.iconSizeSmall
    icon.fillMode: Image.PreserveAspectFit
    icon.source: app.navigation_menu_type.value === 0
                 ? "image://theme/icon-m-menu"
                 : "image://hutspot-icons/icon-m-toolbar"

    // show button only when not having a panel or menu is not an attached page
    // Navigation now uses the pull-down menu of each page (NavigationPullDown)
    enabled: false

    visible: enabled

    onClicked: {
        if(app.navigation_menu_type.value === 0 ) {
            // menu using dialog
            var dialog = pageStack.push(Qt.resolvedUrl("NavigationMenuDialog.qml")) //, {}, PageStackAction.Immediate)
            dialog.done.connect(function() {
                if(dialog.selectedMenuItem > -1)
                    app.doSelectedMenuItem(dialog.selectedMenuItem)
            })
        } else {
            // menu using docked panel
            if(!app.dockedPanel.open)
                app.dockedPanel.open = true
            if(!app.dockedPanel.modal)
                app.dockedPanel.modal = true
            if(!app.dockedPanel.visible)
                app.dockedPanel.visible = true
        }
    }
}
