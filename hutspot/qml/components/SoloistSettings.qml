/**
 * Réglages de Spotify Soloist, le lecteur qui joue sur le téléphone :
 * état de la connexion, réappairage et nouvelle clé d'API.
 * S'appuie sur les scripts de /usr/share/hutspot/scripts.
 *
 * License: MIT
 */

import QtQuick 2.0
import Sailfish.Silica 1.0
import org.hildon.components 1.0

Column {
    id: soloist
    width: parent.width
    spacing: Theme.paddingMedium

    readonly property string scripts: "/usr/share/hutspot/scripts/"
    property string loginState: ""   // yes, no, stopped
    property bool busy: process.state !== Processes.NotRunning
    property string task: ""         // pair, setkey, state
    property string message: ""
    property string _output: ""

    SectionHeader {
        text: qsTr("Player on the phone (Soloist)")
    }

    Label {
        x: Theme.horizontalPageMargin
        width: parent.width - 2*Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        color: loginState === "yes" ? Theme.highlightColor : Theme.errorColor
        text: {
            switch(loginState) {
            case "yes": return qsTr("Connected to your Spotify account")
            case "no": return qsTr("Not paired: use Pair again")
            case "stopped": return qsTr("Soloist is not running")
            }
            return qsTr("Checking…")
        }
    }

    Label {
        x: Theme.horizontalPageMargin
        width: parent.width - 2*Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        visible: message.length > 0
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.secondaryHighlightColor
        text: message
    }

    BusyIndicator {
        anchors.horizontalCenter: parent.horizontalCenter
        size: BusyIndicatorSize.Medium
        running: busy && task !== "state"
        visible: running
    }

    Button {
        anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("Pair again")
        enabled: !busy
        onClicked: {
            message = qsTr("Starting…")
            run("pair", ["180"])
        }
    }

    Label {
        x: Theme.horizontalPageMargin
        width: parent.width - 2*Theme.horizontalPageMargin
        wrapMode: Text.Wrap
        font.pixelSize: Theme.fontSizeExtraSmall
        color: Theme.secondaryColor
        text: qsTr("Needed after a new key or if the phone no longer appears in Spotify. Then choose the phone in a Spotify app (computer, other phone) on the same Wi-Fi.")
    }

    PasswordField {
        id: keyField
        width: parent.width
        label: qsTr("New Soloist key")
        placeholderText: qsTr("New Soloist key (spak_…)")
        enabled: !busy
        EnterKey.enabled: text.length > 0
        EnterKey.iconSource: "image://theme/icon-m-enter-accept"
        EnterKey.onClicked: saveKey()
    }

    Button {
        anchors.horizontalCenter: parent.horizontalCenter
        text: qsTr("Save the key")
        enabled: !busy && keyField.text.length > 0
        onClicked: saveKey()
    }

    function saveKey() {
        if(keyField.text.length === 0)
            return
        message = qsTr("Saving the key and restarting Soloist…")
        run("setkey", [])
        // the key goes through the standard input, never as an argument
        process.write(keyField.text + "\n")
        process.closeWriteChannel()
        keyField.text = ""
    }

    function run(name, args) {
        task = name
        _output = ""
        var file = name === "pair" ? "soloist-pair.sh"
                 : name === "setkey" ? "soloist-setkey.sh" : "soloist-state.sh"
        process.start("/bin/bash", [scripts + file].concat(args))
    }

    function refreshState() {
        if(!busy)
            run("state", [])
    }

    Process {
        id: process
        onReadyReadStandardOutput: {
            var text = readAllStandardOutput()
            _output += text
            var lines = text.split("\n")
            for(var i=0;i<lines.length;i++) {
                var l = lines[i].trim()
                if(l === "WAITING")
                    message = qsTr("Choose “%1” in a Spotify app on the same Wi-Fi (3 minutes).").arg("JollaPhone")
                else if(l.indexOf("STATE ") === 0)
                    soloist.loginState = l.substring(6)
                else if(task === "state" && (l === "yes" || l === "no" || l === "stopped"))
                    soloist.loginState = l
            }
        }
        onFinished: {
            var m = _output.match(/RESULT (\w+)/)
            var result = m ? m[1] : ""
            switch(task + ":" + result) {
            case "pair:ok": message = qsTr("Paired. Soloist is connected."); break
            case "pair:timeout": message = qsTr("No Spotify app chose the phone in time."); break
            case "pair:nokey": message = qsTr("Save a Soloist key first."); break
            case "pair:failed": message = qsTr("Soloist could not be started."); break
            case "setkey:ok": message = qsTr("Key saved. Soloist is connected."); break
            case "setkey:needpair": message = qsTr("Key saved. Now pair the phone again."); break
            case "setkey:invalid": message = qsTr("This is not a Soloist key (it starts with spak_)."); break
            case "setkey:failed": message = qsTr("Key saved, but Soloist did not restart."); break
            default:
                if(task !== "state")
                    message = ""
            }
            if(task !== "state")
                app.controller.reloadDevices()
            task = ""
        }
    }

    Component.onCompleted: refreshState()
}
