/**
 * Page of a podcast (show) or an audiobook: description, episodes or
 * chapters, play and save to the library.
 *
 * License: MIT
 */

import QtQuick 2.2
import Sailfish.Silica 1.0

import "../components"
import "../Spotify.js" as Spotify
import "../Util.js" as Util

Page {
    id: showPage
    objectName: "ShowPage"

    // a show or an audiobook object (simplified or full)
    property var show
    readonly property bool isAudiobook: show && show.type === "audiobook"

    property bool showBusy: false
    property bool isSaved: false
    property bool descriptionExpanded: false

    allowedOrientations: Orientation.All

    ListModel {
        id: itemsModel
    }

    SilicaListView {
        id: listView
        model: itemsModel

        width: parent.width
        anchors.top: parent.top
        height: parent.height - app.dockedPanel.visibleSize
        clip: app.dockedPanel.expanded

        PullDownMenu {
            MenuItem {
                text: isSaved ? qsTr("Remove from Library") : qsTr("Save to Library")
                onClicked: toggleSaved()
            }
            MenuItem {
                text: isAudiobook ? qsTr("Play the Audiobook") : qsTr("Play the Podcast")
                onClicked: playItem(null)
            }
        }

        header: Column {
            width: parent.width - 2*Theme.horizontalPageMargin
            x: Theme.horizontalPageMargin
            spacing: Theme.paddingMedium

            PageHeader {
                width: parent.width
                title: show ? show.name : ""
                description: isAudiobook ? qsTr("Audiobook") : qsTr("Podcast")
            }

            Row {
                width: parent.width
                spacing: Theme.paddingLarge

                Image {
                    id: cover
                    width: Theme.itemSizeHuge * 1.5
                    height: width
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    source: (show && show.images && show.images.length > 0)
                            ? show.images[0].url : "image://theme/icon-l-music"
                }

                Column {
                    width: parent.width - cover.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.paddingSmall

                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        color: Theme.highlightColor
                        visible: text.length > 0
                        text: {
                            if(!show)
                                return ""
                            if(isAudiobook && show.authors)
                                return Util.createItemsString(show.authors, "")
                            return ""
                        }
                    }
                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                        text: {
                            if(!show)
                                return ""
                            if(isAudiobook)
                                return (show.total_chapters ? show.total_chapters + " " + qsTr("chapters") : "")
                            return (show.total_episodes ? show.total_episodes + " " + qsTr("episodes") : "")
                        }
                    }
                    Button {
                        text: qsTr("Play")
                        preferredWidth: Theme.buttonWidthSmall
                        onClicked: playItem(null)
                    }
                }
            }

            Label {
                id: descriptionLabel
                width: parent.width
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.secondaryColor
                maximumLineCount: descriptionExpanded ? 1000 : 4
                elide: Text.ElideRight
                text: show && show.description ? show.description : ""
                visible: text.length > 0
                MouseArea {
                    anchors.fill: parent
                    onClicked: descriptionExpanded = !descriptionExpanded
                }
            }

            SectionHeader {
                x: 0
                width: parent.width
                text: isAudiobook ? qsTr("Chapters") : qsTr("Episodes")
            }
        }

        delegate: ListItem {
            width: parent.width
            contentHeight: Theme.itemSizeLarge

            SearchResultListItem {
                dataModel: model
            }

            onClicked: playItem(item)
        }

        VerticalScrollDecorator {}

        ViewPlaceholder {
            enabled: listView.count === 0 && !showBusy
            text: isAudiobook ? qsTr("No chapters found") : qsTr("No episodes found")
        }

        onAtYEndChanged: {
            if(listView.atYEnd && itemsModel.count > 0)
                append()
        }
    }

    BusyIndicator {
        running: showBusy && listView.count === 0
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
    }

    property int _total: 0
    property bool _loading: false

    function append() {
        if(itemsModel.count > 0 && itemsModel.count >= _total)
            return
        if(_loading || !show)
            return
        _loading = true
        showBusy = true
        var options = {offset: itemsModel.count, limit: 50, market: "from_token"}
        var cb = function(error, data) {
            if(data && data.items) {
                _total = data.total
                for(var i=0;i<data.items.length;i++) {
                    var it = data.items[i]
                    if(!it)
                        continue
                    itemsModel.append({type: isAudiobook ? Util.SpotifyItemType.Chapter
                                                         : Util.SpotifyItemType.Episode,
                                       name: it.name,
                                       item: it,
                                       following: false,
                                       saved: false,
                                       played_at: ""})
                }
            } else if(error) {
                app.showErrorMessage(error, isAudiobook ? qsTr("Cannot load the chapters")
                                                        : qsTr("Cannot load the episodes"))
            }
            _loading = false
            showBusy = false
        }
        if(isAudiobook)
            Spotify.getAudiobookChapters(show.id, options, cb)
        else
            Spotify.getShowEpisodes(show.id, options, cb)
    }

    // Play the show/audiobook, from the given episode/chapter if any
    function playItem(episode) {
        var options = {
            'device_id': app.controller.getDeviceId(),
            'context_uri': show.uri
        }
        if(episode)
            options.offset = {'uri': episode.uri}
        Spotify.play(options, function(error, data) {
            if(!error)
                app.controller.refreshPlaybackState()
            else if(episode) {
                // some contexts refuse an offset: play the episode alone
                app.controller.playTrack(episode)
            } else
                app.showErrorMessage(error, qsTr("Play Failed"))
        })
    }

    function toggleSaved() {
        var cb = function(error, data) {
            if(!error)
                isSaved = !isSaved
            else
                app.showErrorMessage(error, qsTr("Failed"))
        }
        if(isSaved)
            Spotify.removeFromLibrary([show.uri], cb)
        else
            Spotify.saveToLibrary([show.uri], cb)
    }

    function refresh() {
        itemsModel.clear()
        _total = 0
        // the simplified object may lack the description: load the full one
        var full = function(error, data) {
            if(data) {
                var s = show
                s.description = data.description
                if(data.authors) s.authors = data.authors
                if(data.total_chapters) s.total_chapters = data.total_chapters
                if(data.total_episodes) s.total_episodes = data.total_episodes
                show = s
            }
        }
        if(isAudiobook)
            Spotify.getAudiobook(show.id, {market: "from_token"}, full)
        else
            Spotify.getShow(show.id, {market: "from_token"}, full)
        Spotify.libraryContains([show.uri], function(error, data) {
            if(data && data.length > 0)
                isSaved = data[0]
        })
        append()
    }

    Component.onCompleted: {
        if(show)
            refresh()
    }

    propagateComposedEvents: true
    onStatusChanged: {
        if(status === PageStatus.Activating)
            app.dockedPanel.registerListView(listView)
        else if(status === PageStatus.Deactivating)
            app.dockedPanel.unregisterListView(listView)
    }
}
