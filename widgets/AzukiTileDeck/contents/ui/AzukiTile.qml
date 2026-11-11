import QtQuick

Rectangle {
    id: tile

    // =========================
    // DATOS DEL TILE
    // =========================

    property var itemData: null
    property url artworkSource: ""
    property string title: ""
    property string subtitle: ""

    // Tamaño lógico dentro del Tile Deck
    property int columns: 1
    property int rows: 1

    // Medidas proporcionadas por main.qml
    property int unitWidth: 156
    property int unitHeight: 136
    property int tileSpacing: 16

    // Preparado para siguientes versiones
    property bool selected: false
    property string itemType: "application"

    // Reactivity properties
    property string tileId: ""
    property string description: ""

    // Exec commands
    property string command: ""

    property string releaseYear: ""
    property string developer: ""
    property string genre: ""

    readonly property bool hovered: hoverHandler.hovered

    signal selectionRequested(var itemData)

    // =========================
    // DIMENSIONES
    // =========================

    width:
        columns * unitWidth
        + (columns - 1) * tileSpacing

    height:
        rows * unitHeight
        + (rows - 1) * tileSpacing

    // =========================
    // APARIENCIA
    // =========================

    radius: 16

    color: "#CC24282D"

    border.width:
    selected ? 2 : 1

    border.color:
        selected
        ? "#21CFE0"
        : hovered
            ? "#9921CFE0"
            : "#444F5963"

    scale:
        selected
        ? 1.05
        : hovered
            ? 1.025
            : 1.0

    z:
        selected || hovered ? 10 : 0

    Behavior on scale {
        NumberAnimation {
            duration: 150
            easing.type: Easing.OutCubic
        }
    }

    Behavior on border.color {
        ColorAnimation {
            duration: 120
        }
    }


    // Artwork local opcional; no cambia el modelo ni la selección.
    Loader {
        anchors.fill: parent
        active: tile.artworkSource.toString() !== ""
        sourceComponent: Component {
            AzukiArtwork {
                source: tile.artworkSource
                cornerRadius: tile.radius
            }
        }
    }

    // El borde se mantiene por encima del artwork.
    Rectangle {
        anchors.fill: parent
        radius: tile.radius
        color: "transparent"
        border.width: tile.border.width
        border.color: tile.border.color
        visible: tile.artworkSource.toString() !== ""
        z: 2
    }

    // =========================
    // TEXTO
    // =========================

    Column {
        anchors.centerIn: parent

        width: parent.width - 24

        spacing: 4

        Text {
            width: parent.width

            text: tile.title

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            wrapMode: Text.WordWrap

            color: "#F2F2F2"

            font.family: "Oxanium"
            font.pixelSize:
                tile.columns >= 2 ? 20 : 17
            font.weight: Font.Medium
        }

        Text {
            width: parent.width

            visible: tile.subtitle !== ""

            text: tile.subtitle

            horizontalAlignment: Text.AlignHCenter

            wrapMode: Text.WordWrap

            color: "#AFC0C5C8"

            font.family: "Exo 2"
            font.pixelSize: 12
        }
    }

    // handlers
    HoverHandler {
        id: hoverHandler
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        onTapped: {
            tile.selectionRequested(tile.itemData !== null ? tile.itemData : {
                id: tile.tileId,
                title: tile.title,
                description: tile.description,
                type: tile.itemType,
                command: tile.command,
                releaseYear: tile.releaseYear,
                developer: tile.developer,
                genre: tile.genre
            })
        }
    }


}
