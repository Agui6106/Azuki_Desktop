// Azuki Tile Deck — modelo de datos v1.
// Biblioteca funcional: sin estado global mutable, red ni acceso al sistema.
.pragma library

var SCHEMA_VERSION = 1
var MAX_ITEMS = 256
var ALLOWED_TYPES = ["game", "application", "folder"]
var ALLOWED_SIZES = ["1x1", "2x1", "2x2"]

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function stringValue(value, fallback) {
    return typeof value === "string" ? value : (fallback || "")
}

function stringList(value) {
    if (!Array.isArray(value)) return []
    return value.filter(function(v) { return typeof v === "string" && v.trim() !== "" })
}

function numberOrNull(value) {
    return typeof value === "number" && isFinite(value) ? value : null
}

function cleanTitle(value) {
    return stringValue(value, "").replace(/\s+/g, " ").trim()
}

function normalizeLaunch(value, legacyCommand) {
    var launch = isObject(value) ? value : {}
    var type = stringValue(launch.type, "")
    if (type === "none") return {type: "none"}
    if (type === "steam") {
        var appId = String(launch.appId === undefined ? "" : launch.appId)
        if (!/^[0-9]{1,20}$/.test(appId)) throw new Error("AppID de Steam inválido")
        return {type: "steam", appId: appId}
    }
    if (type === "url") {
        var url = stringValue(launch.url, "").trim()
        if (!/^https?:\/\/[^\s]+$/i.test(url)) throw new Error("URL no válida")
        return {type: "url", url: url}
    }
    if (type === "executable") {
        return {type: "executable", command: stringValue(launch.command, "")}
    }
    // Compatibilidad con los comandos de la versión 0.4.
    if (type === "" && typeof legacyCommand === "string") {
        if (/^steam:\/\/rungameid\/[0-9]+$/.test(legacyCommand)) {
            return {type: "steam", appId: legacyCommand.split("/").pop()}
        }
        if (/^https?:\/\//i.test(legacyCommand)) {
            return normalizeLaunch({type: "url", url: legacyCommand})
        }
        return {type: "executable", command: legacyCommand}
    }
    if (type === "") return {type: "none"}
    throw new Error("Tipo de lanzamiento desconocido: " + type)
}

function normalizeItem(item) {
    if (!isObject(item)) throw new Error("Elemento inválido")
    var id = stringValue(item.id, "").trim()
    if (!id) throw new Error("Un elemento no tiene ID")
    var name = cleanTitle(item.name || item.title || item.tileLabel)
    if (!name) throw new Error("El elemento " + id + " no tiene nombre")
    var type = stringValue(item.type, "application")
    if (ALLOWED_TYPES.indexOf(type) < 0) throw new Error("Tipo de elemento inválido: " + type)
    var size = isObject(item.size) ? item.size : {columns: item.columns || 1, rows: item.rows || 1}
    var columns = Number(size.columns), rows = Number(size.rows)
    if (ALLOWED_SIZES.indexOf(columns + "x" + rows) < 0) throw new Error("Tamaño de tile inválido: " + id)
    var metadata = isObject(item.metadata) ? item.metadata : {}
    var artwork = isObject(item.artwork) ? item.artwork : {}
    var releaseDate = stringValue(metadata.releaseDate, "") || null
    if (!releaseDate && item.releaseYear) releaseDate = String(item.releaseYear)
    return {
        id: id, name: name,
        tileLabel: stringValue(item.tileLabel, stringValue(item.title, name)),
        type: type, groupId: stringValue(item.groupId, "main"),
        size: {columns: columns, rows: rows},
        description: stringValue(item.description, ""),
        launch: type === "folder" ? {type: "none"} : normalizeLaunch(item.launch, item.command),
        metadata: Object.assign({}, metadata, {
            provider: stringValue(metadata.provider, "") || null,
            providerId: metadata.providerId === undefined ? null : metadata.providerId,
            releaseDate: releaseDate,
            developers: stringList(metadata.developers || (item.developer ? [item.developer] : [])),
            publishers: stringList(metadata.publishers),
            genres: stringList(metadata.genres || (item.genre ? [item.genre] : [])),
            rating: numberOrNull(metadata.rating),
            metacritic: numberOrNull(metadata.metacritic)
        }),
        artwork: Object.assign({}, artwork, {tile: stringValue(artwork.tile, "") || null})
    }
}

