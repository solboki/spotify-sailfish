/**
 * Copyright (C) 2018 Willem-Jan de Hoog
 * Copyright (C) 2018 Maciej Janiszewski
 *
 * License: MIT
 */

import QtQuick 2.0
import Sailfish.Silica 1.0
import QtQml 2.2

import org.nemomobile.configuration 1.0
import org.nemomobile.dbus 2.0
import Sailfish.Media 1.0
import org.hildon.components 1.0

import "Spotify.js" as Spotify
import "Util.js" as Util
import "LibraryCache.js" as LibraryCache

import "cover"
import "pages"
import "components"

ApplicationWindow {
    id: app

    property bool lightTheme: {
	try {
            if (Theme.colorScheme !== Theme.LightOnDark)
                return true
        } catch (e) {}
        return false
    }

    property alias controller: spotifyController
    SpotifyController {
        id: spotifyController
    }

    property alias spotifyDataCache: spotifyDataCache
    SpotifyDataCache {
        id: spotifyDataCache
    }

    GlassyBackground {
        z: -1
        id: glassyBackground
        property bool showTrackInfo: true
        anchors.fill: parent
        sourceSize.height: parent.height
        source: app.controller.getCoverArt("", showTrackInfo)
        visible: source !== ""
        // TODO: make some cool transitions
        state: "Hidden"
        opacity: 0
        states: [
            State {
                name: "Hidden"
                PropertyChanges { target: glassyBackground; opacity: 0}
            },
            State {
                name: "Visible"
                PropertyChanges { target: glassyBackground; opacity: 1}
            }
        ]

        transitions: [
            Transition {
                from: "Hidden"
                to: "Visible"
                NumberAnimation {
                    target: glassyBackground
                    duration: 500
                    from: 0
                    to: 1
                    properties: "opacity"
                }
            },
            Transition {
                from: "Visible"
                to: "Hidden"
                NumberAnimation {
                    target: glassyBackground
                    duration: 500
                    from: 1
                    to: 0
                    properties: "opacity"
                }
            }
        ]
    }
    property alias glassyBackground: glassyBackground

    property string connectionText: qsTr("connecting")
    property alias searchLimit: searchLimit

    property alias selected_search_targets: selected_search_targets
    property alias auth_using_browser: auth_using_browser
    property alias start_stop_librespot: start_stop_librespot
    property alias confirm_un_follow_save: confirm_un_follow_save
    property alias navigation_menu_type: navigation_menu_type
    property alias playing_as_attached_page: playing_as_attached_page
    property alias history_store: history_store
    property alias genre_seeds: genre_seeds
    property alias recommended_attributes: recommended_attributes
    property alias current_item_classes: current_item_classes
    property alias search_history: search_history
    property alias search_history_max_size: search_history_max_size
    property alias query_for_market: query_for_market
    property alias hutspot_queue_playlist_name: hutspot_queue_playlist_name
    property alias enable_connect_discovery: enable_connect_discovery
    property alias show_devices_page_at_startup: show_devices_page_at_startup
    property alias controlpanel_show_delay: controlpanel_show_delay
    property alias logging_flags: logging_flags
    property alias locale_config: locale_config

    property alias deviceId: deviceId
    property alias deviceName: deviceName

    property alias queue: queue
    property alias playingPage: playingPage
    property alias librespot: librespot
    property string playerName: "Hutspot"

    property var doBeforeStart: doBeforeStart

    allowedOrientations: Orientation.All

    // seeds for recommendations
    property alias seedsModel: seedsModel
    ListModel {
        id: seedsModel
    }

    function useAsSeeds(playlist) {
        getPlaylistTracks(playlist.id, {offset: 0, limit: 5}, function(error, data) {
            if(data) {
                seedsModel.clear()
                try {
                    //console.log("useAsSeeds: number of PlaylistTracks: " + data.items.length)
                    for(var i=0;i<data.items.length;i++) {
                        seedsModel.append({type: Spotify.ItemType.Track,
                                           stype: Spotify.ItemType.Playlist,
                                           name: data.items[i].track.name,
                                           saved: false,
                                           item: data.items[i].track})
                    }
                } catch (err) {
                    console.log("useAsSeeds: "+ err)
                }
            } else {
                console.log("useAsSeeds: No Data for getPlaylistTracks")
            }
        })
    }

    cover: CoverPage {
        id: cover
    }

    Messagebox {
        id: msgBox
    }

    Playing {
        id: playingPage
    }

    /*NavigationMenu {
        id: navigationMenuPage
    }*/

    property int _attachedPage: 0 // 0 for playingPage, 1 for navigationMenuPage

    function showPage(pageName) {
        var page
        switch(pageName) {
        case 'PlayingPage':
            // when not having the Playing page as attached page
            // pop all pages above playing page or add it
            var pPage = pageStack.find(function(page) {
                return page.objectName === "PlayingPage"
            })
            if(pPage !== null)
                pageStack.pop(pPage)
            else
                pageStack.push(playingPage)
            break;
        case 'NewReleasePage':
            pageStack.clear()
            page = pageStack.push(Qt.resolvedUrl("pages/NewAndFeatured.qml"))
            break;
        case 'MyStuffPage':
            pageStack.clear()
            page = pageStack.push(Qt.resolvedUrl("pages/MyStuff.qml"))
            break;
        case 'TopStuffPage':
            pageStack.clear()
            page = pageStack.push(Qt.resolvedUrl("pages/TopStuff.qml"))
            break;
        case 'SearchPage':
            pageStack.clear()
            page = pageStack.push(Qt.resolvedUrl("pages/Search.qml"))
            break;
        case 'GenreMoodPage':
            pageStack.clear()
            page = pageStack.push(Qt.resolvedUrl("pages/GenreMood.qml"))
            break;
        case 'HistoryPage':
            pageStack.clear()
            page = pageStack.push(Qt.resolvedUrl("pages/History.qml"))
            break;
        case 'RecommendedPage':
            pageStack.clear()
            page = pageStack.push(Qt.resolvedUrl("pages/Recommended.qml"))
            break;
        default:
            return
        }
        if(playing_as_attached_page.value)
            pageStack.pushAttached(playingPage)
        firstPage.value = pageName
    }

    function loadFirstPage() {
        var pageUrl = undefined
        switch(firstPage.value) {
        default:
        case "PlayingPage":
            // when not having the Playing page as attached page
            if(!playing_as_attached_page.value)
                pageUrl = Qt.resolvedUrl("pages/Playing.qml")
            else
                pageUrl = Qt.resolvedUrl("pages/MyStuff.qml")
            break;
        case "NewReleasePage": // rebuilt from the endpoints still available
            pageUrl = Qt.resolvedUrl("pages/NewAndFeatured.qml")
            break;
        case "MyStuffPage":
            pageUrl = Qt.resolvedUrl("pages/MyStuff.qml")
            break;
        case "TopStuffPage":
            pageUrl = Qt.resolvedUrl("pages/TopStuff.qml")
            break;
        case "SearchPage":
            pageUrl = Qt.resolvedUrl("pages/Search.qml")
            break;
        case 'GenreMoodPage': // removed by Spotify (Web API, Feb. 2026)
            pageUrl = Qt.resolvedUrl("pages/MyStuff.qml")
            break;
        case 'HistoryPage':
            pageUrl = Qt.resolvedUrl("pages/History.qml")
            break;
        case 'RecommendedPage': // removed by Spotify (Web API, Feb. 2026)
            pageUrl = Qt.resolvedUrl("pages/MyStuff.qml")
            break;
        }
        if(pageUrl !== undefined ) {
            // load first page
            pageStack.replace(Qt.resolvedUrl(pageUrl), {}, PageStackAction.Immediate)
            // attach playing page if needed
            if(playing_as_attached_page.value)
                pageStack.pushAttached(playingPage)
            // show the Devices page if needed
            if(show_devices_page_at_startup.value)
                doSelectedMenuItem(Util.HutspotMenuItem.ShowDevicesPage)
        }
    }

    // when using menu dialog
    function doSelectedMenuItem(selectedIndex) {
        switch(selectedIndex) {
        case Util.HutspotMenuItem.ShowPlayingPage:
            app.showPage('PlayingPage')
            break
        case Util.HutspotMenuItem.ShowNewReleasePage:
            app.showPage('NewReleasePage')
            break
        case Util.HutspotMenuItem.ShowMyStuffPage:
            app.showPage('MyStuffPage')
            break
        case Util.HutspotMenuItem.ShowTopStuffPage:
            app.showPage('TopStuffPage')
            break
        case Util.HutspotMenuItem.ShowGenreMoodPage:
            app.showPage('GenreMoodPage')
            break
        case Util.HutspotMenuItem.ShowHistoryPage:
            app.showPage('HistoryPage')
            break
        case Util.HutspotMenuItem.ShowRecommendedPage:
            app.showPage('RecommendedPage')
            break
        case Util.HutspotMenuItem.ShowSearchPage:
            app.showPage('SearchPage')
            break
        case Util.HutspotMenuItem.ShowDevicesPage:
            pageStack.push(Qt.resolvedUrl("pages/Devices.qml"))
            break
        case Util.HutspotMenuItem.ShowSettingsPage:
            pageStack.push(Qt.resolvedUrl("pages/Settings.qml"))
            break
        case Util.HutspotMenuItem.ShowAboutPage:
            pageStack.push(Qt.resolvedUrl("pages/About.qml"))
            break;
        case Util.HutspotMenuItem.ShowHelp:
            Qt.openUrlExternally("http://sailfish-spotify.github.io/hutspot/")
            break;
        }
    }

    //
    // 0: Album, 1: Artist, 2: Playlist
    function pushPage(type, options, fromPlaying) {
        var pageUrl = undefined
        switch(type) {
        case Util.HutspotPage.Album:
            pageUrl = "pages/Album.qml"
            break
        case Util.HutspotPage.Artist:
            pageUrl = "pages/Artist.qml"
            break
        case Util.HutspotPage.Playlist:
            pageUrl = "pages/Playlist.qml"
            break
        case Util.HutspotPage.GenreMoodPlaylist:
            pageUrl = "pages/GenreMoodPlaylist.qml"
            break
        case Util.HutspotPage.Show:
            pageUrl = "pages/Show.qml"
            break
        }

        // if the pushPage is called from the Playing page and the Playing page
        // is an attached page we need to go to the parent first
        if(fromPlaying) {
            if(playing_as_attached_page.value)
                pageStack.navigateBack(PageStackAction.Immediate)
        }

        if(pageUrl !== undefined ) {
            pageStack.push(Qt.resolvedUrl(pageUrl), options, PageStackAction.Immediate)
            if(playing_as_attached_page.value)
                pageStack.pushAttached(playingPage)
        }
    }

    function setPlayingAsAttachedPage() {
        pageStack.pushAttached(playingPage)
        _attachedPage = 0
    }

    function setMenuAsAttachedPage() {
        //navigationMenuPage.selectedMenuItem = -1
        //navigationMenuPage._currentIndex = -1
        //pageStack.pushAttached(navigationMenuPage)
        pageStack.pushAttached(Qt.resolvedUrl("pages/NavigationMenu.qml"))
        _attachedPage = 1
    }

    // Banners that can repeat (no network, login needed) are shown at most
    // once a minute: a page that sends ten requests while the phone is
    // offline must not produce ten banners.
    property var _lastBanner: ({})
    function _showRarely(key, message) {
        var now = Date.now()
        if(_lastBanner[key] && now - _lastBanner[key] < 60000)
            return
        _lastBanner[key] = now
        msgBox.showMessage(message, 3000)
    }

    function showErrorMessage(error, text) {
        var msg
        if(!text)
            text = qsTr("Spotify error")
        if(error && error.status === 0) {
            // no answer at all: no network, or the network has just changed
            _showRarely("network", qsTr("Cannot reach Spotify: check the connection"))
            return
        }
        if(error && error.status === 401 && needsLogin) {
            _showRarely("login", qsTr("Spotify asks you to log in again (Settings, Login)"))
            return
        }
        if(error) {
            if(error.hasOwnProperty('status') && error.hasOwnProperty('message'))
                msg = text + ":" + error.status + ":" + error.message
            else
                msg = text + ": " + error
        } else
            msg = text
        msgBox.showMessage(msg, 3000)
    }

    function setDevice(id, name, callback) {
        var newId = id
        var newName = name
        Spotify.transferMyPlayback([id],{}, function(error, data) {
            if(!error) {
                controller.refreshPlaybackState()
                deviceId.value = newId
                deviceName.value = newName
                callback(null, data)
            } else
                showErrorMessage(error, qsTr("Failed to transfer to") + " " + deviceName.value)
        })
    }

    // Called once, when the app starts. Nothing here depends on the network
    // being up: the token is used or renewed as soon as that is possible.
    function startSpotify() {
        Spotify.setHooks({
            // a request needs a new token now. While renewals are failing,
            // do not try more than once every 5 s: the request simply waits
            // for the next attempt (and gives up quietly after 12 s).
            refresh: function() {
                if(Date.now() - app._lastRefreshAttempt > 5000)
                    app.refreshToken()
            },
            defer: function(ms, fn) { app.callLater(ms, fn) }
        })

        history = history_store.value

        // start discovery
        if(enable_connect_discovery.value)
            spConnect.startMDNSService()

        if(!spotify.isLinked()) {
            // never logged in (or logged out): open the login page, once
            needsLogin = true
            connectionText = qsTr("Disconnected")
            spotify.doO2Auth(Spotify._scope, auth_using_browser.value)
        } else if(spotify.getExpires() - Date.now() / 1000 > 5 * 60) {
            // the stored token is still good: use it at once
            _useToken()
        } else
            refreshToken()
    }

    onHasValidTokenChanged: {
        if(start_stop_librespot.value) {
            if(librespot.serviceEnabled) {
                if(hasValidToken) {
                    librespotAtStart.notifyHappend(librespotAtStart.validTokenMask)
                }
                // ToDo: stop Librespot if the token becomes invalid?
            }
        }
    }

    Item {
        id: librespotAtStart

        readonly property int validTokenMask: 0x01
        readonly property int deviceListReadyMask: 0x02

        readonly property int triggerMask: 0x03
        property int happendMask: 0

        function notifyHappend(event) {
            happendMask |= event
            if((happendMask & triggerMask) === triggerMask) {
                // only do something when wished for
                if(!start_stop_librespot.value)
                    return
                if(!librespot.serviceRunning) {
                    console.log("Librespot is not running so start it")
                    librespot.start()
                } else {
                    if(!isLibrespotInDevicesList()) {
                        console.log("Librespot is not in the devices list so try to re-register it")
                        if(librespot.hasLibrespotCredentials()) {
                            var ls = isLibrespotInDiscoveredList()
                            if(ls !== null)
                                librespot.addUser(ls)
                            else
                                console.log("Librespot not present in discovered list")
                        } else {
                            console.log("no credentials available so restart and hope for the best...")
                            librespot.start()
                        }
                    } else
                        // it is in the devices list now check if it is the current one
                        handleCurrentDevice()
                }
            }
        }
    }

    // thanks to harbour-storeman.qml
    Connections {
        target: __quickWindow
        onClosing: {
            if(start_stop_librespot.value) {
                librespot.stop()
            }
        }
    }

    // --- Spotify session ----------------------------------------------------
    //
    // hasValidToken: requests can be sent.
    // needsLogin:    Spotify refused the stored session; only the user can
    //                fix that (Settings, Login). Network trouble never sets it.
    //
    // The token is renewed in the background, 10 minutes before it expires.
    // A renewal that fails for lack of network is simply tried again (after
    // 2 s, 4 s, 8 s... up to 1 minute, and at once when the network returns),
    // without any message: the user is only told when a request they asked
    // for cannot be done.

    property int tokenExpireTime: 0 // seconds from epoch
    property bool hasValidToken: false
    property bool needsLogin: false
    property bool _refreshing: false
    property int _refreshFailures: 0
    property real _lastRefreshAttempt: 0

    function _tokenSecondsLeft() {
        return tokenExpireTime - Date.now() / 1000
    }

    // Take the token stored by the compiled part into use.
    function _useToken() {
        tokenExpireTime = spotify.getExpires()
        Spotify._username = spotify.getUserName()
        Spotify.setAccessToken(spotify.getToken(), tokenExpireTime)
        var date = new Date(tokenExpireTime*1000)
        console.log("token expires on: " + date.toDateString() + " " + date.toTimeString())
        _refreshFailures = 0
        refreshRetryTimer.stop()
        needsLogin = false
        connectionText = qsTr("Connected")
        Spotify.tokenReady()
        if(!hasValidToken) {
            hasValidToken = true
            loadUser()
        } else if(app.id === "")
            loadUser()
    }

    function refreshToken() {
        if(_refreshing)
            return
        if(!spotify.isLinked()) {
            _loginNeeded()
            return
        }
        _refreshing = true
        _lastRefreshAttempt = Date.now()
        refreshRetryTimer.stop()
        refreshWatchdog.restart()
        spotify.refreshToken()
    }

    // Renew the token if it is close to its end. Cheap: called often.
    function checkToken() {
        if(needsLogin || !spotify.isLinked())
            return
        if(_tokenSecondsLeft() < 10*60)
            refreshToken()
    }

    function _loginNeeded() {
        var first = !needsLogin
        needsLogin = true
        hasValidToken = false
        refreshRetryTimer.stop()
        connectionText = qsTr("Disconnected")
        Spotify.tokenFailed(true)
        if(first)
            _showRarely("login", qsTr("Spotify asks you to log in again (Settings, Login)"))
    }

    function _refreshFailed() {
        _refreshFailures++
        if(_tokenSecondsLeft() <= 0)
            hasValidToken = false
        refreshRetryTimer.interval = Math.min(60, Math.pow(2, Math.min(_refreshFailures, 6))) * 1000
        refreshRetryTimer.restart()
        console.log("token refresh failed (" + _refreshFailures + "), next try in "
                    + refreshRetryTimer.interval / 1000 + " s")
    }

    Timer {
        // looks every minute whether the token must be renewed
        id: refreshTokenTimer
        interval: 60*1000
        running: tokenExpireTime > 0
        repeat: true
        onTriggered: checkToken()
    }

    Timer {
        id: refreshRetryTimer
        onTriggered: refreshToken()
    }

    Timer {
        // the compiled part gives up after 20 s; this is only a safety net
        id: refreshWatchdog
        interval: 40*1000
        onTriggered: {
            if(_refreshing) {
                _refreshing = false
                _refreshFailed()
            }
        }
    }

    // Timers do not run while the phone sleeps: look at the token as soon as
    // the app is in front again.
    Connections {
        target: Qt.application
        onActiveChanged: if(Qt.application.active) checkToken()
    }

    // General purpose "call this later" (used by Spotify.js to send a
    // request again after a short network gap).
    Component {
        id: laterComponent
        Timer {
            property var action
            onTriggered: {
                try { action() } catch(err) { console.log("callLater: " + err) }
                destroy()
            }
        }
    }
    function callLater(ms, fn) {
        laterComponent.createObject(app, {interval: ms, action: fn, running: true})
    }

    Connections {
        target: spotify

        onExtraTokensReady: { // (const QVariantMap &extraTokens);
            // extraTokens
            //   scope: ""
            //   token_type: "Bearer"
        }

        onLinkingFailed: {
            // the login page was closed or refused; the session is unchanged
            console.log("Connections.onLinkingFailed")
            if(!spotify.isLinked())
                connectionText = qsTr("Disconnected")
        }

        onLinkingSucceeded: {
            // after a login, and after each successful refresh
            console.log("Connections.onLinkingSucceeded")
            _useToken()
        }

        onLinkedChanged: {
            console.log("Connections.onLinkingChanged")
        }

        onRefreshFinished: {
            console.log("Connections.onRefreshFinished error code: " + errorCode +", msg: " + errorString)
            _refreshing = false
            refreshWatchdog.stop()
            if(errorCode === 0)
                _useToken()
            else if(!spotify.isLinked())
                _loginNeeded()      // Spotify refused the session itself
            else
                _refreshFailed()    // network trouble: try again later
        }

        onOpenBrowser: {
            if(auth_using_browser.value)
                Qt.openUrlExternally(url)
            else
                scheduleDelayedAction(function() {
                    // one login page at most
                    var open = pageStack.find(function(page) { return page.objectName === "webAuth" })
                    if(open)
                        open.url = url
                    else
                        pageStack.push(Qt.resolvedUrl("components/WebAuth.qml"),
                                       {url: url, scale: Screen.widthRatio})
                })
        }

        onCloseBrowser: {
            // login done: leave the login page
            scheduleDelayedAction(function() {
                if(pageStack.currentPage && pageStack.currentPage.objectName === "webAuth")
                    pageStack.pop()
            })
        }
    }

    signal devicesChanged()

    onDevicesChanged: {        
        // for logging Librespot discovery
        var ls = isLibrespotInDiscoveredList()
        if(ls !== null) {
            if(logging_flags.discovery)console.log("onDevicesChanged: " + (ls!==null)?"Librespot is discovered":"not yet")
            if(!isLibrespotInDevicesList()) {
                if(logging_flags.discovery)console.log("Librespot is not in the devices list")
                // maybe the list needs to be updated
                if(hasValidToken)
                    spotifyController.checkForNewDevices()
            } else {
                if(logging_flags.discovery)console.log("Librespot is already in the devices list")
            }
        }
        //handleCurrentDevice()
    }

    function handleCurrentDevice() {
        // check if our current device is in the list and if it is active
        var i
        for(i=0;i<spotifyController.devices.count;i++) {
            var device = spotifyController.devices.get(i)
            if(device.name === deviceName.value) {
                if(logging_flags.discovery)console.log("onDevicesChanged found current: " + JSON.stringify(device))
                // Now we want to make sure it is our 'current' Spotify device.
                // How do we know what Spotify thinks our current device is?
                // According to the documentation it should be device.is_active
                // For now we check if the device name of the playback state matches
                // and if it is 'active'.
                // If it does not it means we have to transfer.
                // (first I used 'id' instead of 'name' but that can change due to Spotify)
                if(device.name !== spotifyController.playbackState.device.name
                   && !spotifyController.playbackState.device.is_active) {
                    console.log("Will try to set device to [" + device.name + "] is_active=" + device.is_active + ", pbs.device.name=" + spotifyController.playbackState.device.name)
                    // device still needs to be selected
                    setDevice(device.id, device.name, function(error, data){
                        // no refresh since it might keep on recursing
                        if(error)
                            console.log("Failed to set device [" + deviceName.value + "] as current: " + error)
                        else
                            console.log("Set device [" + deviceName.value + "] as current")
                    })
                } else {
                    if(logging_flags.discovery) {
                        console.log("Device [" + deviceName.value + "] already in playbackState.")
                        console.log("  id: " + deviceId.value + ", pbs id: " + spotifyController.playbackState.device.id)
                    }
                }
                break
            }
        }
    }

    property var foundDevices: []     // the device info queried by getInfo
    property var connectDevices: ({}) // the device info discovered by mdns

    Connections {
        target: spMdns
        onServiceAdded: {
            if(logging_flags.discovery)console.log("onServiceAdded: " + JSON.stringify(serviceJSON,null,2))
            var mdns = JSON.parse(serviceJSON)
            connectDevices[mdns.name] = mdns
        }
        onServiceUpdated: {
            if(logging_flags.discovery)console.log("onServiceUpdated: " + JSON.stringify(serviceJSON,null,2))
            for(var deviceName in connectDevices) {
                var device = connectDevices[deviceName]
                var mdns = JSON.parse(serviceJSON)
                if(device.name === mdns.name) {
                    connectDevices[mdns.name] = mdns
                    devicesChanged()
                    break
                }
            }
        }
        onServiceRemoved: {
            if(logging_flags.discovery)console.log("onServiceRemoved: " + name)
            for(var deviceName in connectDevices) {
                var device = connectDevices[deviceName]
                if(device.name === name) {
                    delete connectDevices[deviceName]
                    // ToDo also delete from foundDevices
                    devicesChanged()
                    break
                }
            }
        }
        onServiceResolved: {
            if(logging_flags.discovery)console.log("onServiceResolved: " + name + " -> " + address)
            for(var deviceName in connectDevices) {
                var device = connectDevices[deviceName]
                if(device.host === name) {
                    device.ip = address
                    Util.deviceInfoRequestMDNS(device, function(error, data) {
                        if(data) {
                            //console.log(JSON.stringify(data,null,2))
                            data.deviceInfo = device
                            var replaced = 0
                            for(var i=0;i<foundDevices.length;i++) {
                              if(foundDevices[i].remoteName === data.remoteName) {
                                  foundDevices[i] = data
                                  replaced = 1
                              }
                            }
                            if(!replaced)
                                foundDevices.push(data)
                            devicesChanged()
                        }
                    })
                    break
                }
            }
        }
    }

    property string id: "" // spotify user id
    property string uri: ""
    property string display_name: ""
    property string product: ""
    property string followers: ""

    function loadUser() {
        Spotify.getMe({}, function(error, data) {
            if(data) {
                try {
                    id = data.id
                    uri = data.uri
                    display_name = data.display_name
                    product = data.product
                    followers = data.followers.total
                } catch (err) {
                    console.log(err)
                }
            } else {
                console.log("No Data for getMe")
            }
        })
        controller.refreshPlaybackState();
    }

    function getPlaylist(playlistId, callback) {
        Spotify.getPlaylist(playlistId, {}, function(error, data) {
            if(callback)
                callback(error, data)
        })
    }

    signal playlistEvent(var event)

    function editPlaylistDetails(playlist, callback) {
        var ms = pageStack.push(Qt.resolvedUrl("components/CreatePlaylist.qml"),
                                {titleText: qsTr("Edit Playlist Details"),
                                 name: playlist.name, description: playlist.description,
                                 publicPL: playlist['public'], collaborative: playlist.collaborative} );
        ms.accepted.connect(function() {
            if(ms.name && ms.name.length > 0) {
                var options = {name: ms.name,
                               'public': ms.publicPL,
                               collaborative: ms.collaborativePL}
                if(ms.description && ms.description.length > 0)
                    options.description = ms.description
                Spotify.changePlaylistDetails(playlist.id, options, function(error, data) {
                    if(callback)
                        callback(error, data)
                    if(!error) {
                        var ev = new Util.PlayListEvent(Util.PlaylistEventType.ChangedDetails,
                                                        playlist.id, playlist.snapshot_id)
                        ev.newDetails = options
                        playlistEvent(ev)
                    }
                })
            }
        })
    }

    function addToPlaylist(track) {

        var ms = pageStack.push(Qt.resolvedUrl("components/PlaylistPicker.qml"),
                                { label: qsTr("Select a Playlist") } );
        ms.accepted.connect(function() {
            if(ms.selectedItem && ms.selectedItem.item) {
                Spotify.addTracksToPlaylist(ms.selectedItem.item.id,
                                            [track.uri], {}, function(error, data) {
                    if(data) {
                        var ev = new Util.PlayListEvent(Util.PlaylistEventType.AddedTrack,
                                                        ms.selectedItem.item.id, data.snapshot_id)
                        ev.trackId = track.id
                        ev.trackUri = track.uri
                        playlistEvent(ev)
                        console.log("addToPlaylist: added \"")
                    } else
                        console.log("addToPlaylist: failed to add \"")
                    console.log(track.name + "\" to \"" + ms.selectedItem.item.name + "\"")
                })
            }
        })
    }

    function removeFromPlaylist(playlist, track, position, callback) {
        app.showConfirmDialog(qsTr("Please confirm to remove:<br><br><b>" + track.name + "</b>"),
                              function() {
            // does not work due to Qt. cannot have DELETE request with a body
            /*Spotify.removeTracksFromPlaylist(playlist.id, [track.uri], function(error, data) {
                callback(error, data)
                var ev = new Util.PlayListEvent(Util.PlaylistEventType.RemovedTrack,
                                                playlist.id, data.snapshot_id)
                ev.trackId = track.id
                playlistEvent(ev)
            })*/

            // if the track is 'linked' we must remove the linked_from one
            var uri = track.uri
            if(track.hasOwnProperty('linked_from'))
                uri = track.linked_from.uri
            removeTracksFromPlaylistUsingCurl(playlist.id, playlist.snapshot_id, [uri], [position], function(error, data) {
                if(callback)
                    callback(error, data)
                var ev = new Util.PlayListEvent(Util.PlaylistEventType.RemovedTrack,
                                                playlist.id, data.snapshot_id)
                ev.trackId = track.id
                playlistEvent(ev)
            })
        })
    }

    function createPlaylist(callback) {
        var ms = pageStack.push(Qt.resolvedUrl("components/CreatePlaylist.qml"),
                                {} );
        ms.accepted.connect(function() {
            if(ms.name && ms.name.length > 0) {
                var options = {name: ms.name,
                               'public': ms.publicPL,
                               collaborative: ms.collaborativePL}
                if(ms.description && ms.description.length > 0)
                    options.description = ms.description
                Spotify.createPlaylist(id, options, function(error, data) {
                    callback(error, data)
                    if(data) {
                        var ev = new Util.PlayListEvent(Util.PlaylistEventType.CreatedPlaylist,
                                                        data.id, data.snapshot_id)
                        ev.playlist = data
                        playlistEvent(ev)
                    }
                })
            }
        })
    }

    function getPlaylistTracks(playlistId, options, callback) {
        if(query_for_market.value) {
            if(!options)
                options = {}
            options.market = "from_token"
        }
        Spotify.getPlaylistTracks(playlistId, options, callback)
    }

    function replaceTracksInPlaylist(playlistId, tracks, callback) {
        Spotify.replaceTracksInPlaylist(playlistId, tracks, function(error, data) {
            if(callback)
                callback(error, data)
            if(data && data.snapshot_id) {
                var ev = new Util.PlayListEvent(Util.PlaylistEventType.ReplacedAllTracks,
                                                playlistId, data.snapshot_id)
                playlistEvent(ev)
                console.log("replaceTracksInPlaylist: snapshot: " + data.snapshot_id)
            } else
                console.log("No Data while replacing tracks in Playlist " + playlistId)
        })
    }

    function loadTracksInModel(data, count, model, getTrack, getExtraProperties) {
        var trackIds = []
        for(var i=0;i<count;i++) {
            var track = getTrack(data, i)
            //console.log(track.id)
            var item = {type: Spotify.ItemType.Track,
                          name: track.name,
                          item: track,
                          following: false,
                          saved: false}
            if(getExtraProperties) {
                var extra = getExtraProperties(data, i)
                for(var attrname in extra)
                    item[attrname] = extra[attrname]
            }
            model.append(item)
            trackIds.push(track.id)
        }
        Spotify.containsMySavedTracks(trackIds, function(error, data) {
            if(data) {
                Util.setSavedInfo(Spotify.ItemType.Track, trackIds, data, model)
            }
        })
    }

    signal favoriteEvent(var event)

    function isFollowingPlaylist(pid, callback) {
        Spotify.areFollowingPlaylist(pid, [id], function(error, data) {
            callback(error, data)
        })
    }

    function followPlaylist(playlist, callback) {
        Spotify.followPlaylist(playlist.id, function(error, data) {
            callback(error, data)
            var event = new Util.FavoriteEvent(Util.SpotifyItemType.Playlist, playlist.id, playlist.uri, true)
            favoriteEvent(event)
        })
    }

    function _unfollowPlaylist(playlist, callback) {
        Spotify.unfollowPlaylist(playlist.id, function(error, data) {
            callback(error, data)
            var event = new Util.FavoriteEvent(Util.SpotifyItemType.Playlist, playlist.id, playlist.uri, false)
            favoriteEvent(event)
        })
    }

    function unfollowPlaylist(playlist, callback) {
        if(confirm_un_follow_save.value)
            app.showConfirmDialog(qsTr("Please confirm to unfollow playlist:<br><br><b>" + playlist.name + "</b>"),
                                  function() {
                _unfollowPlaylist(playlist, callback)
            })
        else
            _unfollowPlaylist(playlist, callback)
    }

    function followArtist(artist, callback) {
        Spotify.followArtists([artist.id], function(error, data) {
            callback(error, data)
            var event = new Util.FavoriteEvent(Util.SpotifyItemType.Artist, artist.id, artist.uri, true)
            favoriteEvent(event)
        })
    }

    function _unfollowArtist(artist, callback) {
        Spotify.unfollowArtists([artist.id], function(error, data) {
            callback(error, data)
            var event = new Util.FavoriteEvent(Util.SpotifyItemType.Artist, artist.id, artist.uri, false)
            favoriteEvent(event)
        })
    }

    function unfollowArtist(artist, callback) {
        if(confirm_un_follow_save.value)
            app.showConfirmDialog(qsTr("Please confirm to unfollow artist:<br><br><b>" + artist.name + "</b>"),
                                  function() {
                _unfollowArtist(artist, callback)
            })
        else
            _unfollowArtist(artist, callback)
    }

    function saveAlbum(album, callback) {
        var id
        if(album.hasOwnProperty("id"))
            id = album.id
        else
            id = Util.parseSpotifyUri(album.uri).id
        Spotify.addToMySavedAlbums([id], function(error, data) {
            callback(error, data)
            var event = new Util.FavoriteEvent(Util.SpotifyItemType.Album, album.id, album.uri, true)
            favoriteEvent(event)
        })
    }

    function _unSaveAlbum(album, callback) {
        Spotify.removeFromMySavedAlbums([album.id], function(error, data) {
            callback(error, data)
            var event = new Util.FavoriteEvent(Util.SpotifyItemType.Album, album.id, album.uri, false)
            favoriteEvent(event)
        })
    }

    function unSaveAlbum(album, callback) {
        if(confirm_un_follow_save.value)
            app.showConfirmDialog(qsTr("Please confirm to un-save album:<br><br><b>" + album.name + "</b>"),
                                  function() {
                _unSaveAlbum(album, callback)
            })
        else
            _unSaveAlbum(album, callback)
    }

    function saveTrack(track, callback) {
        Spotify.addToMySavedTracks([track.id], function(error, data) {
            callback(error, data)
            var event = new Util.FavoriteEvent(Util.SpotifyItemType.Track, track.id, track.uri, true)
            favoriteEvent(event)
        })
    }

    function _unSaveTrack(track, callback) {
        Spotify.removeFromMySavedTracks([track.id], function(error, data) {
            callback(error, data)
            var event = new Util.FavoriteEvent(Util.SpotifyItemType.Track, track.id, track.uri, false)
            favoriteEvent(event)
        })
    }

    function unSaveTrack(track, callback) {
        if(confirm_un_follow_save.value)
            app.showConfirmDialog(qsTr("Please confirm to un-save track:<br><br><b>" + track.name + "</b>"),
                                  function() {
                _unSaveTrack(track, callback)
            })
        else
            _unSaveTrack(track, callback)
    }

    // Add an item (track, album, artist, playlist, podcast, episode,
    // audiobook) to the library or remove it. 'm' is a list model entry
    // with the roles type, item, saved and following.
    function toggleInLibrary(m) {
        var it = m.item
        var type = m.type
        var usesFollowing = (type === Util.SpotifyItemType.Artist
                             || type === Util.SpotifyItemType.Playlist)
        var isIn = usesFollowing ? m.following : m.saved
        var doIt = function() {
            var cb = function(error, data) {
                if(error) {
                    showErrorMessage(error, qsTr("Failed"))
                    return
                }
                if(usesFollowing)
                    m.following = !isIn
                else
                    m.saved = !isIn
                favoriteEvent(new Util.FavoriteEvent(type, it.id, it.uri, !isIn))
                msgBox.showMessage(!isIn ? qsTr("Added to your library")
                                         : qsTr("Removed from your library"), 1500)
            }
            if(isIn)
                Spotify.removeFromLibrary([it.uri], cb)
            else
                Spotify.saveToLibrary([it.uri], cb)
        }
        if(isIn && confirm_un_follow_save.value)
            showConfirmDialog(qsTr("Remove from your library?") + "<br><br><b>" + it.name + "</b>", doIt)
        else
            doIt()
    }

    function toggleSavedTrack(model) {
        if(model.saved)
            unSaveTrack(model.item, function(error,data) {
                if(!error)
                    model.saved = false
            })
        else
            saveTrack(model.item, function(error,data) {
                if(!error)
                    model.saved = true
            })
    }

    function toggleSavedAlbum(album, isAlbumSaved, callback) {
        if(isAlbumSaved)
            unSaveAlbum(album, function(error,data) {
                if(!error)
                    callback(false)
            })
        else
            saveAlbum(album, function(error,data) {
                if(!error)
                    callback(true)
            })
    }

    function toggleFollowArtist(artist, isFollowed, callback) {
        if(isFollowed)
            unfollowArtist(artist, function(error,data) {
                if(!error)
                    callback(false)
            })
        else
            followArtist(artist, function(error,data) {
                if(!error)
                    callback(true)
            })
    }

    function toggleFollowPlaylist(playlist, isFollowed, callback) {
        if(isFollowed)
             unfollowPlaylist(playlist, function(error, data) {
                 if(!error)
                     callback(false)
             })
         else
             followPlaylist(playlist, function(error, data) {
                 if(!error)
                     callback(true)
             })
    }

    function loadArtist(artists, fromPlaying) {
        if(artists.length > 1) {
            // choose
            var ms = pageStack.push(Qt.resolvedUrl("components/ArtistPicker.qml"),
                                    { label: qsTr("View an Artist"), artists: artists } );
            ms.done.connect(function() {
                if(ms.selectedItem) {
                    app.pushPage(Util.HutspotPage.Artist, {currentArtist: ms.selectedItem.item}, fromPlaying)
                }
            })
        } else if(artists.length === 1) {
            app.pushPage(Util.HutspotPage.Artist, {currentArtist:artists[0]}, fromPlaying)
        }
    }

    QueueController {
        id: queue
    }

    Librespot {
        id: librespot
    }

    // check if the Librespot service is known to Spotify
    function isLibrespotInDevicesList() {
        var i
        // we cannot determine the name if it is not running
        if(!librespot.serviceRunning)
            return false
        var devName = librespot.getName()
        if(devName.length === 0) // failed to determine the name
            return null
        for(i=0;i<spotifyController.devices.count;i++) {
            var device = spotifyController.devices.get(i)
            if(device.name === devName)
                return device
        }
        return null
    }

    // check if the Librespot service is discovered on the network
    function isLibrespotInDiscoveredList() {
        var i
        // we cannot determine the name if it is not running
        if(!librespot.serviceRunning)
            return false
        var devName = librespot.getName()
        if(devName.length === 0) // failed to determine the name
            return null
        for(i=0;i<foundDevices.length;i++) {
            var device = foundDevices[i]
            if(device.remoteName === devName)
                return device
        }
        return null
    }

    Connections {
        target: spotifyController
        onDevicesReloaded: {
            librespotAtStart.notifyHappend(librespotAtStart.deviceListReadyMask)
        }
    }

    function getAppIconSource() {
        return getAppIconSource2(Theme.iconSizeExtraLarge)
    }

    function getAppIconSource2(iconSize) {
        if (iconSize < 108)
            iconSize = 86
        else if (iconSize < 128)
            iconSize = 108
        else if (iconSize < 256)
            iconSize = 128
        else
            iconSize = 256
        return "/usr/share/icons/hicolor/" + iconSize + "x" + iconSize + "/apps/hutspot.png"
    }

    /**
     * can have a 3rd param: rejectCallback
     */
    function showConfirmDialog(text, acceptCallback) {
        var dialog = pageStack.push(Qt.resolvedUrl("components/ConfirmDialog.qml"),
                                                   {confirmMessageText: text})
        if(acceptCallback !== null)
            dialog.accepted.connect(acceptCallback)
        if(arguments.length >= 3 && arguments[2] !== null)
            dialog.rejected.connect(arguments[2])
    }

    /**
     * List of last visited albums/artists/playlists
     */
    readonly property int historySize: 50
    property var history: []
    signal historyModified(int added, int removed)
    function notifyHistoryUri(uri) {
        var removedIndex = -1
        if(history.length === 0) {
            history.unshift(uri)
        } else if(history[0] === uri) {
            // already at the top
            return
        } else {
            // add to the top
            history.unshift(uri)
            // remove if already present
            for(var i=1;i<history.length;i++)
                if(history[i] === uri) {
                    history.splice(i, 1)
                    removedIndex = i - 1 // -1 since the model does not have the new one yet
                    break
                }
        }
        historyModified(0, removedIndex)
        if(history.length > historySize) { // make configurable
            history.pop()
            historyModified(-1, historySize-1)
        }
        history_store.value = history
    }

    function clearHistory() {
        history = []
        history_store.value = history
        historyModified(-1, -1)
    }

    //
    // MediaKeys: see components/HeadsetKeys.qml (loaded below). On Sailfish
    // the keys only arrive once the HeadsetButtons resource is reserved.
    //

    //
    // Configuration
    //

    ConfigurationValue {
            id: deviceId
            key: "/hutspot/device_id"
            defaultValue: ""
    }

    ConfigurationValue {
            id: deviceName
            key: "/hutspot/device_name"
            defaultValue: ""
    }

    ConfigurationValue {
        id: searchLimit
        key: "/hutspot/search_limit"
        defaultValue: 50
    }

    ConfigurationValue {
            id: selected_search_targets
            key: "/hutspot/selected_search_targets"
            defaultValue: 0xFFF
    }

    ConfigurationValue {
            id: auth_using_browser
            key: "/hutspot/auth_using_browser"
            defaultValue: false
    }

    ConfigurationValue {
            id: firstPage
            key: "/hutspot/first_page"
            defaultValue: ""
    }

    ConfigurationValue {
            id: start_stop_librespot
            key: "/hutspot/start_stop_librespot"
            defaultValue: true
    }

    ConfigurationValue {
            id: enable_connect_discovery
            key: "/hutspot/enable_connect_discovery"
            defaultValue: true
    }

    ConfigurationValue {
            id: confirm_un_follow_save
            key: "/hutspot/confirm_un_follow_save"
            defaultValue: true
    }

    // 0 for NavigationMenuDialog
    // 1 for NavigationMenu as attached page
    // 2 for NavigationPanel
    // 3 for panel with controls and hamburger button
    ConfigurationValue {
            id: navigation_menu_type
            key: "/hutspot/navigation_menu_type"
            defaultValue: 3
    }

    ConfigurationValue {
            id: playing_as_attached_page
            key: "/hutspot/playing_as_attached_page"
            defaultValue: true
    }

    ConfigurationValue {
            id: history_store
            key: "/hutspot/history"
            defaultValue: []
    }

    ConfigurationValue {
            id: genre_seeds
            key: "/hutspot/genre_seeds"
            defaultValue: []
    }

    ConfigurationGroup {
        id: recommended_attributes
        path: "/hutspot/recommended_attributes"

        property real energy: 0.5
        property real danceability: 0.5
        property real instrumentalness: 0.5
        property real speechiness: 0.5
        property real acousticness: 0.5
        property real liveness: 0.5
        property real valence: 0.5
        property int popularity: 50
    }

    ConfigurationGroup {
        id: current_item_classes
        path: "/hutspot/current_item_classes"

        property int topStuff: 0
        property int search: 0
        property int recommended: 0
        property int myStuff: 0
        property int artist: 0
        property int featuredStuff: 0
    }

    ConfigurationValue {
            id: hutspot_queue_playlist_name
            key: "/hutspot/hutspot_queue_playlist_name"
            defaultValue: "Hutspot Queue"
    }

    ConfigurationValue {
        id: search_history
        key: "/hutspot/search_history"
        defaultValue: []
    }

    ConfigurationValue {
        id: search_history_max_size
        key: "/hutspot/search_history_max_size"
        defaultValue: 50
    }

    ConfigurationValue {
            id: query_for_market
            key: "/hutspot/query_for_market"
            defaultValue: true
    }

    ConfigurationValue {
            id: show_devices_page_at_startup
            key: "/hutspot/show_devices_page_at_startup"
            defaultValue: false
    }

    ConfigurationValue { // in ms
        id: controlpanel_show_delay
        key: "/hutspot/controlpanel_show_delay"
        defaultValue: 700
    }

    ConfigurationGroup {
        id: logging_flags
        path: "/hutspot/logging_flags"

        property bool discovery: false
    }

    ConfigurationGroup {
        id: locale_config
        path: "/hutspot/locale_config"

        property string country: ""
    }

    /*ConfigurationValue {
            id: auto_load_lists
            key: "/hutspot/auto_load_lists"
            defaultValue: true
    }*/

    /*function updateConfigurationData() {
        if(configuration_data_version.value === currentConfigurationDataVersion)
            return

        if(configuration_data_version.value === 0) {
            // menu type from 0..1 to 0..2
            if(navigation_menu_type.value === 1)
                navigation_menu_type.value = 2
        }

        configuration_data_version.value = currentConfigurationDataVersion
    }

    readonly property int currentConfigurationDataVersion: 2
    ConfigurationValue {
            id: configuration_data_version
            key: "/hutspot/configuration_data_version"
            defaultValue: 0
    }*/

    // QML seems unable to send a http DELETE request with a body.
    // Therefore this is done using curl
    //
    // curl -X DELETE -i -H "Authorization: Bearer {your access token}"
    //      -H "Content-Type: application/json" "https://api.spotify.com/v1/playlists/71m0QB5fUFrnqfnxVerUup/tracks"
    //      --data "{\"tracks\":[{\"uri\": \"spotify:track:4iV5W9uYEdYUVa79Axb7Rh\", \"positions\": [2] },{\"uri\":\"spotify:track:1301WleyT98MSxVHPZCA6M\", \"positions\": [7] }] }"

    // assumes the uris and positions arrays are equal length and 1 uri has 1 position
    function removeTracksFromPlaylistUsingCurl(playlistId, snapshotId, uris, positions, callback) {
        var command = "/usr/bin/curl"
        var args = []
        args.push("-X")
        args.push("DELETE")
        //args.push("-i") // include headers in the output
        args.push("-H")
        args.push("Authorization: Bearer " + Spotify.getAccessToken())
        args.push("-H")
        args.push("Content-Type: application/json")
        args.push(Spotify._baseUri + "/playlists/" + playlistId + "/items")
        args.push("--data")

        var data = "{\"items\":["
        for(var i=0;i<uris.length;i++) {
            if(i>0)
                data += ","
            data += "{\"uri\":\"" + uris[i] + "\",\"positions\":[" +positions[i]+ "]}"
        }
        //data += "],\"snapshot_id\":\"" + snapshotId + "\"}"
        data += "]}"
        args.push(data)

        process.callback = callback
        process.start(command, args)
    }

    Process {
        id: process

        property var callback: undefined

        workingDirectory: StandardPaths.home

        onError: {
            if(callback !== undefined)
                callback(process.error, undefined)
            console.log("Process.Error: " + process.error)
            callback = undefined
        }

        onFinished: {
            var output = process.readAllStandardOutput()
            console.log("Process.Finished: " + process.exitStatus + ", code: " + process.exitCode)
            console.log(output)
            if(callback !== undefined)
                callback(null, JSON.parse(output))
            callback = undefined
        }
    }

    property alias dockedPanel: dockedPanel
    DockedPanel {
        id: dockedPanel
        open: true

        width: parent.width
        height: cp.height
        dock: Dock.Bottom

        // allow to force the panel to stay hidden, for example for the menu page
        property bool _hidden: false
        property bool _savedOpen: false
        function setHidden() { _hidden = true; _savedOpen = open; open = false }
        function resetHidden() { _hidden = false; open = _savedOpen }

        // we want to 'share' the dockedPanel so every page must
        // register/unregister it's listview when it becomes active
        property SilicaListView listView: null

        function registerListView(lv) {
            lv.onContentYChanged.connect(notifyVScrolling)
            lv.onIsAtBoundaryChanged.connect(notifyIsAtYEndChanged)
            listView = lv
        }

        function unregisterListView(lv) {
            if(listView === lv)
                listView = null
            lv.onContentYChanged.disconnect(notifyVScrolling)
            lv.onIsAtBoundaryChanged.disconnect(notifyIsAtYEndChanged)
        }

        Item {
            id: cp
            property real itemHeight: 0
            width: parent.width
            height: itemHeight
            y: 0
            Loader {
                id: loader
                width: parent.width
                height: parent.height

                source: {
                    switch(app.navigation_menu_type.value) {
                    case 1:
                    case 2: return "components/NavigationPanel.qml"
                    case 3: return "components/ControlPanel.qml"
                    default: return ""
                    }
                }
                onLoaded: {
                    cp.itemHeight = item.implicitHeight
                    if(app.navigation_menu_type.value === 1)
                        dockedPanel.open = false
                }
            }
        }

        //property real vSize: parent.height - dockedPanel.y + dockedPanel.contentY

        property bool _fixAtEnd: false
        property bool _atEnd: false

        function doAutoStuff() {
            return navigation_menu_type.value >= 2
                   && controlpanel_show_delay.value > 0
        }

        function notifyIsAtYEndChanged() {
            if(!doAutoStuff())
                return
            dockedPanel._atEnd = listView.atYEnd
            //console.log("notifyIsAtYEndChanged: " + dockedPanel._atEnd)
        }

        onMovingChanged: {
            if(!doAutoStuff())
                return
            //console.log("onMovingChanged: moving" + moving + ", _fixAtEnd: " + _fixAtEnd)
            if(!moving) {
                if(_fixAtEnd && listView)
                    listView.positionViewAtEnd()
            }
        }

        // hide the panel when scrolling
        function notifyVScrolling() {
            // when nothing should be done
            if(!doAutoStuff())
                return
            if(_hidden)
                return
            // do not hide when last element is just above panel
            if(_atEnd)
                return
            // do not hide when pull/push is active (copied from VerticalScrollDecorator)
            var inBounds = (!listView.pullDownMenu || !listView.pullDownMenu.active)
                           && (!listView.pushUpMenu || !listView.pushUpMenu.active)
            if(!inBounds)
                return
            dockedPanel._fixAtEnd = false
            dockedPanel.open = false
            noScrollDetect.restart()
        }

        Timer {
            id: noScrollDetect
            interval: controlpanel_show_delay.value
            repeat: false
            onTriggered: {
                // when nothing should be done
                if(dockedPanel._hidden)
                    return
                dockedPanel._fixAtEnd = dockedPanel._atEnd
                dockedPanel.open = true
            }
        }

    }

    //
    // Detect headphone connect/disconnect using DBus
    //

    // 0: speaker, 1: headphone, 2: bluetooth
    property int audioOutputRoute: 0

    DBusInterface {
        id: routeManager
        bus: DBus.SystemBus
        service: "org.nemomobile.Route.Manager"
        path: "/org/nemomobile/Route/Manager"
        iface: "org.nemomobile.Route.Manager"
        signalsEnabled: true

        // insert: [D] onAudioRouteChanged:1213 - DBus org.nemomobile.Route.Manager string=headphone, uint32=9
        // insert: [D] onAudioRouteChanged:1213 - DBus org.nemomobile.Route.Manager string=bluetootha2dp, uint32=17
        // remove: [D] onAudioRouteChanged:1213 - DBus org.nemomobile.Route.Manager string=speaker, uint32=5

        // insert: [D] onAudioRouteChanged:1422 - DBus org.nemomobile.Route.Manager string=headset, uint32=10
        // remove: [D] onAudioRouteChanged:1422 - DBus org.nemomobile.Route.Manager string=microphone, uint32=6

        signal audioRouteChanged(string s, int i)
        onAudioRouteChanged: {
            console.log("DBus org.nemomobile.Route.Manager string=" + s + ", uint32=" + i)
            switch(i) {
            case 5: // speaker
                // if switched to speaker assume headset is disconnected and stop playing
                if(audioOutputRoute !== 0)
                    controller.pause()
                audioOutputRoute = 0
                break
            case 9: // headphone
                audioOutputRoute = 1
                break
            case 17: // bluetooth
                audioOutputRoute = 2
                break
            }
        }

        //
        function updateInfo() {
            var output_device = ""
            var output_device_mask = 0
            var input_device = ""
            var input_device_mask = 0
            var features = 0

            /* can't get correct type for 'features'
            typedCall("GetAll", [{"type":"s", "value": output_device},
                                 {"type":"u", "value": output_device_mask},
                                 {"type":"s", "value": input_device},
                                 {"type":"u", "value": input_device_mask},
                                 {"type":"a(suu)", "value": features}],
                      function(output_device, output_device_mask, input_device, input_device_mask, features) {
                          console.log("routeManager: GetAll() succeeded info = " + info)
                          console.log("  output_device: " + output_device)
                          console.log("  output_device_mask: " + output_device_mask)
                          console.log("  input_device: " + input_device)
                          console.log("  input_device_mask: " + input_device_mask)
                          console.log("  features: " + features)
                      },
                      function() {
                          console.log("routeManager: GetAll() failed")
                      })*/

            typedCall("ActiveRoutes", [{"type":"s", "value": output_device},
                                       {"type":"u", "value": output_device_mask},
                                       {"type":"s", "value": input_device},
                                       {"type":"u", "value": input_device_mask}],
                      function(output_device, output_device_mask, input_device, input_device_mask) {
                          console.log("RouteManager.ActiveRoutes() results:")
                          console.log("  output_device: " + output_device)
                          console.log("  output_device_mask: " + output_device_mask)
                          console.log("  input_device: " + input_device)
                          console.log("  input_device_mask: " + input_device_mask)
                          switch(output_device_mask) {
                          case 5: // speaker
                              audioOutputRoute = 0
                              break
                          case 9: // headphone
                              audioOutputRoute = 1
                              break
                          case 17: // bluetooth
                              audioOutputRoute = 2
                              break
                          }
                      },
                      function() {
                          console.log("RouteManager.ActiveRoutes() failed")
                      })
        }

        Component.onCompleted: updateInfo()
    }

    signal spotifyDataCacheReady()

    Item {
        id: doBeforeStart

        readonly property int followedPlaylistsMask: 0x01
        readonly property int followedArtistsMask: 0x02
        readonly property int savedAlbumsMask: 0x04
        readonly property int savedTracksMask: 0x08

        readonly property int triggerMask: 0x0F
        property int happendMask: 0

        function notifyHappend(mask) {
            happendMask |= mask
            if((happendMask & triggerMask) === triggerMask) {
                spotifyDataCacheReady()
            }
        }
    }

    // --- Remote control from the car (Sailplay) ---------------------------

    // A Spotify URI chosen on the car screen (MPRIS OpenUri). It is played as
    // soon as the app has a valid token.
    property string _remoteUri: ""
    function playFromRemote(uri) {
        if(!uri || uri.indexOf("spotify:") !== 0)
            return
        if(!hasValidToken) {
            _remoteUri = uri
            return
        }
        var type = uri.split(":")[1]
        if(type === "track" || type === "episode" || type === "chapter")
            controller.playTrack({uri: uri})
        else
            controller.playContext({uri: uri})
    }
    Connections {
        target: app
        onHasValidTokenChanged: {
            if(app.hasValidToken && app._remoteUri !== "") {
                var uri = app._remoteUri
                app._remoteUri = ""
                app.playFromRemote(uri)
            }
            if(app.hasValidToken)
                carLibraryDelay.restart()
        }
    }

    // Library summary for the "Browse" button of the car screen. The Sailplay
    // service (python/sailplay_service.py) reads it from LocalStorage, so it
    // works without a Spotify token of its own.
    Timer {
        id: carLibraryDelay
        interval: 8000      // let the pages load first
        onTriggered: refreshCarLibrary()
    }
    Timer {
        interval: 6 * 3600 * 1000
        repeat: true
        running: hasValidToken
        onTriggered: refreshCarLibrary()
    }
    onFavoriteEvent: carLibraryDelay.restart()

    // images: a Spotify image list, largest first. The car shows cards of
    // about 100 px: take the medium picture (300 px) when there is one.
    function _carItem(uri, title, subtitle, images) {
        var item = {uri: uri, title: title ? title : "", subtitle: subtitle ? subtitle : ""}
        if(images && images.length > 0) {
            var picture = images[images.length > 1 ? 1 : 0]
            if(picture && picture.url)
                item.image = picture.url
        }
        return item
    }

    function refreshCarLibrary() {
        var lib = {playlists: [], albums: [], shows: [], audiobooks: [], recent: []}
        var steps = [
            function(next) {
                Spotify.getUserPlaylists({limit: 50}, function(error, data) {
                    if(data && data.items)
                        for(var i=0;i<data.items.length;i++) {
                            var p = data.items[i]
                            if(p)
                                lib.playlists.push(_carItem(p.uri, p.name,
                                    p.owner && p.owner.display_name ? p.owner.display_name : "", p.images))
                        }
                    next()
                })
            },
            function(next) {
                var push = function(list) {
                    for(var i=0;i<list.length;i++) {
                        var a = list[i].album
                        if(a)
                            lib.albums.push(_carItem(a.uri, a.name,
                                a.artists && a.artists.length > 0 ? a.artists[0].name : "", a.images))
                    }
                }
                var cached = LibraryCache.savedAlbums()
                if(cached) {
                    push(cached)
                    lib.albums.sort(function(x, y) { return x.title.localeCompare(y.title) })
                    next()
                    return
                }
                var all = []
                var page = function(offset) {
                    Spotify.getMySavedAlbums({offset: offset, limit: 50}, function(error, data) {
                        if(data && data.items) {
                            all = all.concat(data.items)
                            if(data.items.length > 0 && all.length < data.total) {
                                page(all.length)
                                return
                            }
                            LibraryCache.setSavedAlbums(all)
                        }
                        push(all)
                        lib.albums.sort(function(x, y) { return x.title.localeCompare(y.title) })
                        next()
                    })
                }
                page(0)
            },
            function(next) {
                Spotify.getMySavedShows({limit: 50, market: "from_token"}, function(error, data) {
                    if(data && data.items)
                        for(var i=0;i<data.items.length;i++) {
                            var sh = data.items[i] ? data.items[i].show : null
                            if(sh)
                                lib.shows.push(_carItem(sh.uri, sh.name, sh.publisher, sh.images))
                        }
                    next()
                })
            },
            function(next) {
                Spotify.getMySavedAudiobooks({limit: 50, market: "from_token"}, function(error, data) {
                    if(data && data.items)
                        for(var i=0;i<data.items.length;i++) {
                            var b = data.items[i] ? (data.items[i].audiobook ? data.items[i].audiobook : data.items[i]) : null
                            if(b)
                                lib.audiobooks.push(_carItem(b.uri, b.name,
                                    b.authors ? Util.createItemsString(b.authors, "") : "", b.images))
                        }
                    next()
                })
            },
            function(next) {
                Spotify.getMyRecentlyPlayedTracks({limit: 50}, function(error, data) {
                    var seen = {}
                    if(data && data.items)
                        for(var i=0;i<data.items.length;i++) {
                            var t = data.items[i] ? data.items[i].track : null
                            if(t && !seen[t.uri]) {
                                seen[t.uri] = true
                                lib.recent.push(_carItem(t.uri, t.name,
                                    t.artists ? Util.createItemsString(t.artists, "") : "",
                                    t.album ? t.album.images : null))
                            }
                        }
                    next()
                })
            }
        ]
        var run = function(index) {
            if(index >= steps.length) {
                lib.updated = Date.now()
                LibraryCache.setCarLibrary(lib)
                return
            }
            steps[index](function() { run(index + 1) })
        }
        run(0)
    }

    Loader {  // D-Bus name of the app, lets Sailplay start it from the car
        source: "components/DBusControl.qml"
        onStatusChanged: if (status === Loader.Error) console.log("Nemo.DBus unavailable")
    }

    Loader {  // headset buttons (HeadsetButtons resource of Sailfish)
        source: "components/HeadsetKeys.qml"
        onStatusChanged: if (status === Loader.Error) console.log("Headset buttons unavailable")
    }

    Component.onCompleted: {
        // Navigation is done with the pull-down menu of each page, the
        // docked panel at the bottom is the mini player (ControlPanel).
        if(navigation_menu_type.value !== 3)
            navigation_menu_type.value = 3
        loadFirstPage()
        startSpotify()
    }

    property var scheduledActions: []
    function scheduleDelayedAction(action) {
        scheduledActions.push(action)
        scheduleTimer.running = true
    }

    // When trying to show a page or dialog, especially at startup
    // we have problems due to those horrible animating stuff. For example
    //   doPush:137 - Warning: cannot push while transition is in progress
    // so we put it in a timer. If you know of a better way please tell us.
    Timer {
        id: scheduleTimer
        repeat: true
        running: false
        interval: 500
        onTriggered: {
            if(scheduledActions.length == 0)
                return
            if(pageStack.busy)
                return
            try {
                var action = scheduledActions.shift()
                action()
            } catch(err) {
                console.log("scheduleTimer: " + err)
            } finally {
                running = scheduledActions.length > 0
            }
        }
    }

    // The phone changes network all the time (Wi-Fi, mobile data, tunnels,
    // no coverage). None of that is an error and nothing is shown: requests
    // in progress are retried or dropped quietly, and the session is kept.
    // When a network comes back, the token is checked and the player state
    // is read again at once instead of waiting for the next poll.
    property bool online: networkConnection.networkConnected !== Util.NetworkState.Disconnected

    NetworkConnection {
        id: networkConnection
        onChanged: {
            console.log("network: " + networkConnected)
            if(networkConnected === Util.NetworkState.Connected)
                networkBackTimer.restart()
        }
    }

    Timer {
        // several signals arrive for one change of network: act once
        id: networkBackTimer
        interval: 1500
        onTriggered: {
            if(needsLogin || !spotify.isLinked())
                return
            if(!hasValidToken || _refreshFailures > 0 || _tokenSecondsLeft() < 10*60) {
                _refreshFailures = 0
                refreshToken()
            } else
                controller.refreshPlaybackState()
        }
    }

}
