import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "RawgImport.js" as RawgImport

Controls.Dialog {
    id: dialog
    property var game: null
    property var libraryData: ({schemaVersion: 1, groups: [], items: []})
    property string mode: "new"
    property string targetId: ""
    property string steamAppId: ""
    property bool allowRelink: false
    property var fields: ({})
    property string errorMessage: ""
    signal importRequested(var options)

    title: "Importar información de RAWG"
    modal: true
    standardButtons: Controls.Dialog.NoButton
    width: Math.min(680, Math.max(280, parent.width - 24))
    height: Math.min(650, Math.max(280, parent.height - 24))
    anchors.centerIn: parent

    readonly property var targets: libraryData.items.filter(function(item) { return item.type !== "folder" })
    readonly property var targetItem: targets.filter(function(item) { return item.id === targetId })[0] || null
    readonly property var oldSource: targetItem ? targetItem.metadata || {} : ({})
    readonly property bool differentSource: mode === "existing" && targetItem !== null &&
        !!oldSource.provider && oldSource.providerId !== null && oldSource.providerId !== undefined &&
        !(oldSource.provider === "rawg" && String(oldSource.providerId) === String(game ? game.id : ""))
    readonly property var fieldOptions: [
        {id: "name", label: "Nombre completo", value: game ? game.name : ""},
        {id: "description", label: "Descripción", value: game ? (game.description || "").length + " caracteres" : ""},
        {id: "releaseDate", label: "Fecha de lanzamiento", value: game ? game.released || "" : ""},
        {id: "developers", label: "Desarrolladores", value: game ? game.developers.join(", ") : ""},
        {id: "publishers", label: "Publishers", value: game ? game.publishers.join(", ") : ""},
        {id: "genres", label: "Géneros", value: game ? game.genres.join(", ") : ""},
        {id: "rating", label: "Puntuación RAWG", value: game && game.rating !== null ? game.rating + "/5" : ""},
        {id: "metacritic", label: "Metacritic", value: game && game.metacritic !== null ? game.metacritic + "/100" : ""}
    ]

    function prepare(source, library) {
        game = JSON.parse(JSON.stringify(source))
        libraryData = JSON.parse(JSON.stringify(library))
        var previous = RawgImport.findSource(library, source.id)
        mode = previous ? "existing" : "new"
        targetId = previous ? previous.id : (targets.length ? targets[0].id : "")
        steamAppId = ""
        allowRelink = false
        fields = RawgImport.defaultFields(game, mode === "new")
        errorMessage = ""
        open()
    }
    function setMode(value) {
        mode = value
        fields = RawgImport.defaultFields(game, mode === "new")
        allowRelink = false
        errorMessage = ""
    }
    function setField(key, value) {
        var next = Object.assign({}, fields)
        next[key] = value
        fields = next
        errorMessage = ""
    }
    function submit() {
        errorMessage = ""
        importRequested({
            mode: mode, targetId: targetId, steamAppId: steamAppId,
            allowRelink: allowRelink, fields: Object.assign({}, fields)
        })
    }

    contentItem: Controls.ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth
        contentHeight: body.implicitHeight
        ColumnLayout {
            id: body
            width: scroll.availableWidth
            spacing: 10
            Controls.Label {
                textFormat: Text.PlainText
                text: dialog.game ? dialog.game.name + " · RAWG #" + dialog.game.id : ""
                font.family: "Oxanium"
                font.pixelSize: 18
                font.bold: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Controls.Label {
                textFormat: Text.PlainText
                text: "Solo se importarán los campos marcados. Los datos no disponibles nunca borrarán información existente."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Controls.Label {
                textFormat: Text.PlainText
                visible: dialog.errorMessage !== ""
                text: dialog.errorMessage
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Controls.Label {
                textFormat: Text.PlainText
                text: "Destino"
                font.bold: true
            }
            Controls.RadioButton {
                text: "Crear un juego nuevo"
                checked: dialog.mode === "new"
                onClicked: dialog.setMode("new")
            }
            Controls.RadioButton {
                text: "Completar un elemento existente"
                enabled: dialog.targets.length > 0
                checked: dialog.mode === "existing"
                onClicked: dialog.setMode("existing")
            }
            Controls.ComboBox {
                Layout.fillWidth: true
                visible: dialog.mode === "existing"
                enabled: dialog.targets.length > 0
                model: dialog.targets
                textRole: "name"
                currentIndex: Math.max(0, dialog.targets.findIndex(function(item) { return item.id === dialog.targetId }))
                onActivated: function(index) {
                    dialog.targetId = dialog.targets[index].id
                    dialog.allowRelink = false
                    dialog.errorMessage = ""
                }
            }
            Controls.Label {
                textFormat: Text.PlainText
                visible: dialog.mode === "existing"
                text: dialog.targetItem ? "Se conservarán su ID, etiqueta, tamaño, grupo, tipo y comando de lanzamiento." : "Selecciona un elemento."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                color: Kirigami.Theme.neutralTextColor
            }
            Controls.CheckBox {
                visible: dialog.differentSource
                text: "Confirmar cambio de ficha RAWG"
                checked: dialog.allowRelink
                onToggled: dialog.allowRelink = checked
            }
            Controls.Label {
                textFormat: Text.PlainText
                visible: dialog.differentSource
                text: "Este elemento ya está asociado a otra ficha. Confirma el cambio solo si estás seguro de que elegiste el juego correcto."
                color: Kirigami.Theme.neutralTextColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
            Controls.Label {
                textFormat: Text.PlainText
                visible: dialog.mode === "new"
                text: "AppID de Steam (opcional)"
            }
            Controls.TextField {
                visible: dialog.mode === "new"
                Layout.fillWidth: true
                placeholderText: "Ej. 287980 — déjalo vacío para configurar después"
                text: dialog.steamAppId
                inputMethodHints: Qt.ImhDigitsOnly
                onTextEdited: dialog.steamAppId = text
            }
            Controls.Label {
                textFormat: Text.PlainText
                visible: dialog.mode === "new"
                text: "RAWG no proporciona el AppID instalado en tu PC. Escribe el ID de Steam que hayas verificado; no se ejecutará ningún juego al importar."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                opacity: 0.75
            }
            Controls.Label {
                textFormat: Text.PlainText
                text: "Campos que se importarán"
                font.bold: true
                Layout.topMargin: 6
            }
            Repeater {
                model: dialog.fieldOptions
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 1
                    readonly property bool available: RawgImport.available(dialog.game)[modelData.id] === true
                    Controls.CheckBox {
                        Layout.fillWidth: true
                        text: modelData.label
                        enabled: parent.available && !(dialog.mode === "new" && modelData.id === "name")
                        checked: dialog.mode === "new" && modelData.id === "name" ? true : dialog.fields[modelData.id] === true
                        onToggled: dialog.setField(modelData.id, checked)
                    }
                    Controls.Label {
                textFormat: Text.PlainText
                        Layout.fillWidth: true
                        text: parent.available ? modelData.value : "No disponible en RAWG"
                        opacity: 0.65
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.leftMargin: 28
                    }
                }
            }
            Controls.Label {
                textFormat: Text.PlainText
                text: "Datos proporcionados por RAWG · https://rawg.io"
                font.pixelSize: 12
                opacity: 0.75
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }
    footer: Controls.DialogButtonBox {
        Controls.Button {
            text: "Cancelar"
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.RejectRole
            onClicked: dialog.close()
        }
        Controls.Button {
            text: "Preparar importación"
            icon.name: "document-import"
            enabled: dialog.game !== null && (dialog.mode === "new" || dialog.targetItem !== null)
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.ActionRole
            onClicked: dialog.submit()
        }
    }
}