function normalizeLibrary(value) {
    if (!isObject(value) || value.schemaVersion !== SCHEMA_VERSION) {
        throw new Error("Esquema de biblioteca no compatible")
    }
    if (!Array.isArray(value.items) || value.items.length > MAX_ITEMS) {
        throw new Error("La biblioteca debe contener entre 0 y " + MAX_ITEMS + " elementos")
    }
    var groups = Array.isArray(value.groups) ? value.groups : []
    if (!groups.length) groups = [{id: "main", name: "Inicio"}]
    var resultGroups = [], groupIds = Object.create(null)
    groups.forEach(function(group) {
        if (!isObject(group) || !stringValue(group.id, "").trim()) throw new Error("Grupo inválido")
        if (groupIds[group.id]) throw new Error("ID de grupo duplicado: " + group.id)
        groupIds[group.id] = true
        resultGroups.push({id: group.id, name: cleanTitle(group.name || group.id)})
    })
    var ids = Object.create(null), items = value.items.map(function(raw) {
        var item = normalizeItem(raw)
        if (ids[item.id]) throw new Error("ID de elemento duplicado: " + item.id)
        if (!groupIds[item.groupId]) throw new Error("Grupo inexistente: " + item.groupId)
        ids[item.id] = true
        return item
    })
    return {schemaVersion: SCHEMA_VERSION, groups: resultGroups, items: items}
}

function parseLibrary(json) {
    return normalizeLibrary(JSON.parse(json))
}

function findItem(items, id) {
    if (!Array.isArray(items) || !id) return null
    for (var i = 0; i < items.length; ++i) {
        if (items[i].id === id) return items[i]
    }
    return null
}

function metadataText(item) {
    if (!item) return ""
    var m = item.metadata || {}, parts = []
    if (m.releaseDate) parts.push(String(m.releaseDate).substring(0, 4))
    if (m.developers && m.developers.length) parts.push(m.developers.join(", "))
    if (m.genres && m.genres.length) parts.push(m.genres.join(", "))
    return parts.join("  ·  ")
}

function actionLabel(item) {
    if (!item) return "ABRIR"
    return item.type === "game" ? "JUGAR" : item.type === "folder" ? "VER" : "ABRIR"
}

function actionIcon(item) {
    if (!item) return "system-run"
    return item.type === "game" ? "media-playback-start" : item.type === "folder" ? "folder-open" : "window-new"
}

function launchTarget(item) {
    if (!item || item.type === "folder") return null
    var launch = item.launch || {type: "none"}
    if (launch.type === "steam") {
        if (!/^[0-9]{1,20}$/.test(String(launch.appId))) return null
        return {type: "url", value: "steam://rungameid/" + launch.appId}
    }
    if (launch.type === "url" && /^https?:\/\/[^\s]+$/i.test(launch.url || "")) {
        return {type: "url", value: launch.url}
    }
    if (launch.type === "executable" && typeof launch.command === "string" && launch.command.trim()) {
        return {type: "executable", value: launch.command}
    }
    return null
}

function canLaunch(item) { return launchTarget(item) !== null }

// Empaquetado provisional: 2 filas, bloques horizontales de 4 columnas.
// Primer hueco disponible; los tiles 2x2 no cruzan el límite de un bloque.
// Se reemplazará por páginas/grupos en una fase posterior.
function packItems(items, unitWidth, unitHeight, gap, pageColumns, rowCount) {
    var cols = pageColumns || 4, rows = rowCount || 2
    if (cols < 2 || rows < 2) throw new Error("Cuadrícula inválida")
    var occupied = {}, placed = [], pages = 0
    items.forEach(function(item) {
        var w = item.size.columns, h = item.size.rows, found = null
        if (w > cols || h > rows) throw new Error("Tile demasiado grande")
        for (var page = 0; page <= items.length && !found; ++page) {
            for (var row = 0; row <= rows - h && !found; ++row) {
                for (var col = 0; col <= cols - w && !found; ++col) {
                    var absoluteCol = page * cols + col, free = true
                    for (var dy = 0; dy < h; ++dy) {
                        for (var dx = 0; dx < w; ++dx) {
                            if (occupied[(absoluteCol + dx) + ":" + (row + dy)]) free = false
                        }
                    }
                    if (free) found = {column: absoluteCol, row: row, page: page}
                }
            }
        }
        if (!found) throw new Error("No se pudo posicionar el elemento " + item.id)
        for (var y = 0; y < h; ++y) {
            for (var x = 0; x < w; ++x) occupied[(found.column + x) + ":" + (found.row + y)] = true
        }
        pages = Math.max(pages, found.page + 1)
        placed.push({item: item, column: found.column, row: found.row,
                     x: found.column * (unitWidth + gap), y: found.row * (unitHeight + gap)})
    })
    var totalColumns = pages * cols
    return {items: placed, pages: pages,
            width: totalColumns ? totalColumns * unitWidth + (totalColumns - 1) * gap : 0,
            height: rows * unitHeight + (rows - 1) * gap}
}
// -----------------------------------------------------------------------------
// v0.5c: operaciones inmutables y formulario para el editor de Preferencias.
// El ID y los datos del proveedor no se regeneran al modificar un elemento.
// -----------------------------------------------------------------------------
function deepCopy(value) {
    return JSON.parse(JSON.stringify(value))
}

function createItem(id) {
    return normalizeItem({
        id: id,
        name: "Nueva aplicación",
        tileLabel: "Nueva aplicación",
        type: "application",
        groupId: "main",
        size: {columns: 1, rows: 1},
        description: "",
        launch: {type: "none"},
        metadata: {},
        artwork: {tile: null}
    })
}

