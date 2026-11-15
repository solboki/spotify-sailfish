/**
 * Hutspot. 
 * Copyright (C) 2018 Maciej Janiszewski
 *
 * License: MIT
 */

import QtQuick 2.0
import Sailfish.Silica 1.0

import Amber.Mpris 1.0
import "../Util.js" as Util

Item {   
    MprisPlayer {
        id: mprisPlayer
        serviceName: "hutspot"
        playbackStatus: is_playing ? Mpris.Playing : Mpris.Paused

        // shown by the media controls of the lock screen
        identity: "Spotify"

        canControl: true

        canPause: true
        canPlay: true
        canGoNext: true
        canGoPrevious: true

        canSeek: false

        onPauseRequested: app.controller.playPause()
        onPlayRequested: app.controller.play()
        onPlayPauseRequested: app.controller.playPause()
        onNextRequested: app.controller.next()
        onPreviousRequested: app.controller.previous()
    }
    onItemChanged: updateMetadata()

    // Metadata for the media controls (lock screen, notifications):
    // title of the track, then artist, then album, and the cover.
    function updateMetadata() {
        if(!item)
            return
        var artists = item.artists ? item.artists : []
        var albumName = ""
        var images = []
        if(item.album) {                      // track
            albumName = item.album.name
            images = item.album.images ? item.album.images : []
        } else if(item.show) {                // podcast episode
            albumName = item.show.name
            images = item.images ? item.images : (item.show.images ? item.show.images : [])
        } else if(item.audiobook) {           // audiobook chapter
            albumName = item.audiobook.name
            images = item.images ? item.images : (item.audiobook.images ? item.audiobook.images : [])
        } else if(item.images)
            images = item.images
        artistsString = artists.length > 0
                ? Util.createItemsString(artists, "")
                : (albumName.length > 0 ? albumName : qsTr("no artist known"))
        coverArtUrl = images.length > 0 ? images[0].url : ""

        _metaTitle = item.name ? item.name : ""
        _metaAlbum = albumName
        _metaLength = item.duration_ms ? item.duration_ms : 0   // milliseconds
        _publishMetadata()
    }

    property string _metaTitle: ""
    property string _metaAlbum: ""
    property real _metaLength: 0

    // Amber.Mpris (the MPRIS module of Sailfish OS 4 and later) passes the
    // cover to the lock screen, the older org.nemomobile.mpris does not.
    function _publishMetadata() {
        mprisPlayer.metaData.title = _metaTitle
        mprisPlayer.metaData.contributingArtist = artistsString
        mprisPlayer.metaData.albumTitle = _metaAlbum
        mprisPlayer.metaData.duration = _metaLength
        mprisPlayer.metaData.artUrl = coverArtUrl
    }

    property string artistsString: ""
    property string coverArtUrl: ""

    property var device: {
        "id": "-1",
        "is_active": true,
        "is_private_session": false,
        "is_restricted": false,
        "type": "Nothing",
        "name": "No device",
        "volume_percent": 100
    }
    property string repeat_state: "off"
    property bool shuffle_state: false
    property var context: undefined
    property var contextDetails: undefined
    property int timestamp: 0
    property int progress_ms: 0
    property bool is_playing: false
    property var item: {
        "id": -1,
        "duration_ms": 0,
        "artists": [],
        "name": "",
        "album": {"name": "", "id": -1, "images": []}
    }

    function nextRepeatState() {
        if (repeat_state === "off")
            return "context"
        else if (repeat_state === "context")
            return "track";
        return "off";
    }

    function importState(state) {
        device = state.device;
        repeat_state = state.repeat_state;
        shuffle_state = state.shuffle_state;
        context = state.context;
        timestamp = state.timestamp;
        progress_ms = state.progress_ms;
        is_playing = state.is_playing;
        item = state.item;
    }
}
