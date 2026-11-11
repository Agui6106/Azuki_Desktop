// Azuki Tile Deck — importación explícita de metadatos RAWG.
// Funciones puras: ninguna operación de red, disco ni ejecución.
.pragma library
.import "TileModel.js" as TileModel

var FIELD_NAMES = ["name", "description", "releaseDate", "developers", "publishers", "genres", "rating", "metacritic"]

function copy(value) { return JSON.parse(JSON.stringify(value)) }
function sourceId(value) {
    var text = String(value)
    if (!/^[0-9]{1,12}$/.test(text) || Number(text) < 1)
        throw new Error("ID de RAWG inválido")
    return text
}
function sourceMatch(item, id) {
    var m = item.metadata || {}
    return m.provider === "rawg" && String(m.providerId) === String(id)
}
function findSource(library, id) {
    for (var i = 0; i < library.items.length; ++i)
        if (sourceMatch(library.items[i], id)) return library.items[i]
    return null
}
function available(game) {
    if (!game || typeof game !== "object") return {}
    var m = {
        name: typeof game.name === "string" && game.name.trim() !== "",
        description: typeof game.description === "string" && game.description.trim() !== "",
        releaseDate: typeof game.released === "string" && /^\d{4}(-\d{2}-\d{2})?$/.test(game.released),
        developers: Array.isArray(game.developers) && game.developers.length > 0,
        publishers: Array.isArray(game.publishers) && game.publishers.length > 0,
        genres: Array.isArray(game.genres) && game.genres.length > 0,
        rating: typeof game.rating === "number" && isFinite(game.rating) && game.rating >= 0 && game.rating <= 5,
        metacritic: typeof game.metacritic === "number" && isFinite(game.metacritic) && game.metacritic >= 0 && game.metacritic <= 100
    }
    return m
}
function defaultFields(game, isNew) {
    var a = available(game), fields = {}
    FIELD_NAMES.forEach(function(key) { fields[key] = a[key] && (key !== "name" || isNew) })
    return fields
}
function cleanList(value) {
    return value.filter(function(v) { return typeof v === "string" && v.trim() !== "" })
                .map(function(v) { return v.trim() })
}
function normalizeSource(game) {
    var id = sourceId(game.id)
    var a = available(game)
    if (!a.name) throw new Error("RAWG no devolvió un nombre válido")
    var name = TileModel.cleanTitle(game.name)
    if (name.length > 200) throw new Error("El nombre de RAWG es demasiado largo")
    return {id: id, name: name, available: a}
}
function makeId(library, source) {
    var base = "rawg-" + source, id = base, n = 2
    while (TileModel.findItem(library.items, id)) id = base + "-" + n++
    return id
}
function buildCandidate(rawLibrary, game, options) {
    var library = TileModel.normalizeLibrary(rawLibrary)
    var source = normalizeSource(game)
    var opts = options || {}, isNew = opts.mode === "new"
    if (!isNew && opts.mode !== "existing") throw new Error("Selecciona cómo importar")
    var fields = opts.fields || {}, a = source.available
    var chosen = FIELD_NAMES.filter(function(key) { return fields[key] === true && a[key] === true })
    if (!chosen.length) throw new Error("Selecciona al menos un campo disponible")
    var sameSource = findSource(library, source.id)
    var item, index = -1
    if (isNew) {
        if (sameSource) throw new Error("Este juego ya está asociado a «" + sameSource.name + "». Selecciona ese elemento para actualizarlo.")
        var appId = String(opts.steamAppId || "").trim()
        if (appId && !/^[0-9]{1,20}$/.test(appId)) throw new Error("AppID de Steam inválido")
        var group = library.groups.some(function(g) { return g.id === "main" }) ? "main" : library.groups[0].id
        item = {
            id: makeId(library, source.id), name: source.name, tileLabel: source.name,
            type: "game", groupId: group, size: {columns: 1, rows: 1}, description: "",
            launch: appId ? {type: "steam", appId: appId} : {type: "none"},
            metadata: {}, artwork: {tile: null}
        }
    } else {
        var targetId = String(opts.targetId || "")
        for (var i = 0; i < library.items.length; ++i)
            if (library.items[i].id === targetId) { index = i; break }
        if (index < 0) throw new Error("El elemento de destino ya no existe")
        item = copy(library.items[index])
        if (item.type === "folder") throw new Error("No se pueden importar juegos sobre carpetas")
        if (sameSource && sameSource.id !== item.id)
            throw new Error("Esta ficha RAWG ya pertenece a «" + sameSource.name + "».")
        var old = item.metadata || {}
        if (old.provider && old.providerId !== null && old.providerId !== undefined &&
            !sourceMatch(item, source.id) && opts.allowRelink !== true)
            throw new Error("El destino ya está asociado a otra ficha. Confirma expresamente el cambio de asociación.")
    }
    if (isNew || chosen.indexOf("name") >= 0) item.name = source.name
    if (chosen.indexOf("description") >= 0) item.description = game.description.slice(0, 12000)
    var metadata = item.metadata || {}
    if (chosen.indexOf("releaseDate") >= 0) metadata.releaseDate = game.released;
    ["developers", "publishers", "genres"].forEach(function(key) {
        if (chosen.indexOf(key) >= 0) metadata[key] = cleanList(game[key])
    })
    if (chosen.indexOf("rating") >= 0) metadata.rating = game.rating
    if (chosen.indexOf("metacritic") >= 0) metadata.metacritic = game.metacritic
    metadata.provider = "rawg"
    metadata.providerId = Number(source.id)
    item.metadata = metadata
    // No se toca el lanzamiento, ID, tamaño, grupo, etiqueta ni artwork de un destino existente.
    if (isNew) library.items.push(item)
    else library.items[index] = item
    var result = TileModel.normalizeLibrary(library)
    return {library: result, itemId: item.id, created: isNew, fields: chosen}
}
