// Azuki Tile Deck — referencias locales de artwork y cambios inmutables.
.pragma library
.import "TileModel.js" as TileModel

function localSource(value) {
    if (typeof value !== "string" || !value || value.length > 8192) return ""
    // Nunca se cargan URLs remotas ni rutas relativas desde la biblioteca.
    if (/^file:\/\/\/(?!\/)/.test(value) && !/[\r\n\0]/.test(value))
        return value
    return ""
}

function legacyPreview(item) {
    var art = item && item.artwork ? item.artwork : {}
    return !!item && item.id === "miniMetro" && !art.tile && art.disabled !== true
}

function sourceForItem(item, previewUrl) {
    if (!item) return ""
    var art = item.artwork || {}
    if (art.disabled === true) return ""
    var chosen = localSource(art.tile)
    if (chosen) return chosen
    return legacyPreview(item) ? String(previewUrl || "") : ""
}

function changeArtwork(library, id, source) {
    var current = TileModel.findItem(library.items, id)
    if (!current) throw new Error("El elemento ya no existe")
    if (source !== null && !localSource(source))
        throw new Error("Selecciona una imagen local válida")
    var next = TileModel.deepCopy(current)
    next.artwork = Object.assign({}, next.artwork || {}, {
        tile: source,
        // Desactiva el fallback de la prueba cuando el usuario decide quitarlo.
        disabled: source === null
    })
    return TileModel.replaceItem(library, next)
}
