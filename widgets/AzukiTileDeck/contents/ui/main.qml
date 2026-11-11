import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import "TileModel.js" as TileModel
import "TileDefaults.js" as TileDefaults

PlasmoidItem {
    id: root

    CoordinationWindow {
        instanceId: String(Plasmoid.id)
        configuring: Plasmoid.userConfiguring
    }

    // El tamaño lo conserva Plasma; estas son referencias de diseño.
    readonly property int designWidth: 1392
    readonly property int designHeight: 464
    readonly property int tileUnitWidth: 156
    readonly property int tileUnitHeight: 136
    readonly property int tileSpacing: 16

    property var libraryData: ({schemaVersion: 1, groups: [], items: []})
    property string selectedTileId: ""
    readonly property var selectedItem: TileModel.findItem(libraryData.items, selectedTileId)
    property string libraryError: ""

    function loadLibrary() {
        var json = Plasmoid.configuration.libraryJson
        if (typeof json !== "string" || json.trim() === "") {
            // Copia inicial incluida en el paquete. No hay lecturas HTTP ni escrituras.
            json = TileDefaults.json
        }
        return TileModel.parseLibrary(json)
    }

    function reloadLibrary() {
        try {
            var updated = loadLibrary()
            libraryData = updated
            if (selectedTileId !== "" && !TileModel.findItem(updated.items, selectedTileId))
                selectedTileId = ""
            libraryError = ""
        } catch (e) {
            // Una configuración dañada nunca destruye la biblioteca en memoria.
            libraryError = String(e)
            console.warn("Azuki Tile Deck: no se pudo cargar la biblioteca:", e)
        }
    }

    function selectTile(itemData) {
        if (itemData && TileModel.findItem(libraryData.items, itemData.id))
            selectedTileId = itemData.id
    }

    // Se mantiene el motor que ya funciona para aplicaciones locales.
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
        }
    }

    function launchSelected() {
        var target = TileModel.launchTarget(selectedItem)
        if (!target) return
        if (target.type === "url") {
            var success = Qt.openUrlExternally(target.value)
            if (!success)
                console.warn("Azuki Tile Deck: no se pudo entregar la URL:", target.value)
            return
        }
        if (target.type === "executable")
            executable.connectSource(target.value)
    }

    Component.onCompleted: reloadLibrary()

    Connections {
        target: Plasmoid.configuration
        function onLibraryJsonChanged() { root.reloadLibrary() }
    }

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    fullRepresentation: Rectangle {
        id: deck

        color: "#331A1D21"

        radius: 24

        border.width: 1
        border.color: "#5521CFE0"

        implicitWidth: 850
        implicitHeight: 430

        // =========================
        // CABECERA
        // =========================

        Text {
            id: title

            anchors {
                top: parent.top
                left: parent.left

                topMargin: 20
                leftMargin: 24
            }

            text: "AZUKI"

            color: "#F2F2F2"

            font.family: "Oxanium"
            font.pixelSize: 20
            font.weight: Font.Medium
        }

        Text {
            anchors {
                baseline: title.baseline
                left: title.right

                leftMargin: 8
            }

            text: "TILE DECK"

            color: "#21CFE0"

            font.family: "Oxanium"
            font.pixelSize: 20
            font.weight: Font.Medium
        }


        // =========================
        // ÁREA DE TILES
        // =========================

        // Solo aparece si la configuración no puede cargarse.
        Text {
            visible: root.libraryError !== ""
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 20
            anchors.rightMargin: 24
            width: Math.max(0, parent.width * 0.55)
            text: "Biblioteca inválida · se conservó la versión anterior"
            color: "#FFB86C"
            font.family: "Exo 2"
            font.pixelSize: 12
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }

        TileGrid {
            id: tileArea
            anchors {
                top: title.bottom
                left: parent.left
                right: parent.right
                bottom: infoArea.top
                topMargin: 18
                leftMargin: 24
                rightMargin: 24
                bottomMargin: 12
            }
            items: root.libraryData.items
            selectedTileId: root.selectedTileId
            unitWidth: root.tileUnitWidth
            unitHeight: root.tileUnitHeight
            tileSpacing: root.tileSpacing
            onSelectionRequested: function(itemData) {
                root.selectTile(itemData)
            }
        }

        // Barra original, sin cambios de tamaño ni tipografía.
        InfoBar {
            id: infoArea
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: 24
                rightMargin: 24
                bottomMargin: 16
            }
            height: 78
            hasSelection: root.selectedItem !== null
            title: root.selectedItem ? root.selectedItem.name : ""
            description: root.selectedItem ? root.selectedItem.description : ""
            metadata: TileModel.metadataText(root.selectedItem)
            actionLabel: TileModel.actionLabel(root.selectedItem)
            actionIconName: TileModel.actionIcon(root.selectedItem)
            actionEnabled: TileModel.canLaunch(root.selectedItem)
            onActionRequested: root.launchSelected()
        }
    }
}