function insertItem(library, item) {
    var next = deepCopy(library)
    next.items.push(item)
    return normalizeLibrary(next)
}

function replaceItem(library, item) {
    var next = deepCopy(library)
    var found = -1
    for (var i = 0; i < next.items.length; ++i) {
        if (next.items[i].id === item.id) { found = i; break }
    }
    if (found < 0) throw new Error("El elemento ya no existe")
    next.items[found] = item
    return normalizeLibrary(next)
}

function removeItem(library, id) {
    var next = deepCopy(library)
    var index = -1
    for (var i = 0; i < next.items.length; ++i) {
        if (next.items[i].id === id) { index = i; break }
    }
    if (index < 0) throw new Error("El elemento ya no existe")
    next.items.splice(index, 1)
    return normalizeLibrary(next)
}

function moveItem(library, id, offset) {
    var next = deepCopy(library)
    var index = -1
    for (var i = 0; i < next.items.length; ++i) {
        if (next.items[i].id === id) { index = i; break }
    }
    if (index < 0) throw new Error("El elemento ya no existe")
    var destination = index + offset
    if (destination < 0 || destination >= next.items.length) return normalizeLibrary(next)
    next.items.splice(destination, 0, next.items.splice(index, 1)[0])
    return normalizeLibrary(next)
}

function formFromItem(item) {
    var m = item.metadata || {}, l = item.launch || {type: "none"}
    return {
        name: item.name,
        tileLabel: item.tileLabel,
        type: item.type,
        size: item.size.columns + "x" + item.size.rows,
        description: item.description,
        launchType: l.type,
        appId: l.appId || "",
        command: l.command || "",
        url: l.url || "",
        releaseDate: m.releaseDate || "",
        developers: (m.developers || []).join(", "),
        publishers: (m.publishers || []).join(", "),
        genres: (m.genres || []).join(", ")
    }
}

function commaList(value) {
    return value.split(",").map(function(s) { return s.trim() })
        .filter(function(s) { return s.length > 0 })
}

function itemFromForm(original, form) {
    if (!original || !isObject(form)) throw new Error("Formulario inválido")
    var next = deepCopy(original)
    var name = cleanTitle(form.name)
    if (!name) throw new Error("Escribe un nombre para el elemento")
    if (name.length > 200) throw new Error("El nombre es demasiado largo")
    next.name = name
    next.tileLabel = form.tileLabel.trim() || name
    if (next.tileLabel.length > 300) throw new Error("La etiqueta es demasiado larga")
    if (form.type !== "game" && form.type !== "application" && form.type !== "folder")
        throw new Error("Tipo de elemento no válido")
    // Las carpetas existentes se conservan; su navegación se implementará en v0.9.
    if (form.type === "folder" && original.type !== "folder")
        throw new Error("Las carpetas estarán disponibles en v0.9")
    next.type = form.type
    if (ALLOWED_SIZES.indexOf(form.size) < 0) throw new Error("Selecciona un tamaño válido")
    var dimensions = form.size.split("x")
    next.size = {columns: Number(dimensions[0]), rows: Number(dimensions[1])}
    next.description = form.description
    next.metadata = deepCopy(original.metadata || {})
    var date = form.releaseDate.trim()
    if (date && !/^\d{4}(-\d{2}-\d{2})?$/.test(date))
        throw new Error("Usa AAAA o AAAA-MM-DD para la fecha")
    if (date.length === 10) {
        var d = new Date(date + "T00:00:00Z")
        if (isNaN(d.getTime()) || d.toISOString().substring(0, 10) !== date)
            throw new Error("La fecha no existe")
    }
    next.metadata.releaseDate = date || null
    next.metadata.developers = commaList(form.developers)
    next.metadata.publishers = commaList(form.publishers)
    next.metadata.genres = commaList(form.genres)
    if (next.type === "folder") {
        next.launch = {type: "none"}
    } else if (form.launchType === "none") {
        next.launch = {type: "none"}
    } else if (form.launchType === "steam") {
        var appId = form.appId.trim()
        if (!/^[0-9]{1,20}$/.test(appId)) throw new Error("Escribe un AppID de Steam válido")
        next.launch = {type: "steam", appId: appId}
    } else if (form.launchType === "executable") {
        var command = form.command.trim()
        if (!command || /[\r\n\0]/.test(command))
            throw new Error("Escribe un comando local válido en una sola línea")
        next.launch = {type: "executable", command: command}
    } else if (form.launchType === "url") {
        var url = form.url.trim()
        if (!/^https?:\/\/[^\s]+$/i.test(url)) throw new Error("Escribe una URL http o https válida")
        next.launch = {type: "url", url: url}
    } else {
        throw new Error("Tipo de lanzamiento desconocido")
    }
    return normalizeItem(next)
}

function formError(original, form) {
    try {
        itemFromForm(original, form)
        return ""
    } catch (e) {
        return String(e.message || e)
    }
}
