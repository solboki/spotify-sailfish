/**
 * Hutspot. 
 * Copyright (C) 2018 Maciej Janiszewski
 *
 * License: MIT
 */

import QtQuick 2.0
import Sailfish.Silica 1.0

import org.nemomobile.mpris 1.0
import org.hildon.components 1.0
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
        _metaLength = item.duration_ms ? item.duration_ms * 1000 : 0
        _metaArt = ""
        _publishMetadata()

        // The lock screen needs a local file for the cover: download the
        // medium size image (300 px) with curl into the cache folder.
        var url = images.length > 1 ? images[1].url : coverArtUrl
        if(url.length > 0)
            _fetchArt(url)
    }

    property string _metaTitle: ""
    property string _metaAlbum: ""
    property real _metaLength: 0
    property string _metaArt: ""

    function _publishMetadata() {
        var metadata = {}
        metadata[Mpris.metadataToString(Mpris.Title)] = _metaTitle
        metadata[Mpris.metadataToString(Mpris.Artist)] = artistsString
        if(_metaAlbum.length > 0)
            metadata[Mpris.metadataToString(Mpris.Album)] = _metaAlbum
        if(_metaLength > 0)
            metadata[Mpris.metadataToString(Mpris.Length)] = _metaLength
        if(_metaArt.length > 0)
            metadata[Mpris.metadataToString(Mpris.ArtUrl)] = _metaArt
        mprisPlayer.metadata = metadata
    }

    // two file names used in turn, so the lock screen sees a new file
    property int _artSlot: 0
    property string _artPending: ""

    Process {
        id: artProcess
        property string target: ""
        onFinished: {
            if(exitCode === 0 && target.length > 0) {
                _metaArt = "file://" + target
                _publishMetadata()
            }
            if(_artPending.length > 0) {
                var next = _artPending
                _artPending = ""
                _fetchArt(next)
            }
        }
    }

    function _fetchArt(url) {
        if(artProcess.state !== Processes.NotRunning) {
            _artPending = url
            return
        }
        _artSlot = 1 - _artSlot
        artProcess.target = StandardPaths.cache + "/cover-" + _artSlot + ".jpg"
        artProcess.start("/usr/bin/curl", ["-s", "-f", "-L", "--create-dirs",
                                          "-o", artProcess.target, url])
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
