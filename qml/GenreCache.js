/**
 * Cache of the genres of artists, kept on the phone (LocalStorage) so the
 * genres of a library are fetched from Spotify only once.
 *
 * Since February 2026 Spotify no longer offers "Get Several Artists", so the
 * artists are fetched one by one: the cache keeps that cost low.
 *
 * License: MIT
 */

.pragma library
.import QtQuick.LocalStorage 2.0 as Sql
.import "Spotify.js" as Spotify

var _db = null
var _mem = {}
var _loaded = false

// Genres are refreshed after 90 days
var MAX_AGE_MS = 90 * 24 * 3600 * 1000

function _open() {
    if (_db)
        return _db
    _db = Sql.LocalStorage.openDatabaseSync("hutspot-fork", "1.0", "Hutspot fork cache", 2000000)
    _db.transaction(function(tx) {
        tx.executeSql('CREATE TABLE IF NOT EXISTS artist_genres(id TEXT PRIMARY KEY, genres TEXT, ts INTEGER)')
    })
    return _db
}

function _load() {
    if (_loaded)
        return
    _loaded = true
    try {
        var now = Date.now()
        _open().readTransaction(function(tx) {
            var rs = tx.executeSql('SELECT id, genres, ts FROM artist_genres')
            for (var i = 0; i < rs.rows.length; i++) {
                var row = rs.rows.item(i)
                if (now - row.ts < MAX_AGE_MS)
                    _mem[row.id] = JSON.parse(row.genres)
            }
        })
    } catch (e) {
        console.log("GenreCache: " + e)
    }
}

// Returns the list of genres, or undefined when not known yet.
function get(artistId) {
    _load()
    return _mem.hasOwnProperty(artistId) ? _mem[artistId] : undefined
}

function _put(artistId, genres) {
    _mem[artistId] = genres
    try {
        _open().transaction(function(tx) {
            tx.executeSql('INSERT OR REPLACE INTO artist_genres VALUES(?, ?, ?)',
                          [artistId, JSON.stringify(genres), Date.now()])
        })
    } catch (e) {
        console.log("GenreCache: " + e)
    }
}

// Fetch the genres of the artists not in the cache, one request at a time.
// progress(done, total) is called after each artist, finished() at the end.
function fetchMissing(artistIds, progress, finished) {
    _load()
    var missing = []
    var seen = {}
    for (var i = 0; i < artistIds.length; i++) {
        var id = artistIds[i]
        if (id && !seen[id] && !_mem.hasOwnProperty(id)) {
            seen[id] = true
            missing.push(id)
        }
    }
    var next = function(index) {
        if (index >= missing.length) {
            if (finished)
                finished()
            return
        }
        Spotify.getArtist(missing[index], {}, function(error, data) {
            if (data)
                _put(missing[index], data.genres ? data.genres : [])
            if (progress)
                progress(index + 1, missing.length)
            next(index + 1)
        })
    }
    next(0)
}

// Main genre of an artist, with a capital first letter, or "" if unknown.
function mainGenre(artistId) {
    var g = get(artistId)
    if (!g || g.length === 0)
        return ""
    return g[0].charAt(0).toUpperCase() + g[0].slice(1)
}
