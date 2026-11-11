import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support

Controls.Dialog {
    id: dialog

    property string targetId: ""
    property string itemName: ""
    property string appId: ""
    property var candidates: []
    property int selectedIndex: -1
    readonly property var selectedCandidate: selectedIndex >= 0 && selectedIndex < candidates.length
                                              ? candidates[selectedIndex] : null
    property bool busy: false
    property bool statusError: false
    property string statusText: ""
    property string pendingCommand: ""
    property string pendingRequestId: ""
    property int requestCounter: 0

    signal sourceChosen(string itemId, string source)

    title: "Artwork local de Steam"
    modal: true
    standardButtons: Controls.Dialog.NoButton
    width: Math.min(760, Math.max(280, parent.width - 24))
    height: Math.min(680, Math.max(280, parent.height - 24))
    anchors.centerIn: parent

    function shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\"'\"'") + "'"
    }

    function scriptPath() {
        var url = Qt.resolvedUrl("../scripts/steam_artwork.py").toString()
        if (url.indexOf("file:///") !== 0) return ""
        return decodeURIComponent(url.substring(7))
    }

    function openForItem(item) {
        if (!item || !item.launch || item.launch.type !== "steam") return
        var id = String(item.launch.appId || "")
        if (!/^[0-9]{1,20}$/.test(id)) return
        if (pendingCommand !== "") executable.disconnectSource(pendingCommand)
        pendingCommand = ""
        busy = false
        targetId = item.id
        itemName = item.name
        appId = id
        candidates = []
        selectedIndex = -1
        statusError = false
        statusText = "Buscando imágenes de Steam…"
        open()
        beginScan()
    }

    function beginScan() {
        if (busy || !/^[0-9]{1,20}$/.test(appId)) return
        var script = scriptPath()
        if (!script) {
            statusError = true
            statusText = "No se encontró el detector local de Steam."
            return
        }
        requestCounter++
        pendingRequestId = String(requestCounter)
        pendingCommand = "/usr/bin/python3 " + shellQuote(script)
                       + " --app-id " + appId + " --request-id " + pendingRequestId
        busy = true
        statusError = false
        statusText = "Buscando imágenes de Steam…"
        candidates = []
        selectedIndex = -1
        executable.connectSource(pendingCommand)
    }

    function finish(sourceName, data) {
        executable.disconnectSource(sourceName)
        if (sourceName !== pendingCommand) return
        var requestId = pendingRequestId
        pendingCommand = ""
        pendingRequestId = ""
        busy = false
        var payload
        try {
            payload = JSON.parse(data["stdout"] || "")
        } catch (e) {
            statusError = true
            statusText = "El detector no devolvió JSON válido."
            return
        }
        if (String(payload.requestId) !== requestId) return
        if (Number(data["exit code"]) !== 0 || payload.ok !== true) {
            statusError = true
            statusText = payload.message || "No se pudo consultar la caché local."
            return
        }
        var result = payload.data || {}
        if (String(result.appId) !== appId || !Array.isArray(result.images)) {
            statusError = true
            statusText = "El detector devolvió una respuesta incompatible."
            return
        }
        candidates = result.images.slice(0, 12)
        selectedIndex = candidates.length ? 0 : -1
        statusError = false
        statusText = candidates.length
            ? candidates.length + " variante(s) disponible(s). Elige una y pulsa Usar esta imagen."
            : "Steam no tiene artwork compatible de este juego en las carpetas revisadas. Puedes seguir usando Elegir archivo…"
        if (result.skipped > 0)
            statusText += " Se omitieron " + result.skipped + " archivo(s) no compatibles."
    }

    onClosed: {
        if (pendingCommand !== "") executable.disconnectSource(pendingCommand)
        pendingCommand = ""
        pendingRequestId = ""
        busy = false
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { dialog.finish(sourceName, data) }
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
                Layout.fillWidth: true
                text: dialog.itemName + " · Steam AppID " + dialog.appId
                textFormat: Text.PlainText
                font.bold: true
                font.pixelSize: 17
                wrapMode: Text.WordWrap
            }
            Controls.Label {
                Layout.fillWidth: true
                text: "Estas imágenes ya están en tu equipo. No se descargará nada ni se cambiará el juego hasta que confirmes la imagen desde Preferencias."
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Controls.BusyIndicator {
                    running: dialog.busy
                    visible: dialog.busy
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                }
                Controls.Label {
                    Layout.fillWidth: true
                    text: dialog.statusText
                    textFormat: Text.PlainText
                    color: dialog.statusError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    wrapMode: Text.WordWrap
                }
            }
            Controls.Frame {
                Layout.fillWidth: true
                visible: dialog.selectedCandidate !== null
                padding: 8
                ColumnLayout {
                    anchors.fill: parent
                    spacing: 7
                    Rectangle {
                        id: previewFrame
                        Layout.fillWidth: true
                        Layout.preferredHeight: 190
                        radius: 10
                        color: "#CC24282D"
                        clip: true
                        AzukiArtwork {
                            anchors.fill: parent
                            source: dialog.selectedCandidate ? dialog.selectedCandidate.fileUrl : ""
                            cornerRadius: previewFrame.radius
                        }
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        text: dialog.selectedCandidate
                            ? dialog.selectedCandidate.label + " · "
                              + dialog.selectedCandidate.width + " × " + dialog.selectedCandidate.height
                              + " · " + Math.round(dialog.selectedCandidate.bytes / 1024) + " KiB"
                            : ""
                        textFormat: Text.PlainText
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                }
            }
            Controls.Label {
                Layout.fillWidth: true
                visible: dialog.candidates.length > 0
                text: "Variantes disponibles"
                font.bold: true
            }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= 520 ? 3 : width >= 360 ? 2 : 1
                columnSpacing: 8
                rowSpacing: 8

                Repeater {
                    model: dialog.candidates
                    delegate: Controls.ItemDelegate {
                        id: candidateDelegate
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredHeight: 157
                        padding: 7
                        highlighted: dialog.selectedIndex === index
                        onClicked: dialog.selectedIndex = index

                        contentItem: ColumnLayout {
                            spacing: 5
                            Image {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 99
                                source: candidateDelegate.modelData.fileUrl
                                asynchronous: true
                                cache: true
                                fillMode: Image.PreserveAspectFit
                                sourceSize.width: 320
                                sourceSize.height: 200
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: candidateDelegate.modelData.label
                                textFormat: Text.PlainText
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                text: candidateDelegate.modelData.width + " × " + candidateDelegate.modelData.height
                                textFormat: Text.PlainText
                                font.pixelSize: 11
                                opacity: 0.7
                            }
                        }
                    }
                }
            }
            Controls.Label {
                Layout.fillWidth: true
                visible: dialog.candidates.length > 0
                text: "Las portadas verticales se recortarán para llenar un mosaico horizontal. Elige la variante cuya composición prefieras."
                textFormat: Text.PlainText
                font.pixelSize: 12
                opacity: 0.7
                wrapMode: Text.WordWrap
            }
            Controls.Button {
                Layout.alignment: Qt.AlignLeft
                text: "Buscar de nuevo"
                icon.name: "view-refresh"
                enabled: !dialog.busy
                onClicked: dialog.beginScan()
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
            text: "Usar esta imagen"
            icon.name: "document-import"
            enabled: !dialog.busy && dialog.selectedCandidate !== null
            Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.ActionRole
            onClicked: {
                var selected = dialog.selectedCandidate
                if (!selected) return
                dialog.sourceChosen(dialog.targetId, selected.fileUrl)
                dialog.close()
            }
        }
    }
}
