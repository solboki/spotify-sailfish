/**
 * Copyright (C) 2018 Willem-Jan de Hoog
 *
 * License: MIT
 */


import QtQuick 2.2
import Sailfish.Silica 1.0
import org.nemomobile.configuration 1.0

import "../components"
import "../Spotify.js" as Spotify
import "../Util.js" as Util
import "../GenreCache.js" as GenreCache
import "../LibraryCache.js" as LibraryCache

Page {
    id: myStuffPage
    objectName: "MyStuffPage"

    property int searchInType: 0
    property bool showBusy: false

    property int currentIndex: -1

    allowedOrientations: Orientation.All

    SortedListModel {
        id: searchModel
        sortKey: {
            if(_itemClass === 2)
                return ""
            if(_itemClass !== 0)
                return "name"
            switch(albumSort.value) {
            case 1: return "artistSort,name"
            case 2: return "genreSort,artistSort,name"
            case 3: return "-added_at,name"
            default: return "name"
            }
        }
    }

    // 0: title, 1: artist, 2: genre, 3: date added
    ConfigurationValue {
        id: albumSort
        key: "/hutspot/album_sort"
        defaultValue: 0
    }

    property string busyText: ""

    SilicaListView {
        id: listView
        model: searchModel

        width: parent.width
        anchors.top: parent.top
        height: parent.height - app.dockedPanel.visibleSize
        clip: app.dockedPanel.expanded

        NavigationPullDown {
            currentPage: "MyStuffPage"
            MenuItem {
                text: qsTr("Reload")
                onClicked: {
                    // a manual reload always downloads the albums again
                    LibraryCache.invalidate()
                    refresh()
                }
            }
        }

        header: Column {
            id: lvColumn

            width: parent.width - 2*Theme.paddingMedium
            x: Theme.paddingMedium
            anchors.bottomMargin: Theme.paddingLarge
            spacing: Theme.paddingSmall

            PageHeader {
                id: pHeader
                width: parent.width
                title: qsTr("My Library")
            }

            // What to show: replaces the former "tap the title" switch
            ComboBox {
                id: itemClassBox
                width: parent.width
                label: qsTr("Show")
                currentIndex: _itemClass
                menu: ContextMenu {
                    MenuItem { text: qsTr("Saved Albums") }
                    MenuItem { text: qsTr("Playlists") }
                    MenuItem { text: qsTr("Recently Played") }
                    MenuItem { text: qsTr("Saved Tracks") }
                    MenuItem { text: qsTr("Followed Artists") }
                    MenuItem { text: qsTr("Podcasts") }
                    MenuItem { text: qsTr("Audiobooks") }
                }
                onCurrentIndexChanged: {
                    if(currentIndex >= 0 && currentIndex !== _itemClass)
                        setItemClass(currentIndex)
                }
            }

            ComboBox {
                id: albumSortBox
                width: parent.width
                visible: _itemClass === 0
                label: qsTr("Sort by")
                currentIndex: albumSort.value
                menu: ContextMenu {
                    MenuItem { text: qsTr("Title") }
                    MenuItem { text: qsTr("Artist") }
                    MenuItem { text: qsTr("Genre") }
                    MenuItem { text: qsTr("Date added") }
                }
                onCurrentIndexChanged: {
                    if(currentIndex >= 0 && currentIndex !== albumSort.value) {
                        albumSort.value = currentIndex
                        refresh()
                    }
                }
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

        SectionDelegate {
            id: sectionDelegate
        }

        // no name section for Recently Played
        section.property: _itemClass != 2 ? "section" : ""
        section.delegate: sectionDelegate

        delegate: ListItem {
            id: listItem
            width: parent.width
            contentHeight: Theme.itemSizeLarge

            SearchResultListItem {
                id: searchResultListItem
                dataModel: model
            }

            menu: SearchResultContextMenu {
                MenuItem {
                    enabled: type === 1 || type === 2
                    visible: enabled
                    text: qsTr("Unfollow")
                    onClicked: {
                        var idx = index
                        var model = searchModel
                        if(type === 1)
                            app.unfollowArtist(item, function(error,data) {
                               if(!error)
                                   model.remove(idx, 1)
                            })
                        else
                            app.unfollowPlaylist(item, function(error,data) {
                               if(!error)
                                   model.remove(idx, 1)
                            })
                    }
                }
            }

            onClicked: {
                switch(type) {
                case 0:
                    app.pushPage(Util.HutspotPage.Album, {album: item})
                    break;
                case 1:
                    app.pushPage(Util.HutspotPage.Artist, {currentArtist: item})
                    break;
                case 2:
                    app.pushPage(Util.HutspotPage.Playlist, {playlist: item})
                    break;
                case Util.SpotifyItemType.Show:
                case Util.SpotifyItemType.Audiobook:
                    app.pushPage(Util.HutspotPage.Show, {show: item})
                    break;
                case 3:
                    // tap on a track plays it, tap on its cover opens the album
                    app.controller.playTrack(item)
                    break;
                }
            }
        }

        VerticalScrollDecorator {}

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("Nothing found")
        }

        onAtYEndChanged: {
            if(listView.atYEnd && searchModel.count > 0)
                append()
        }
    }

    // when the page is on the stack but not on top a refresh can wait
    property bool _needsRefresh: false

    Connections {
        target: app

        onPlaylistEvent: {
            if(_itemClass !== 1)
                return
            switch(event.type) {
            case Util.PlaylistEventType.AddedTrack:
            case Util.PlaylistEventType.ChangedDetails:
            case Util.PlaylistEventType.RemovedTrack:
            case Util.PlaylistEventType.ReplacedAllTracks:
                // check if the playlist is in the current list if so trigger a refresh
                var i = Util.doesListModelContain(searchModel, Spotify.ItemType.Playlist, event.playlistId)
                if(i >= 0) {
                    if(myStuffPage.status === PageStatus.Active)
                        refresh()
                    else
                        _needsRefresh = true
                }
                break
             case Util.PlaylistEventType.CreatedPlaylist:
                 if(myStuffPage.status === PageStatus.Active)
                     refresh()
                 else
                     _needsRefresh = true
                 break
            }
        }
    }

    property var savedAlbums
    property var userPlaylists
    property var recentlyPlayedTracks
    property var savedTracks
    property var followedArtists
    // 0: Saved Albums, 1: User Playlists, 2: Recently Played Tracks, 3: Saved Tracks, 4: Followed Artists
    property int _itemClass: app.current_item_classes.myStuff

    function nextItemClass() {
        var i = _itemClass
        i++
        if(i > 6)
            i = 0
        _itemClass = i
        app.current_item_classes.myStuff = i
        refreshDirection = 0
        refresh()
    }

    function setItemClass(i) {
        _itemClass = i
        app.current_item_classes.myStuff = i
        refreshDirection = 0
        refresh()
    }

    function addData(obj) {
        obj.nameFirstChar = Util.getFirstCharForSection(obj.name)
        if(!obj.hasOwnProperty('section'))
            obj.section = obj.nameFirstChar
        if(!obj.hasOwnProperty('played_at'))
            obj.played_at = ""
        if(!obj.hasOwnProperty('following'))
            obj.following = false
        searchModel.add(obj)
    }

    // savedItem: {added_at, album}
    function addAlbum(savedItem) {
        var album = savedItem.album
        var artist = (album.artists && album.artists.length > 0) ? album.artists[0] : null
        var artistName = artist ? artist.name : ""
        var genre = artist ? GenreCache.mainGenre(artist.id) : ""
        var obj = {type: 0, stype: 0,
                   name: album.name,
                   item: album,
                   following: false, saved: true,
                   added_at: savedItem.added_at ? savedItem.added_at : "",
                   artistSort: artistName.toLowerCase(),
                   genreSort: genre.length > 0 ? genre.toLowerCase() : "\uffff"}
        switch(albumSort.value) {
        case 1:
            obj.section = artistName
            break
        case 2:
            obj.section = genre.length > 0 ? genre : qsTr("Unknown genre")
            break
        case 3:
            obj.section = obj.added_at
                    ? Qt.formatDate(new Date(obj.added_at), "MMMM yyyy")
                    : ""
            break
        default:
            obj.section = Util.getFirstCharForSection(album.name)
        }
        addData(obj)
    }

    // Sorting by artist, genre or date needs the whole list of albums
    property bool _loadingAll: false

    function loadAllAlbums() {
        if(_loadingAll)
            return
        var cached = LibraryCache.savedAlbums()
        if(cached) {
            _afterAlbumsLoaded(cached)
            return
        }
        _loadingAll = true
        showBusy = true
        busyText = qsTr("Loading albums")
        var all = []
        var page = function(offset) {
            Spotify.getMySavedAlbums({offset: offset, limit: 50}, function(error, data) {
                if(data && data.items) {
                    for(var i=0;i<data.items.length;i++)
                        all.push(data.items[i])
                    cursorHelper.total = data.total
                    busyText = qsTr("Loading albums") + " " + all.length + "/" + data.total
                    if(data.items.length > 0 && all.length < data.total) {
                        page(all.length)
                        return
                    }
                }
                _loadingAll = false
                _afterAlbumsLoaded(LibraryCache.setSavedAlbums(all))
            })
        }
        page(0)
    }

    // Genres are only needed when sorting by genre (and are cached too)
    function _afterAlbumsLoaded(all) {
        if(albumSort.value === 2) {
            var ids = []
            for(var j=0;j<all.length;j++)
                if(all[j].album.artists && all[j].album.artists.length > 0)
                    ids.push(all[j].album.artists[0].id)
            _loadingAll = true
            showBusy = true
            GenreCache.fetchMissing(ids, function(done, total) {
                busyText = qsTr("Loading genres") + " " + done + "/" + total
            }, function() {
                fillAllAlbums(all)
            })
        } else
            fillAllAlbums(all)
    }

    function fillAllAlbums(all) {
        searchModel.clear()
        for(var i=0;i<all.length;i++)
            addAlbum(all[i])
        cursorHelper.total = all.length
        _loadingAll = false
        showBusy = false
        busyText = ""
    }

    function loadData() {
        var i
        if(savedAlbums)
            for(i=0;i<savedAlbums.items.length;i++)
                addAlbum(savedAlbums.items[i])
        if(userPlaylists)
            for(i=0;i<userPlaylists.items.length;i++) {
                addData({type: 2, stype: 2,
                         name: userPlaylists.items[i].name,
                         item: userPlaylists.items[i],
                         following: true, saved: false})
            }
        if(recentlyPlayedTracks)
            // context, played_at, track
            for(i=0;i<recentlyPlayedTracks.items.length;i++) {
                addData({type: 3, stype: 3,
                         name: recentlyPlayedTracks.items[i].track.name,
                         item: recentlyPlayedTracks.items[i].track,
                         following: false, saved: false,
                         played_at: recentlyPlayedTracks.items[i].played_at})
            }
        if(savedTracks)
            for(i=0;i<savedTracks.items.length;i++) {
                addData({type: 3, stype: 4,
                         name: savedTracks.items[i].track.name,
                         item: savedTracks.items[i].track,
                         following: true, saved: true})
            }
        if(followedArtists)
            for(i=0;i<followedArtists.artists.items.length;i++) {
                addData({type: 1, stype: 1,
                         name: followedArtists.artists.items[i].name,
                         item: followedArtists.artists.items[i],
                         following: true, saved: false})
            }
    }

    property int nextPrevious: 0


    function refresh() {
        searchModel.clear()
        savedAlbums = undefined
        userPlaylists = undefined
        savedTracks = undefined
        recentlyPlayedTracks = undefined
        followedArtists = undefined
        append()
    }

    property bool _loading: false

    function append() {
        // if already at the end -> bail out
        if(searchModel.count > 0 && searchModel.count >= cursorHelper.total)
            return

        // guard
        if(_loading)
            return
        _loading = true

        var i, options;
        if(_itemClass === 0) {
            _loading = false
            if(searchModel.count === 0)
                loadAllAlbums()
            return
        }
        switch(_itemClass) {
        case 0:
            Spotify.getMySavedAlbums({offset: searchModel.count, limit: cursorHelper.limit}, function(error, data) {
                if(data) {
                    console.log("number of SavedAlbums: " + data.items.length)
                    savedAlbums = data
                    cursorHelper.offset = data.offset
                    cursorHelper.total = data.total
                } else
                    console.log("No Data for getMySavedAlbums")
                loadData()
                _loading = false
            })
            break
        case 1:
            Spotify.getUserPlaylists({offset: searchModel.count, limit: cursorHelper.limit},function(error, data) {
                if(data) {
                    console.log("number of playlists: " + data.items.length)
                    userPlaylists = data
                    cursorHelper.offset = data.offset
                    cursorHelper.total = data.total
                } else
                    console.log("No Data for getUserPlaylists")
                loadData()
                _loading = false
            })
            break
        case 2:
            // unfortunately:
            //   Any tracks listened to while the user had “Private Session” enabled in
            //   their client will not be returned in the list of recently played tracks.
            // and it seems Librespot just does that when using credentials
            options = {limit: cursorHelper.limit}
            // 'RecentlyPlayedTracks' has 'before' and 'after' fields
            if(refreshDirection < 0) // previous set is looking forward in time
                options.after = cursorHelper.after
            else if(refreshDirection > 0) // next set is looking back in time
                options.before = cursorHelper.before
            Spotify.getMyRecentlyPlayedTracks(options, function(error, data) {
                if(data) {
                    console.log("number of RecentlyPlayedTracks: " + data.items.length)
                    recentlyPlayedTracks = data
                    cursorHelper.update(Util.loadCursor(data, Util.CursorType.RecentlyPlayed))
                } else
                    console.log("No Data for getMyRecentlyPlayedTracks")
                loadData()
                _loading = false
            })
            break
        case 3:
            Spotify.getMySavedTracks({offset: searchModel.count, limit: cursorHelper.limit}, function(error, data) {
                if(data) {
                    console.log("number of SavedTracks: " + data.items.length)
                    savedTracks = data
                    cursorHelper.offset = data.offset
                    cursorHelper.total = data.total
                } else
                    console.log("No Data for getMySavedTracks")
                loadData()
                _loading = false
            })
            break
        case 4:
            // 'Followed Artists' only has an 'after' field
            options = {limit: cursorHelper.limit}
            if(refreshDirection > 0)
                options.after = cursorHelper.after
            Spotify.getFollowedArtists(options, function(error, data) {
                if(data) {
                    console.log("number of FollowedArtists: " + data.artists.items.length)
                    followedArtists = data
                    cursorHelper.update(Util.loadCursor(data.artists, Util.CursorType.FollowedArtists))
                } else
                    console.log("No Data for getFollowedArtists")
                loadData()
                _loading = false
            })
            break
        case 5: // podcasts
        case 6: // audiobooks
            var isShows = _itemClass === 5
            var cb = function(error, data) {
                if(data && data.items) {
                    cursorHelper.offset = data.offset
                    cursorHelper.total = data.total
                    for(var k=0;k<data.items.length;k++) {
                        var it = data.items[k]
                        if(!it)
                            continue
                        var obj = isShows ? it.show : (it.audiobook ? it.audiobook : it)
                        if(!obj)
                            continue
                        addData({type: isShows ? Util.SpotifyItemType.Show : Util.SpotifyItemType.Audiobook,
                                 stype: isShows ? Util.SpotifyItemType.Show : Util.SpotifyItemType.Audiobook,
                                 name: obj.name,
                                 item: obj,
                                 following: true, saved: true})
                    }
                } else if(error)
                    app.showErrorMessage(error, qsTr("Cannot load the library"))
                _loading = false
            }
            options = {offset: searchModel.count, limit: cursorHelper.limit, market: "from_token"}
            if(isShows)
                Spotify.getMySavedShows(options, cb)
            else
                Spotify.getMySavedAudiobooks(options, cb)
            break
        }
    }

    property int refreshDirection: 0
    property alias cursorHelper: cursorHelper

    CursorHelper {
        id: cursorHelper

        useHas: true
    }

    Connections {
        target: app
        onHasValidTokenChanged: refresh()
        onFavoriteEvent: {
            // an album was saved or removed: the cached list is outdated
            if(event.type === Util.SpotifyItemType.Album) {
                LibraryCache.invalidate()
                if(_itemClass === 0)
                    refresh()
            }
        }
    }

    Component.onCompleted: {
        if(app.hasValidToken)
            refresh()
    }

    // The shared DockedPanel needs mouse events
    // and some ListView events
    propagateComposedEvents: true
    onStatusChanged: {
        if(status === PageStatus.Activating) {
            app.dockedPanel.registerListView(listView)
            if(_needsRefresh) {
                _needsRefresh = false
                refresh()
            }
        } else if(status === PageStatus.Deactivating)
            app.dockedPanel.unregisterListView(listView)
    }
}
