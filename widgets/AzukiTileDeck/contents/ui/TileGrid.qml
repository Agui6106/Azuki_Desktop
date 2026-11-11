import QtQuick
import QtCore
import QtQuick.Controls as Controls
import "TileModel.js" as TileModel
import "ArtworkModel.js" as ArtworkModel

Item {
    id: grid
    property var items: []
    property string selectedTileId: ""
    property int unitWidth: 156
    property int unitHeight: 136
    property int tileSpacing: 16
    property int pageColumns: 4
    property int rowCount: 2
    // Ruta temporal para la prueba. La configuración de artwork vendrá después.
    readonly property string previewArtworkSource:
        StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
        + "/azuki-tile-deck/artwork/mini-metro-preview.jpg"

    signal selectionRequested(var itemData)

    readonly property var placement: TileModel.packItems(
        items, unitWidth, unitHeight, tileSpacing, pageColumns, rowCount)

    Flickable {
        id: viewport
        anchors.fill: parent
        readonly property bool overflowing: placement.width > width
        contentWidth: Math.max(width, placement.width + (overflowing ? 16 : 0))
        contentHeight: placement.height
        flickableDirection: Flickable.HorizontalFlick
        interactive: overflowing
        boundsBehavior: Flickable.StopAtBounds
        clip: overflowing

        Item {
            width: placement.width
            height: placement.height
            x: viewport.overflowing ? 8 : 0

            Repeater {
                model: grid.placement.items
                delegate: AzukiTile {
                    // Los datos son la fuente de verdad, no el delegado.
                    itemData: modelData.item
                    artworkSource: ArtworkModel.sourceForItem(modelData.item, grid.previewArtworkSource)
                    tileId: modelData.item.id
                    title: modelData.item.tileLabel
                    description: modelData.item.description
                    itemType: modelData.item.type
                    columns: modelData.item.size.columns
                    rows: modelData.item.size.rows
                    unitWidth: grid.unitWidth
                    unitHeight: grid.unitHeight
                    tileSpacing: grid.tileSpacing
                    x: modelData.x
                    y: modelData.y
                    selected: grid.selectedTileId === tileId
                    onSelectionRequested: function(data) {
                        grid.selectionRequested(data)
                    }
                }
            }
        }

        Controls.ScrollBar.horizontal: Controls.ScrollBar {
            policy: viewport.overflowing
                    ? Controls.ScrollBar.AsNeeded
                    : Controls.ScrollBar.AlwaysOff
        }

        WheelHandler {
            target: null
            onWheel: function(event) {
                if (!viewport.overflowing) {
                    event.accepted = false
                    return
                }
                var delta = event.pixelDelta.x !== 0 ? event.pixelDelta.x
                          : event.pixelDelta.y !== 0 ? event.pixelDelta.y
                          : event.angleDelta.x !== 0 ? event.angleDelta.x / 2
                          : event.angleDelta.y / 2
                viewport.contentX = Math.max(0, Math.min(
                    viewport.contentWidth - viewport.width,
                    viewport.contentX - delta))
                event.accepted = true
            }
        }
    }
}
