import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.plasma.plasma5support as Plasma5Support
import "TileModel.js" as TileModel
import "TileDefaults.js" as TileDefaults
import "RawgImport.js" as RawgImport
import org.kde.plasma.plasmoid

Item {
    id: root
    readonly property string protocolInstanceId: String(Plasmoid.id)
    function committedDraftText() {
        return cfg_libraryJson && cfg_libraryJson.trim() ? cfg_libraryJson : TileDefaults.json
    }
    function saveConfig() {
        coordination.prepareApply(committedDraftText())
    }
    property string cfg_libraryJson: ""
    property bool publishingLibrary: false
    property string query: ""
    property bool busy: false
    property bool ready: false
    property string statusText: "Comprobando las credenciales locales…"
    property var results: []
    property int resultCount: 0
    property var selectedGame: null
    property string pendingCommand: ""
    property string pendingAction: ""
    property string pendingId: ""
    property int requestCounter: 0
    readonly property bool wide: width >= 680

    function currentLibrary() {
        var text = cfg_libraryJson && cfg_libraryJson.trim()
                   ? cfg_libraryJson : TileDefaults.json
        return TileModel.parseLibrary(text)
    }

    function openImport() {
        if (!selectedGame || busy) return
        try {
            importDialog.prepare(selectedGame, currentLibrary())
        } catch (e) {
            statusText = "No se pudo preparar la importación: " + String(e.message || e)
        }
    }

    function prepareImport(options) {
        if (busy || !selectedGame || !importDialog.game ||
            String(selectedGame.id) !== String(importDialog.game.id)) return
        try {
            // Se lee el borrador más reciente, nunca la copia que abrió el diálogo.
            var candidate = RawgImport.buildCandidate(currentLibrary(), importDialog.game, options)
            var json = JSON.stringify(candidate.library)
            coordination.markDirty(json)
            publishingLibrary = true
            cfg_libraryJson = json
            publishingLibrary = false
            importDialog.close()
            statusText = candidate.created
                ? "Juego añadido al borrador. Pulsa Aplicar para guardarlo. Configura su lanzamiento en Elementos si lo dejaste vacío."
                : "Metadatos preparados para «" + TileModel.findItem(candidate.library.items, candidate.itemId).name + "». Pulsa Aplicar para guardarlos."
        } catch (e) {
            publishingLibrary = false
            importDialog.errorMessage = String(e.message || e)
        }
    }

    onCfg_libraryJsonChanged: {
        if (!publishingLibrary && importDialog.visible) {
            importDialog.close()
            statusText = "La biblioteca cambió. Vuelve a abrir la importación para revisar los datos actuales."
        }
    }

    CoordinationProbe {
        id: coordination
        instanceId: root.protocolInstanceId
        Component.onCompleted: openSession(root.committedDraftText())
    }

    RawgImportDialog {
        id: importDialog
        parent: root
        onImportRequested: function(options) { root.prepareImport(options) }
    }

    function shellQuote(text) {
        return "'" + String(text).replace(/'/g, "'\"'\"'") + "'"
    }

    // Only ASCII-safe, percent-encoded text is passed through the command engine.
    function encodeQuery(text) {
        return encodeURIComponent(text).replace(/[!'()*]/g, function(c) {
            return "%" + c.charCodeAt(0).toString(16).toUpperCase()
        })
    }

    function scriptPath() {
        var url = Qt.resolvedUrl("../scripts/rawg_client.py").toString()
        if (url.indexOf("file://") !== 0)
            return ""
        return decodeURIComponent(url.substring(7))
    }

    function request(action, value) {
        if (busy)
            return
        var path = scriptPath()
        if (!path) {
            statusText = "No se encontró el cliente local RAWG."
            return
        }
        var command = "/usr/bin/python3 " + shellQuote(path) + " " + action
        if (action === "search") {
            var encoded = encodeQuery(value)
            command += " --query-encoded " + shellQuote(encoded)
        } else if (action === "detail") {
            if (!/^[0-9]{1,12}$/.test(String(value)))
                return
            command += " --game-id " + String(value)
        }
        requestCounter++
        pendingId = String(requestCounter)
        command += " --request-id " + pendingId
        pendingAction = action
        pendingCommand = command
        busy = true
        statusText = action === "search" ? "Buscando juegos…"
                   : action === "detail" ? "Consultando detalles…"
                   : "Comprobando credenciales…"
        executable.connectSource(command)
    }

    function search() {
        if (busy || !ready)
            return
        var text = query.trim()
        if (text.length < 2 || text.length > 120) {
            statusText = "Escribe entre 2 y 120 caracteres."
            return
        }
        selectedGame = null
        results = []
        resultCount = 0
        request("search", text)
    }

    function finish(sourceName, data) {
        executable.disconnectSource(sourceName)
        if (sourceName !== pendingCommand)
            return
        var action = pendingAction
        var id = pendingId
        pendingCommand = ""
        pendingAction = ""
        pendingId = ""
        busy = false
        var payload
        try {
            payload = JSON.parse(data["stdout"] || "")
        } catch (e) {
            statusText = "El cliente no devolvió JSON válido. Comprueba su instalación."
            return
        }
        if (String(payload.requestId) !== id)
            return
        if (Number(data["exit code"]) !== 0 || payload.ok !== true) {
            statusText = payload.message || "La operación no pudo completarse."
            return
        }
        if (action === "status") {
            ready = payload.data.ready === true
            statusText = ready ? "RAWG conectado. Escribe el nombre de un juego." : "No se encontró una clave válida."
        } else if (action === "search") {
            results = payload.data.results || []
            resultCount = payload.data.count || 0
            statusText = results.length ? "Resultados encontrados: " + resultCount + ". Se muestran los primeros 10."
                                        : "No se encontraron juegos. Prueba otra búsqueda."
        } else if (action === "detail") {
            selectedGame = payload.data
            statusText = "Detalles recibidos. La biblioteca todavía no se ha modificado."
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            root.finish(sourceName, data)
        }
    }

    Component.onCompleted: request("status", "")

    CoordinationNotice {
        id: coordinationWarning
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        protocolState: coordination.protocolState
        details: coordination.message
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: coordinationWarning.visible ? coordinationWarning.implicitHeight + 8 : 0
        spacing: 10
        enabled: coordination.editingAllowed

        Controls.Label {
            text: "Buscar juegos en RAWG"
            font.bold: true
            font.pixelSize: 18
            Layout.fillWidth: true
        }
        Controls.Label {
            text: "Busca por nombre y selecciona un resultado para consultar sus detalles. Selecciona un resultado, revisa sus detalles y elige qué datos importar. Los cambios se guardan al pulsar Aplicar. Los comandos de los elementos existentes no se modificarán."
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        RowLayout {
            Layout.fillWidth: true
            Controls.TextField {
                id: queryField
                Layout.fillWidth: true
                placeholderText: "Ej. Mini Metro, Overwatch, ReStory…"
                text: root.query
                onTextEdited: root.query = text
                onAccepted: root.search()
                enabled: !root.busy
                maximumLength: 120
            }
            Controls.Button {
                text: "Buscar"
                icon.name: "search"
                enabled: root.ready && !root.busy && root.query.trim().length >= 2
                onClicked: root.search()
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Controls.BusyIndicator {
                running: root.busy
                visible: root.busy
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
            }
            Controls.Label {
                Layout.fillWidth: true
                text: root.statusText
                wrapMode: Text.WordWrap
                font.pixelSize: 13
            }
            Controls.Button {
                text: "Revisar conexión"
                enabled: !root.busy
                visible: !root.ready
                onClicked: root.request("status", "")
            }
        }

        Controls.ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            contentHeight: body.implicitHeight

            ColumnLayout {
                id: body
                width: scroll.availableWidth
                spacing: 12

                GridLayout {
                    Layout.fillWidth: true
                    columns: root.wide ? 2 : 1
                    columnSpacing: 14
                    rowSpacing: 14

                    Controls.Frame {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: root.wide ? 310 : -1
                        padding: 10
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6
                            Controls.Label {
                                text: "Resultados" + (root.results.length ? " (" + root.results.length + ")" : "")
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.results.length === 0
                                text: "Los resultados aparecerán aquí después de buscar."
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Repeater {
                                model: root.results
                                delegate: Controls.ItemDelegate {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    highlighted: root.selectedGame !== null && root.selectedGame.id === modelData.id
                                    onClicked: root.request("detail", modelData.id)
                                    contentItem: ColumnLayout {
                                        spacing: 2
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                        text: modelData.name
                                            font.bold: true
                                            wrapMode: Text.WordWrap
                                        }
                                        Controls.Label {
                                            Layout.fillWidth: true
                                            text: (modelData.released || "Sin fecha") + " · RAWG #" + modelData.id
                                            opacity: 0.7
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Controls.Frame {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: root.wide ? 400 : -1
                        padding: 12
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 9
                            Controls.Label {
                                text: "Vista previa"
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame === null
                                text: "Selecciona un resultado para obtener la descripción y los metadatos completos."
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                textFormat: Text.PlainText
                                text: root.selectedGame ? root.selectedGame.name : ""
                                font.family: "Oxanium"
                                font.pixelSize: 18
                                font.bold: true
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                textFormat: Text.PlainText
                                text: root.selectedGame ? "RAWG ID: " + root.selectedGame.id : ""
                                opacity: 0.7
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                text: root.selectedGame ? "Fecha: " + (root.selectedGame.released || "No disponible") : ""
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                text: root.selectedGame ? "Desarrolladores: " + (root.selectedGame.developers.join(", ") || "No disponibles") : ""
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                text: root.selectedGame ? "Publishers: " + (root.selectedGame.publishers.join(", ") || "No disponibles") : ""
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                text: root.selectedGame ? "Géneros: " + (root.selectedGame.genres.join(", ") || "No disponibles") : ""
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                text: root.selectedGame ? "RAWG: " + (root.selectedGame.rating === null ? "Sin puntuación" : root.selectedGame.rating + "/5") + "  ·  Metacritic: " + (root.selectedGame.metacritic === null ? "N/D" : root.selectedGame.metacritic + "/100") : ""
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                text: "Descripción"
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                textFormat: Text.PlainText
                                text: root.selectedGame ? (root.selectedGame.description || "No hay descripción disponible.") : ""
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                font.pixelSize: 13
                            }
                            Controls.Button {
                                visible: root.selectedGame !== null
                                enabled: !root.busy
                                text: "Importar al Tile Deck…"
                                icon.name: "document-import"
                                Layout.fillWidth: true
                                onClicked: root.openImport()
                            }
                            Controls.Label {
                                visible: root.selectedGame !== null
                                Layout.fillWidth: true
                                textFormat: Text.RichText
                                text: "Datos proporcionados por <a href=\"https://rawg.io\">RAWG</a>"
                                onLinkActivated: function(link) { Qt.openUrlExternally("https://rawg.io") }
                            }
                            Controls.Button {
                                visible: root.selectedGame !== null
                                text: "Ver ficha en RAWG"
                                icon.name: "internet-web-browser"
                                onClicked: {
                                    if (root.selectedGame)
                                        Qt.openUrlExternally(root.selectedGame.rawgUrl)
                                }
                            }
                        }
                    }
                }
                Controls.Label {
                    Layout.fillWidth: true
                    text: "Solo se consultará RAWG al buscar o solicitar detalles. La importación guarda los campos elegidos en el borrador local; no descarga imágenes ni modifica los comandos de juegos existentes. Datos proporcionados por RAWG: https://rawg.io."
                    wrapMode: Text.WordWrap
                    opacity: 0.7
                    font.pixelSize: 12
                }
            }
        }
    }
}
