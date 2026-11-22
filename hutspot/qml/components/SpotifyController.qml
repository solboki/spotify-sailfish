<<<<<<< HEAD
/**
 * Hutspot. 
 * Copyright (C) 2018 Maciej Janiszewski
 *
 * License: MIT
 */

import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Spotify.js" as Spotify
import "../Util.js" as Util


Item {
    PlaybackState {
        id: playbackState
    }

    function getCoverArt(defaultValue, ignoreContext) {
        if (ignoreContext) {
            if (playbackState.coverArtUrl)
                return playbackState.coverArtUrl
            return defaultValue
        }

        if (playbackState.contextDetails)
            if (playbackState.contextDetails.images)
                return playbackState.contextDetails.images[0].url
        return defaultValue;
    }

    property alias playbackState: playbackState
    property alias devices: devicesModel

    ListModel {
        id: devicesModel
    }

    Timer {
        id: handleRendererInfo
        interval: 1000
        onRunningChanged: if (running) refreshCount = 0
        running: playbackState.is_playing || Qt.application.active || cover.status === Cover.Active
        property int refreshCount: 0
        repeat: true
        onTriggered: {
            // pretend progress (ms), refresh() will set the actual value
            if (playbackState.is_playing) {
                if (playbackState.progress_ms < playbackState.item.duration_ms) {
                    playbackState.progress_ms += 1000
                } else
                    playbackState.progress_ms = playbackState.item.duration_ms
            }

            // close to switching tracks so refresh every time
            // also reload playbackState if we haven't done it in a long time
            if(playbackState.is_playing
               && (playbackState.item.duration_ms - playbackState.progress_ms) < 3000) {
                refreshPlaybackState()
                refreshCount = 0
            } else if (++refreshCount >= 5) {
                refreshPlaybackState()
                refreshCount = 0
            }
        }
    }

    Connections {
        target: app
        onHasValidTokenChanged: {
            if(app.hasValidToken) {
                refreshPlaybackState()
                reloadDevices()
            }
        }
    }

    Timer {
        id: timer
        function setTimeout(cb, delayTime) {
            interval = delayTime;
            repeat = false;
            triggered.connect(cb);
            triggered.connect(function() {
                triggered.disconnect(cb); // This is important
            });
            start();
        }
    }

    function setVolume(volume) {
        var value = Math.round(volume);
        Spotify.setVolume(value, function(error, data) {
            if (!error) {
                playbackState.device.volume_percent = value;
            }
        })
    }

    ListModel {
        id: tmpDevicesModel
    }

    // The device chosen in Hutspot (JollaPhone, i.e. Soloist on this phone).
    // Spotify lists a Connect device only while it is active or while an app
    // on the same local network has discovered it by mDNS. On mobile data
    // nobody can discover it, so Spotify leaves it out of the list although
    // it still accepts commands sent to its id: add it back ourselves.
    function _withSavedDevice(data) {
        var id = app.deviceId.value
        var name = app.deviceName.value
        if (!data || !data.devices || !id || !name)
            return data
        for (var i = 0; i < data.devices.length; i++)
            if (data.devices[i].id === id || data.devices[i].name === name)
                return data
        data.devices.push({
            "id": id,
            "is_active": false,
            "is_private_session": false,
            "is_restricted": false,
            "name": name,
            "supports_volume": true,
            "type": "Smartphone",
            "volume_percent": 100
        })
        return data
    }

    function checkForNewDevices() {
        Spotify.getMyDevices(function(error, data) {
            data = _withSavedDevice(data)
            if (data) {
                try {
                    var i, j, added, removed, changed, found, device

                    // a new one has been added?
                    added = false
                    for(i=0; i < data.devices.length; i++) {
                        found = false
                        for(j=0; j < devicesModel.count; j++) {
                            device = devicesModel.get(j)
                            if(data.devices[i].id === device.id) {
                                found = true
                                break
                            }
                        }
                        if(!found) {
                            added = true
                            break
                        }
                    }
                    // an old one has been removed?
                    removed = false
                    for(i=0; i < devicesModel.count; i++) {
                        found = false
                        device = devicesModel.get(i)
                        for(j=0; j < data.devices.length; j++) {
                            if(data.devices[j].id === device.id) {
                                found = true
                                break
                            }
                        }
                        if(!found) {
                            removed = true
                            break
                        }
                    }
                    // changed
                    changed = false
                    for(i=0; i < data.devices.length; i++) {
                        for(j=0; j < devicesModel.count; j++) {
                            device = devicesModel.get(j)
                            if(data.devices[i].id === device.id) {
                                if(Util.hasDeviceChanged(data.devices[i], device))
                                    changed = true
                                break
                            }
                        }
                        if(changed)
                            break
                    }
                    if(added || removed || changed) {
                        devicesModel.clear();
                        for(i=0; i < data.devices.length; i++) {
                            devicesModel.append(data.devices[i])
                            //if (data.devices[i].is_active)
                            //    playbackState.device = data.devices[i]
                        }
                        //console.log("controller.checkForNewDevices: list differs")
                        devicesReloaded()
                    }
                } catch (err) {
                    console.log("controller.checkForNewDevices: error: " + err)
                }
            }
        })
    }

    signal devicesReloaded()

    function reloadDevices() {
        Spotify.getMyDevices(function(error, data) {
            data = _withSavedDevice(data)
            if (data) {
                try {
                    console.log("controller.reloadDevices: #devices: " + data.devices.length)
                    devicesModel.clear();
                    for (var i=0; i < data.devices.length; i++) {
                        devicesModel.append(data.devices[i]);
                        if (data.devices[i].is_active)
                            playbackState.device = data.devices[i]
                    }
                    devicesReloaded()
                } catch (err) {
                    console.log("controller.reloadDevices: error: " + err)
                }
            } else {
                console.log("controller.reloadDevices: No Data for getMyDevices")
            }
        })
    }

    function delayedRefreshPlaybackState() {
        // for some reason we need to wait
        // thx spotify
        handleRendererInfo.refreshCount = 0
        timer.setTimeout(function () {
            refreshPlaybackState();
        }, 300)
    }

    function next(callback) {
        // TODO: use playback queue to find out what happens next!
        // exciting!
        Spotify.skipToNext({}, function(error, data) {
            if (error && (error.status === 404 || noSession)) {
                resumeOnDevice(callback)
                return
            }
            if (callback)
                callback(error, data)
            refreshPlaybackState()
        })
    }

    function previous(callback) {
        Spotify.skipToPrevious({}, function(error, data) {
            if (error && (error.status === 404 || noSession)) {
                resumeOnDevice(callback)
                return
            }
            if (callback)
                callback(error, data)
            refreshPlaybackState()
        })
    }

    function play(callback) {
        if (noSession) {
            resumeOnDevice(callback)
            return
        }
        Spotify.play({'device_id': getDeviceId()}, function(error, data) {
            if (error && error.status === 404) {
                // the session vanished (Soloist restarted after a network change)
                resumeOnDevice(callback)
                return
            }
            if(!error) {
                playbackState.is_playing = true;
                if(_waitForPlaybackState)
                    _ignorePlaybackState = true
            }
            if (callback)
                callback(error, data)
            else if(error)
                app.showErrorMessage(error, data)
        })
    }

    function pause(callback) {
        Spotify.pause({'device_id': getDeviceId()}, function(error, data) {
            if (error && error.status === 404) {
                // nothing is playing any more: show the real state
                playbackState.is_playing = false
                refreshPlaybackState()
                if (callback)
                    callback(null, data)
                return
            }
            if(!error) {
                playbackState.is_playing = false;
                if(_waitForPlaybackState)
                    _ignorePlaybackState = true
            }
            if (callback)
                callback(error, data)
            else if(error)
                app.showErrorMessage(error, data)
        })
    }

    function playPause(callback) {
        if (playbackState.is_playing)
            pause(callback);
        else
            play(callback);
    }

    function setRepeat(value, callback) {
        Spotify.setRepeat(value, {}, function(error, data) {
            if (!error) {
                playbackState.repeat_state = value;
                delayedRefreshPlaybackState();
            }

            if (callback) callback(error, data)
        })
    }

    function setShuffle(value, callback) {
        Spotify.setShuffle(value, {}, function(error, data) {
            if (!error) {
                playbackState.shuffle_state = value;
                delayedRefreshPlaybackState();
            }

            if (callback) callback(error, data)
        })
    }

    // this allows to check if a response is underway (with possibly outdated info)
    property bool _waitForPlaybackState: false
    property bool _ignorePlaybackState: false

    function refreshPlaybackState() {
        _waitForPlaybackState = true
        var oldContextId = playbackState.context ? playbackState.context.uri : undefined;

        Spotify.getMyCurrentPlaybackState({}, function (error, state) {
            _waitForPlaybackState = false
            if(_ignorePlaybackState) {
                _ignorePlaybackState = false
                return
            }

            if (!error && !state) {
                // HTTP 204: Spotify has no playback session any more,
                // typically after Soloist was restarted. Stop pretending
                // that the old track is still playing.
                if (!noSession) {
                    console.log("controller.refreshPlaybackState: no playback session")
                    noSession = true
                    playbackState.is_playing = false
                    reloadDevices()
                }
                return
            }

            if (state) {
                noSession = false
                playbackState.importState(state)
                if (state.context && state.context.uri !== oldContextId) {
                    var cid = Util.getIdFromURI(playbackState.context.uri)
                    switch (state.context.type) {
                        case 'album':
                            Spotify.getAlbum(cid, {}, function(error, data) {
                                playbackState.contextDetails = data
                            })
                            break
                        case 'artist':
                            Spotify.getArtist(cid, {}, function(error, data) {
                                playbackState.contextDetails = data
                            })
                            break
                        case 'playlist':
                            Spotify.getPlaylist(cid, {}, function(error, data) {
                                playbackState.contextDetails = data
                            })
                            break
                        default:
                            playbackState.contextDetails = null
                    }
                } else {
                    // ToDo why is this?
                    // Disabled since we lose ifo on what is being played
                    //playbackState.contextDetails = undefined
                }
            }
        })
        //reloadDevices() Why is this here? The info is not used.
    }

    function playTrack(track) {
        Spotify.play({
            'device_id': getDeviceId(),
            'uris': [track.uri]
        }, function(error, data) {
            if(!error) {
                playbackState.item = track
                refreshPlaybackState();
            } else
                app.showErrorMessage(error, qsTr("Play Failed"))
        })
    }

    function playContext(context) {
        var options = {
            'device_id': getDeviceId(),
            'context_uri': context.uri
        }
        Spotify.play(options, function(error, data) {
            if (!error) {
              refreshPlaybackState();
            } else
                app.showErrorMessage(error, qsTr("Play Failed"))
        })
    }

    function playTrackInContext(track, context, position) {
        // does not work for some tracks.
        if (playbackState.device) {
            Spotify.play({
                "device_id": getDeviceId(),
                "context_uri": context.uri,
                //"offset": {"position": position}
                "offset": {"uri": track.linked_from
                                  ? track.linked_from.uri : track.uri}
            }, function (error, data) {
                if (!error) {
                    playbackState.item = track
                    refreshPlaybackState();
                } else {
                    app.showErrorMessage(error, qsTr("Play failed"))
                }
            })
        } else {
            // TODO: handle that
            app.showErrorMessage(error, qsTr("No device selected"))
        }
    }

    // true when Spotify reports no playback session at all (HTTP 204)
    property bool noSession: false

    // Restart playback after the session was lost: look the device up again
    // (its id may have changed when Soloist restarted), transfer playback to
    // it and let Spotify resume the last track.
    function resumeOnDevice(callback) {
        Spotify.getMyDevices(function(error, data) {
            var id = getDeviceId()
            var name = app.deviceName.value
            if (data && data.devices) {
                var found = null
                for (var i = 0; i < data.devices.length; i++) {
                    if (name && data.devices[i].name === name) { found = data.devices[i]; break }
                    if (data.devices[i].id === id) found = data.devices[i]
                }
                if (found) {
                    id = found.id
                    app.deviceId.value = id
                }
            }
            Spotify.transferMyPlayback([id], {'play': true}, function(error2, data2) {
                if (!error2) {
                    noSession = false
                    playbackState.is_playing = true
                    reloadDevices()
                    // Spotify needs a moment before reporting the new session
                    timer.setTimeout(function () { refreshPlaybackState() }, 1500)
                } else if (!callback) {
                    app.showErrorMessage(error2, qsTr("Play Failed"))
                }
                if (callback)
                    callback(error2, data2)
            })
        })
    }

    function getDeviceId() {
        return (playbackState.device && playbackState.device.id !== "-1")
               ? playbackState.device.id
               : app.deviceId.value
    }

}
=======
/**
 * Hutspot. 
 * Copyright (C) 2018 Maciej Janiszewski
 *
 * License: MIT
 */

