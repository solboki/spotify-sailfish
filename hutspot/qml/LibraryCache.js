/**
 * Cache of the user's saved albums, kept in memory and on the phone
 * (LocalStorage). Sorting the albums then needs no new download: the list
 * is fetched again only when asked ("Reload"), when an album is saved or
 * removed, or when the cache is older than MAX_AGE_MS.
 *
 * License: MIT
 */

.pragma library
.import QtQuick.LocalStorage 2.0 as Sql

var MAX_AGE_MS = 24 * 3600 * 1000   // one day

var _albums = null   // [{added_at, album}] or null
var _ts = 0
var _db = null
var _loaded = false

function _open() {
    if (_db)
        return _db
    _db = Sql.LocalStorage.openDatabaseSync("hutspot-fork", "1.0", "Hutspot fork cache", 2000000)
    _db.transaction(function(tx) {
        tx.executeSql('CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT, ts INTEGER)')
    })
    return _db
}

function _load() {
    if (_loaded)
        return
    _loaded = true
    try {
        _open().readTransaction(function(tx) {
            var rs = tx.executeSql("SELECT v, ts FROM kv WHERE k = 'saved_albums'")
            if (rs.rows.length > 0) {
                _albums = JSON.parse(rs.rows.item(0).v)
                _ts = rs.rows.item(0).ts
            }
        })
    } catch (e) {
        console.log("LibraryCache: " + e)
    }
}

// Keep only what the pages need, to keep the cache small.
function _slim(saved) {
    var a = saved.album
    var images = a.images ? a.images.slice(0, 2) : []
    var artists = []
    if (a.artists)
        for (var i = 0; i < a.artists.length; i++)
            artists.push({id: a.artists[i].id, name: a.artists[i].name,
                          uri: a.artists[i].uri, type: "artist"})
    return {
        added_at: saved.added_at,
        album: {
            id: a.id, name: a.name, uri: a.uri, type: "album",
            album_type: a.album_type, release_date: a.release_date,
            total_tracks: a.total_tracks, images: images, artists: artists
        }
    }
}

// The cached list, or null when there is none or it is too old.
function savedAlbums() {
    _load()
    if (!_albums || Date.now() - _ts > MAX_AGE_MS)
        return null
    return _albums
}

function setSavedAlbums(list) {
    var slim = []
    for (var i = 0; i < list.length; i++)
        if (list[i] && list[i].album)
            slim.push(_slim(list[i]))
    _albums = slim
    _ts = Date.now()
    try {
        _open().transaction(function(tx) {
            tx.executeSql('INSERT OR REPLACE INTO kv VALUES(?, ?, ?)',
                          ['saved_albums', JSON.stringify(slim), _ts])
        })
    } catch (e) {
        console.log("LibraryCache: " + e)
    }
    return slim
}

function invalidate() {
    _albums = null
    _ts = 0
    try {
        _open().transaction(function(tx) {
            tx.executeSql("DELETE FROM kv WHERE k = 'saved_albums'")
        })
    } catch (e) {
        console.log("LibraryCache: " + e)
    }
}


// Summary of the library for the "Browse" button of the car screen
// (Sailplay). Read by python/sailplay_service.py.
function setCarLibrary(lib) {
    try {
        _open().transaction(function(tx) {
            tx.executeSql('INSERT OR REPLACE INTO kv VALUES(?, ?, ?)',
                          ['car_library', JSON.stringify(lib), Date.now()])
        })
    } catch (e) {
        console.log("LibraryCache: " + e)
    }
}
