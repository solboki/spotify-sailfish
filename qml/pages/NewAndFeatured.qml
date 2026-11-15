/**
 * Copyright (C) 2018 Willem-Jan de Hoog
 *
 * "Featured" page, rebuilt for the Spotify Web API of 2026.
 *
 * Spotify removed the editorial endpoints (new releases, featured playlists,
 * categories, recommendations) for Development Mode apps. This page builds
 * the same kind of content from what is still available:
 *   - new releases of the artists the user follows or listens to most
 *   - new albums on Spotify (search with "tag:new")
 *   - playlists matching the user's favourite genres (search)
 *   - the user's all-time favourite tracks
 *
 * License: MIT
 */

import QtQuick 2.2
import Sailfish.Silica 1.0

import "../components"
import "../Spotify.js" as Spotify
import "../Util.js" as Util

Page {
    id: featuredPage
    objectName: "NewReleasePage"

    property bool showBusy: false
    property string busyText: ""

    allowedOrientations: Orientation.All

    // number of days a release is considered "new"
    readonly property int newReleaseDays: 90
    // max number of artists whose albums are checked (one request each)
    readonly property int maxArtists: 30

    ListModel {
        id: featuredModel
    }

    SilicaListView {
        id: listView
        model: featuredModel

        NavigationPullDown {
            currentPage: "NewReleasePage"
            MenuItem {
                text: qsTr("Reload")
                onClicked: refresh()
            }
        }

        width: parent.width
        anchors.top: parent.top
        height: parent.height - app.dockedPanel.visibleSize
        clip: app.dockedPanel.expanded

        header: Column {
            width: parent.width - 2*Theme.paddingMedium
            x: Theme.paddingMedium
            spacing: Theme.paddingSmall

            PageHeader {
                width: parent.width
                title: qsTr("Featured")
            }

            Label {
                visible: busyText.length > 0
                width: parent.width
                text: busyText
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
            }
        }

        section.property: "section"
        section.delegate: SectionHeader {
            text: section
        }

        delegate: ListItem {
            id: listItem
            width: parent.width
            contentHeight: Theme.itemSizeLarge

            SearchResultListItem {
                dataModel: model
            }

            menu: SearchResultContextMenu {}

            onClicked: {
                switch(type) {
                case Util.SpotifyItemType.Album:
                    app.pushPage(Util.HutspotPage.Album, {album: item})
                    break
                case Util.SpotifyItemType.Artist:
                    app.pushPage(Util.HutspotPage.Artist, {currentArtist: item})
                    break
                case Util.SpotifyItemType.Playlist:
                    app.pushPage(Util.HutspotPage.Playlist, {playlist: item})
                    break
                case Util.SpotifyItemType.Track:
                    app.pushPage(Util.HutspotPage.Album, {album: item.album})
                    break
                }
            }
        }

        VerticalScrollDecorator {}

        ViewPlaceholder {
            enabled: listView.count === 0 && !showBusy
            text: qsTr("Nothing found")
            hintText: qsTr("Pull down to reload")
        }
    }

    BusyIndicator {
        running: showBusy && listView.count === 0
        anchors.centerIn: parent
        size: BusyIndicatorSize.Large
    }

    // The sections, in display order. Each one is filled independently.
    property var _sections: ({})
    readonly property var _order: ["artists", "new", "playlists", "classics"]

    function _sectionTitle(key) {
        switch(key) {
        case "artists": return qsTr("New from your artists")
        case "new": return qsTr("New on Spotify")
        case "playlists": return qsTr("Playlists for you")
        case "classics": return qsTr("Your all-time favourites")
        }
        return ""
    }

    // Rebuild the model from the sections, keeping the display order.
    function _rebuild() {
        featuredModel.clear()
        for(var s=0;s<_order.length;s++) {
            var items = _sections[_order[s]]
            if(!items)
                continue
            for(var i=0;i<items.length;i++) {
                var it = items[i]
                featuredModel.append({type: it.type, stype: it.type,
                                      name: it.item.name,
                                      item: it.item,
                                      following: false,
                                      saved: false,
                                      played_at: "",
                                      section: _sectionTitle(_order[s])})
            }
        }
    }

    function _setSection(key, items) {
        var copy = _sections
        copy[key] = items
        _sections = copy
        _rebuild()
    }

    property int _pending: 0
    function _done() {
        _pending--
        if(_pending <= 0) {
            showBusy = false
            busyText = ""
        }
    }

    function refresh() {
        _sections = ({})
        featuredModel.clear()
        showBusy = true
        // artists + genre playlists, new on Spotify, classics
        _pending = 4
        loadArtistReleasesAndGenres()
        loadNewOnSpotify()
        loadClassics()
    }

    // --- New releases of followed and top artists, and favourite genres ---
    function loadArtistReleasesAndGenres() {
        var artists = []
        var seen = {}
        var genreCount = {}
        var addArtists = function(list) {
            for(var i=0;i<list.length;i++) {
                var a = list[i]
                if(!a)
                    continue
                if(a.genres)
                    for(var g=0;g<a.genres.length;g++)
                        genreCount[a.genres[g]] = (genreCount[a.genres[g]] || 0) + 1
                if(!seen[a.id]) {
                    seen[a.id] = true
                    artists.push(a)
                }
            }
        }
        Spotify.getMyTopArtists({limit: 20, time_range: "medium_term"}, function(error, data) {
            if(data && data.items)
                addArtists(data.items)
            Spotify.getFollowedArtists({limit: 50}, function(error2, data2) {
                if(data2 && data2.artists && data2.artists.items)
                    addArtists(data2.artists.items)
                loadGenrePlaylists(genreCount)
                loadArtistReleases(artists.slice(0, maxArtists))
            })
        })
    }

    function _parseReleaseDate(s) {
        // release_date can be "2026", "2026-11" or "2026-11-07"
        if(s.length === 4)
            s += "-01-01"
        else if(s.length === 7)
            s += "-01"
        return new Date(s)
    }

    function loadArtistReleases(artists) {
        var limitDate = new Date(Date.now() - newReleaseDays * 24 * 3600 * 1000)
        var releases = []
        var seenAlbum = {}
        var next = function(index) {
            if(index >= artists.length) {
                releases.sort(function(a, b) {
                    return b.item.release_date.localeCompare(a.item.release_date)
                })
                _setSection("artists", releases)
                _done()
                return
            }
            busyText = qsTr("Checking your artists") + " " + (index + 1) + "/" + artists.length
            Spotify.getArtistAlbums(artists[index].id,
                                    {include_groups: "album,single", limit: 5},
                                    function(error, data) {
                if(data && data.items) {
                    for(var i=0;i<data.items.length;i++) {
                        var album = data.items[i]
                        if(!album || seenAlbum[album.id] || !album.release_date)
                            continue
                        if(_parseReleaseDate(album.release_date) >= limitDate) {
                            seenAlbum[album.id] = true
                            releases.push({type: Util.SpotifyItemType.Album, item: album})
                        }
                    }
                }
                next(index + 1)
            })
        }
        next(0)
    }

    // --- New albums on Spotify ---
    function loadNewOnSpotify() {
        var items = []
        var add = function(data) {
            if(data && data.albums && data.albums.items)
                for(var i=0;i<data.albums.items.length;i++)
                    if(data.albums.items[i])
                        items.push({type: Util.SpotifyItemType.Album, item: data.albums.items[i]})
        }
        Spotify.search("tag:new", ["album"], {limit: 10, offset: 0}, function(error, data) {
            add(data)
            Spotify.search("tag:new", ["album"], {limit: 10, offset: 10}, function(error2, data2) {
                add(data2)
                _setSection("new", items)
                _done()
            })
        })
    }

    // --- Playlists for the 3 favourite genres ---
    function loadGenrePlaylists(genreCount) {
        var genres = Object.keys(genreCount)
        genres.sort(function(a, b) { return genreCount[b] - genreCount[a] })
        genres = genres.slice(0, 3)
        var items = []
        var seen = {}
        var next = function(index) {
            if(index >= genres.length) {
                _setSection("playlists", items)
                _done()
                return
            }
            Spotify.search(genres[index], ["playlist"], {limit: 5}, function(error, data) {
                if(data && data.playlists && data.playlists.items)
                    for(var i=0;i<data.playlists.items.length;i++) {
                        var pl = data.playlists.items[i]
                        // the list can contain null entries
                        if(pl && !seen[pl.id]) {
                            seen[pl.id] = true
                            items.push({type: Util.SpotifyItemType.Playlist, item: pl})
                        }
                    }
                next(index + 1)
            })
        }
        next(0)
    }

    // --- All-time favourite tracks ---
    function loadClassics() {
        Spotify.getMyTopTracks({limit: 10, time_range: "long_term"}, function(error, data) {
            var items = []
            if(data && data.items)
                for(var i=0;i<data.items.length;i++)
                    items.push({type: Util.SpotifyItemType.Track, item: data.items[i]})
            _setSection("classics", items)
            _done()
        })
    }

    property bool _loadedOnce: false

    Connections {
        target: app
        onHasValidTokenChanged: {
            if(app.hasValidToken && !_loadedOnce) {
                _loadedOnce = true
                refresh()
            }
        }
    }

    Component.onCompleted: {
        if(app.hasValidToken) {
            _loadedOnce = true
            refresh()
        }
    }

    // The shared DockedPanel needs mouse events
    // and some ListView events
    propagateComposedEvents: true
    onStatusChanged: {
        if(status === PageStatus.Activating)
            app.dockedPanel.registerListView(listView)
        else if(status === PageStatus.Deactivating)
            app.dockedPanel.unregisterListView(listView)
    }
}