import QtQuick 2.0
import Sailfish.Silica 1.0
import "../Spotify.js" as Spotify
import "../Util.js" as Util


Item {
    PlaybackState {
        id: playbackState
    }

    function getCoverArt(defaultValue, ignoreContext) {
        if (ignoreContext) {
            if (playbackState.coverArtUrl)
                return playbackState.coverArtUrl
            return defaultValue
        }

        if (playbackState.contextDetails)
            if (playbackState.contextDetails.images)
                return playbackState.contextDetails.images[0].url
        return defaultValue;
    }

    property alias playbackState: playbackState
    property alias devices: devicesModel

    ListModel {
        id: devicesModel
    }

    Timer {
        id: handleRendererInfo
        interval: 1000
        onRunningChanged: if (running) refreshCount = 0
        running: playbackState.is_playing || Qt.application.active || cover.status === Cover.Active
        property int refreshCount: 0
        repeat: true
        onTriggered: {
            // a request unanswered for 12 s was probably sent on a network
            // that no longer exists: cancel it
            Spotify.abortStale(12000)

            // pretend progress (ms), refresh() will set the actual value
            if (playbackState.is_playing) {
                if (playbackState.progress_ms < playbackState.item.duration_ms) {
                    playbackState.progress_ms += 1000
                } else
                    playbackState.progress_ms = playbackState.item.duration_ms
            }

            // close to switching tracks so refresh every time
            // also reload playbackState if we haven't done it in a long time
            if(playbackState.is_playing
               && (playbackState.item.duration_ms - playbackState.progress_ms) < 3000) {
                refreshPlaybackState()
                refreshCount = 0
            } else if (++refreshCount >= (_stateUnreachable ? 2 : 5)) {
                // every 5 s normally, every 2 s while Spotify cannot be reached
                refreshPlaybackState()
                refreshCount = 0
            }
        }
    }

    Connections {
        target: app
        onHasValidTokenChanged: {
            if(app.hasValidToken) {
                refreshPlaybackState()
                reloadDevices()
            }
        }
    }

    Timer {
        id: timer
        function setTimeout(cb, delayTime) {
            interval = delayTime;
            repeat = false;
            triggered.connect(cb);
            triggered.connect(function() {
                triggered.disconnect(cb); // This is important
            });
            start();
        }
    }

    function setVolume(volume) {
        var value = Math.round(volume);
        Spotify.setVolume(value, function(error, data) {
            if (!error) {
                playbackState.device.volume_percent = value;
            }
        })
    }

    ListModel {
        id: tmpDevicesModel
    }

    function checkForNewDevices() {
        Spotify.getMyDevices(function(error, data) {
            if (data) {
                try {
                    var i, j, added, removed, changed, found, device

                    // a new one has been added?
                    added = false
                    for(i=0; i < data.devices.length; i++) {
                        found = false
                        for(j=0; j < devicesModel.count; j++) {
                            device = devicesModel.get(j)
                            if(data.devices[i].id === device.id) {
                                found = true
                                break
                            }
                        }
                        if(!found) {
                            added = true
                            break
                        }
                    }
                    // an old one has been removed?
                    removed = false
                    for(i=0; i < devicesModel.count; i++) {
                        found = false
                        device = devicesModel.get(i)
                        for(j=0; j < data.devices.length; j++) {
                            if(data.devices[j].id === device.id) {
                                found = true
                                break
                            }
                        }
                        if(!found) {
                            removed = true
                            break
                        }
                    }
                    // changed
                    changed = false
                    for(i=0; i < data.devices.length; i++) {
                        for(j=0; j < devicesModel.count; j++) {
                            device = devicesModel.get(j)
                            if(data.devices[i].id === device.id) {
                                if(Util.hasDeviceChanged(data.devices[i], device))
                                    changed = true
                                break
                            }
                        }
                        if(changed)
                            break
                    }
                    if(added || removed || changed) {
                        devicesModel.clear();
                        for(i=0; i < data.devices.length; i++) {
                            devicesModel.append(data.devices[i])
                            //if (data.devices[i].is_active)
                            //    playbackState.device = data.devices[i]
                        }
                        //console.log("controller.checkForNewDevices: list differs")
                        devicesReloaded()
                    }
                } catch (err) {
                    console.log("controller.checkForNewDevices: error: " + err)
                }
            }
        })
    }

    signal devicesReloaded()

    function reloadDevices() {
        Spotify.getMyDevices(function(error, data) {
            if (data) {
                try {
                    console.log("controller.reloadDevices: #devices: " + data.devices.length)
                    devicesModel.clear();
                    for (var i=0; i < data.devices.length; i++) {
                        devicesModel.append(data.devices[i]);
                        if (data.devices[i].is_active)
                            playbackState.device = data.devices[i]
                    }
                    devicesReloaded()
                } catch (err) {
                    console.log("controller.reloadDevices: error: " + err)
                }
            } else {
                console.log("controller.reloadDevices: No Data for getMyDevices")
            }
        })
    }

    function delayedRefreshPlaybackState() {
        // for some reason we need to wait
        // thx spotify
        handleRendererInfo.refreshCount = 0
        timer.setTimeout(function () {
            refreshPlaybackState();
        }, 800)
    }

    function next(callback) {
        // TODO: use playback queue to find out what happens next!
        // exciting!
        Spotify.skipToNext({}, function(error, data) {
            if (callback)
                callback(error, data)
            refreshPlaybackState()
        })
    }

    function previous(callback) {
        Spotify.skipToPrevious({}, function(error, data) {
            if (callback)
                callback(error, data)
            refreshPlaybackState()
        })
    }

    function play(callback) {
        _playOrPause(true, callback)
    }

    function pause(callback) {
        _playOrPause(false, callback)
    }

    function playPause(callback) {
        _playOrPause(!playbackState.is_playing, callback)
    }

    // Spotify answers 403 ("restriction violated") when asked to pause what is
    // already paused, or to play what is already playing. That happens when
    // the state shown here is out of date, for instance after a network
    // switch. In that case the wish is already fulfilled: refresh the state
    // and only report an error if it really does not match.
    function _playOrPause(wantPlaying, callback) {
        var options = {'device_id': getDeviceId()}
        var request = wantPlaying ? Spotify.play : Spotify.pause
        _commandGeneration++
        request(options, function(error, data) {
            if (!error) {
                playbackState.is_playing = wantPlaying
                _commandGeneration++
                delayedRefreshPlaybackState()
                if (callback)
                    callback(error, data)
                return
            }
            if (error.status === 403) {
                refreshPlaybackState(function(ok) {
                    if (ok && playbackState.is_playing === wantPlaying) {
                        if (callback)
                            callback(null, data)
                    } else if (callback) {
                        callback(error, data)
                    } else {
                        app.showErrorMessage(error, data)
                    }
                })
                return
            }
            if (callback)
                callback(error, data)
            else
                app.showErrorMessage(error, data)
        })
    }

    function setRepeat(value, callback) {
        Spotify.setRepeat(value, {}, function(error, data) {
            if (!error) {
                playbackState.repeat_state = value;
                delayedRefreshPlaybackState();
            }

            if (callback) callback(error, data)
        })
    }

    function setShuffle(value, callback) {
        Spotify.setShuffle(value, {}, function(error, data) {
            if (!error) {
                playbackState.shuffle_state = value;
                delayedRefreshPlaybackState();
            }

            if (callback) callback(error, data)
        })
    }

    // Increased by every play/pause command. A state answer requested before
    // a command describes the situation before it, so it is ignored.
    property int _commandGeneration: 0
    // true while the last state request failed for lack of network
    property bool _stateUnreachable: false

    function refreshPlaybackState(done) {
        var generation = _commandGeneration
        var oldContextId = playbackState.context ? playbackState.context.uri : undefined;

        Spotify.getMyCurrentPlaybackState({}, function (error, state) {
            if (error) {
                if (!error.status)
                    _stateUnreachable = true
                if (done)
                    done(false)
                return
            }
            if (_stateUnreachable) {
                // Spotify can be reached again: refresh the device list
                // at once instead of waiting for the next check
                _stateUnreachable = false
                reloadDevices()
            }
            if (generation !== _commandGeneration) {
                if (done)
                    done(false)
                return
            }

            if (!state) {
                // HTTP 204: nothing is playing on any device
                playbackState.is_playing = false
            } else {
                playbackState.importState(state)
                if (state.context && state.context.uri !== oldContextId) {
                    var cid = Util.getIdFromURI(playbackState.context.uri)
                    switch (state.context.type) {
                        case 'album':
                            Spotify.getAlbum(cid, {}, function(error, data) {
                                playbackState.contextDetails = data
                            })
                            break
                        case 'artist':
                            Spotify.getArtist(cid, {}, function(error, data) {
                                playbackState.contextDetails = data
                            })
                            break
                        case 'playlist':
                            Spotify.getPlaylist(cid, {}, function(error, data) {
                                playbackState.contextDetails = data
                            })
                            break
                        default:
                            playbackState.contextDetails = null
                    }
                } else {
                    // ToDo why is this?
                    // Disabled since we lose ifo on what is being played
                    //playbackState.contextDetails = undefined
                }
            }
            if (done)
                done(true)
        })
        //reloadDevices() Why is this here? The info is not used.
    }

    function playTrack(track) {
        Spotify.play({
            'device_id': getDeviceId(),
            'uris': [track.uri]
        }, function(error, data) {
            if(!error) {
                playbackState.item = track
                refreshPlaybackState();
            } else
                app.showErrorMessage(error, qsTr("Play Failed"))
        })
    }

    function playContext(context) {
        var options = {
            'device_id': getDeviceId(),
            'context_uri': context.uri
        }
        Spotify.play(options, function(error, data) {
            if (!error) {
              refreshPlaybackState();
            } else
                app.showErrorMessage(error, qsTr("Play Failed"))
        })
    }

    function playTrackInContext(track, context, position) {
        // does not work for some tracks.
        if (playbackState.device) {
            Spotify.play({
                "device_id": getDeviceId(),
                "context_uri": context.uri,
                //"offset": {"position": position}
                "offset": {"uri": track.linked_from
                                  ? track.linked_from.uri : track.uri}
            }, function (error, data) {
                if (!error) {
                    playbackState.item = track
                    refreshPlaybackState();
                } else {
                    app.showErrorMessage(error, qsTr("Play failed"))
                }
            })
        } else {
            // TODO: handle that
            app.showErrorMessage(error, qsTr("No device selected"))
        }
    }

    function getDeviceId() {
        return (playbackState.device && playbackState.device.id !== "-1")
               ? playbackState.device.id
               : app.deviceId.value
    }

}
>>>>>>> b4bbd24818a130c50c9cbae74a9ab3de51653be2
