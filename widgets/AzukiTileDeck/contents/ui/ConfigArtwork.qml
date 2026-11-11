import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import QtQuick.Dialogs as Dialogs
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import "TileModel.js" as TileModel
import "TileDefaults.js" as TileDefaults
import "ArtworkModel.js" as ArtworkModel
import org.kde.plasma.plasmoid

Item {
    id: root
    readonly property string protocolInstanceId: String(Plasmoid.id)
    function committedDraftText() {
        return cfg_libraryJson && cfg_libraryJson.trim()
            ? cfg_libraryJson : (cfg_libraryJsonDefault && cfg_libraryJsonDefault.trim()
                                  ? cfg_libraryJsonDefault : TileDefaults.json)
    }
    function saveConfig() {
        coordination.prepareApply(committedDraftText())
    }
    property string title: "Imágenes"
    property string cfg_libraryJson: ""
    property string cfg_libraryJsonDefault: ""
    property var draftLibrary: ({schemaVersion: 1, groups: [], items: []})
    property string selectedId: ""
    readonly property var currentItem: TileModel.findItem(draftLibrary.items, selectedId)
    readonly property bool wide: width >= 720
    readonly property url legacyPreviewUrl:
        StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
        + "/azuki-tile-deck/artwork/mini-metro-preview.jpg"
    readonly property string currentSource: ArtworkModel.sourceForItem(currentItem, legacyPreviewUrl)
    readonly property string displayedSource: pendingMode === "remove" ? ""
        : pendingMode === "select" ? pendingSource : currentSource
    property string pendingMode: ""
    property string pendingSource: ""
    property var pendingInfo: ({})
    property bool publishingLibrary: false
    property bool busy: false
    property string statusText: "Elige un elemento para gestionar su imagen."
    property bool statusError: false
    property string libraryError: ""
    property string pendingCommand: ""
    property string pendingAction: ""
    property string pendingRequestId: ""
    property string pendingTargetId: ""
    property string pendingArtworkSignature: ""
    property int requestCounter: 0
    property string nextSelectionId: ""

    function currentLibrary() {
        var text = cfg_libraryJson && cfg_libraryJson.trim()
            ? cfg_libraryJson : (cfg_libraryJsonDefault && cfg_libraryJsonDefault.trim()
                                  ? cfg_libraryJsonDefault : TileDefaults.json)
        return TileModel.parseLibrary(text)
    }

    function resetPending() {
        pendingMode = ""
        pendingSource = ""
        pendingInfo = ({})
    }

    function loadFromConfiguration() {
        if (publishingLibrary) return
        try {
            var library = currentLibrary()
            draftLibrary = library
            libraryError = ""
            if (!TileModel.findItem(library.items, selectedId))
                selectedId = library.items.length ? library.items[0].id : ""
            if (pendingMode !== "") {
                resetPending()
                statusText = "La biblioteca cambió. Vuelve a seleccionar la imagen antes de guardarla."
            }
        } catch (e) {
            libraryError = "No se pudo cargar la biblioteca: " + String(e.message || e)
        }
    }

    function selectItem(id) {
        if (busy || id === selectedId) return
        if (pendingMode !== "") {
            nextSelectionId = id
            discardDialog.open()
            return
        }
        selectedId = id
        statusError = false
        statusText = "Selecciona una imagen local o quita la imagen actual."
    }

    function shellQuote(text) {
        return "'" + String(text).replace(/'/g, "'\"'\"'") + "'"
    }

    function scriptPath() {
        var url = Qt.resolvedUrl("../scripts/artwork_manager.py").toString()
        if (url.indexOf("file://") !== 0) return ""
        return decodeURIComponent(url.substring(7))
    }

    function request(action, source, expectedHash) {
        if (busy || !currentItem) return
        var script = scriptPath()
        if (!script) {
            statusError = true
            statusText = "No se encontró el gestor local de imágenes."
            return
        }
        var encoded = encodeURIComponent(String(source)).replace(/[!'()*]/g, function(c) {
            return "%" + c.charCodeAt(0).toString(16).toUpperCase()
        })
        if (encoded.length > 24000) {
            statusError = true
            statusText = "La ruta seleccionada es demasiado larga."
            return
        }
        requestCounter++
        pendingRequestId = String(requestCounter)
        pendingAction = action
        pendingTargetId = selectedId
        pendingArtworkSignature = JSON.stringify(currentItem.artwork || {})
        var command = "/usr/bin/python3 " + shellQuote(script) + " " + action
                    + " --source-encoded " + shellQuote(encoded)
                    + " --request-id " + pendingRequestId
        if (action === "copy" && expectedHash)
            command += " --expected-sha256 " + shellQuote(expectedHash)
        pendingCommand = command
        busy = true
        statusError = false
        statusText = action === "inspect" ? "Comprobando la imagen local…" : "Copiando la imagen a Azuki…"
        executable.connectSource(command)
    }

    function commitArtwork(source, targetId, previousSignature) {
        try {
            var library = currentLibrary()
            var item = TileModel.findItem(library.items, targetId)
            if (!item) throw new Error("El elemento ya no existe.")
            if (JSON.stringify(item.artwork || {}) !== previousSignature)
                throw new Error("La imagen del elemento cambió. Vuelve a revisar antes de guardar.")
            var candidate = ArtworkModel.changeArtwork(library, targetId, source)
            var json = JSON.stringify(candidate)
            coordination.markDirty(json)
            publishingLibrary = true
            cfg_libraryJson = json
            draftLibrary = candidate
            publishingLibrary = false
            resetPending()
            statusError = false
            statusText = source === null
                ? "Imagen quitada del borrador. Pulsa Aplicar para guardar el cambio. El archivo no se ha borrado."
                : "Imagen preparada. Pulsa Aplicar para guardarla. La copia local ya está disponible."
        } catch (e) {
            publishingLibrary = false
            statusError = true
            statusText = String(e.message || e)
        }
    }

    function finish(sourceName, data) {
        executable.disconnectSource(sourceName)
        if (sourceName !== pendingCommand) return
        var action = pendingAction
        var requestId = pendingRequestId
        var targetId = pendingTargetId
        var signature = pendingArtworkSignature
        pendingCommand = ""
        pendingAction = ""
        pendingRequestId = ""
        busy = false
        var payload
        try {
            payload = JSON.parse(data["stdout"] || "")
        } catch (e) {
            statusError = true
            statusText = "El gestor no devolvió JSON válido. Comprueba su instalación."
            return
        }
        if (String(payload.requestId) !== requestId) return
        if (Number(data["exit code"]) !== 0 || payload.ok !== true) {
            statusError = true
            statusText = payload.message || "No se pudo procesar la imagen."
            return
        }
        if (selectedId !== targetId) {
            statusError = true
            statusText = "El elemento cambió durante la operación. Revisa la selección."
            return
        }
        if (action === "inspect") {
            coordination.markDirty()
            pendingMode = "select"
            pendingSource = payload.data.fileUrl
            pendingInfo = payload.data
            statusError = false
            statusText = "Vista previa lista. Pulsa Guardar imagen para preparar el cambio."
        } else if (action === "copy") {
            commitArtwork(payload.data.fileUrl, targetId, signature)
        }
    }

    function saveImage() {
        if (busy || !currentItem || pendingMode === "") return
        if (pendingMode === "remove") {
            commitArtwork(null, selectedId, JSON.stringify(currentItem.artwork || {}))
        } else if (pendingMode === "select") {
            request("copy", pendingSource, pendingInfo.sha256 || "")
        }
    }

    function removeImage() {
        if (busy || !currentItem) return
        coordination.markDirty()
        pendingMode = "remove"
        pendingSource = ""
        pendingInfo = ({})
        statusError = false
        statusText = "Se quitará la imagen del mosaico. Pulsa Guardar imagen y después Aplicar. No se eliminará ningún archivo."
    }

    function useCurrentImage() {
        if (!currentSource || busy) return
        request("inspect", currentSource, "")
    }

    onCfg_libraryJsonChanged: loadFromConfiguration()
    Component.onCompleted: loadFromConfiguration()

    CoordinationProbe {
        id: coordination
        instanceId: root.protocolInstanceId
        Component.onCompleted: openSession(root.committedDraftText())
    }
    Component.onDestruction: {
        if (pendingCommand !== "") executable.disconnectSource(pendingCommand)
    }

    SteamArtworkDialog {
        id: steamDialog
        parent: root
        onSourceChosen: function(itemId, source) {
            if (!root.currentItem || root.selectedId !== itemId || root.busy || root.pendingMode !== "") return
            root.request("inspect", source, "")
        }
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { root.finish(sourceName, data) }
    }

    Dialogs.FileDialog {
        id: imageDialog
        title: "Elegir artwork local"
        fileMode: Dialogs.FileDialog.OpenFile
        nameFilters: ["Imágenes (*.jpg *.jpeg *.png *.webp)"]
        currentFolder: StandardPaths.writableLocation(StandardPaths.PicturesLocation)
        onAccepted: root.request("inspect", selectedFile.toString(), "")
    }

    Controls.Dialog {
        id: discardDialog
        parent: root
        anchors.centerIn: parent
        modal: true
        title: "Selección sin guardar"
        standardButtons: Controls.Dialog.NoButton
        width: Math.min(420, root.width - 24)
        contentItem: Controls.Label {
            text: "Tienes una imagen seleccionada que aún no has preparado. ¿Quieres descartarla y cambiar de elemento?"
            wrapMode: Text.WordWrap
        }
        footer: Controls.DialogButtonBox {
            Controls.Button {
                text: "Continuar editando"
                Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.RejectRole
                onClicked: discardDialog.close()
            }
            Controls.Button {
                text: "Descartar selección"
                Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.AcceptRole
                onClicked: {
                    root.resetPending()
                    root.selectedId = root.nextSelectionId
                    root.nextSelectionId = ""
                    discardDialog.close()
                }
            }
        }
    }

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
            text: "Imágenes del Tile Deck"
            font.bold: true
            font.pixelSize: 18
            Layout.fillWidth: true
        }
        Controls.Label {
            text: "Elige una imagen local para cualquier elemento. Se guardará una copia privada en Azuki. Los cambios del mosaico se confirman con Aplicar; los archivos nunca se eliminan automáticamente."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Controls.Label {
            visible: root.libraryError !== ""
            text: root.libraryError
            textFormat: Text.PlainText
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
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
                text: root.statusText
                textFormat: Text.PlainText
                color: root.statusError ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                font.pixelSize: 13
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
                        Layout.preferredWidth: root.wide ? 250 : -1
                        padding: 10
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8
                            Controls.Label {
                                text: "Elementos (" + root.draftLibrary.items.length + ")"
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                visible: root.draftLibrary.items.length === 0
                                text: "No hay elementos en la biblioteca."
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            ListView {
                                id: elementList
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(300, Math.max(60, contentHeight))
                                clip: true
                                model: root.draftLibrary.items
                                spacing: 3
                                currentIndex: -1
                                delegate: Controls.ItemDelegate {
                                    id: entry
                                    required property var modelData
                                    width: elementList.width
                                    enabled: !root.busy
                                    highlighted: root.selectedId === modelData.id
                                    onClicked: root.selectItem(modelData.id)
                                    contentItem: ColumnLayout {
                                        spacing: 1
                                        Controls.Label {
                                            text: entry.modelData.name
                                            textFormat: Text.PlainText
                                            font.bold: entry.highlighted
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Controls.Label {
                                            text: entry.modelData.type === "game" ? "Juego" : entry.modelData.type === "folder" ? "Carpeta" : "Aplicación"
                                            opacity: 0.7
                                            font.pixelSize: 12
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                                Controls.ScrollBar.vertical: Controls.ScrollBar {
                                    policy: Controls.ScrollBar.AsNeeded
                                }
                            }
                        }
                    }

                    Controls.Frame {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.minimumWidth: 0
                        padding: 12
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 10
                            Controls.Label {
                                text: root.currentItem ? "Editar imagen: " + root.currentItem.name : "Selecciona un elemento"
                                textFormat: Text.PlainText
                                font.bold: true
                                font.pixelSize: 17
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Rectangle {
                                id: previewFrame
                                Layout.fillWidth: true
                                Layout.preferredHeight: 210
                                radius: 12
                                color: "#CC24282D"
                                clip: true
                                AzukiArtwork {
                                    anchors.fill: parent
                                    source: root.displayedSource
                                    cornerRadius: previewFrame.radius
                                    visible: root.displayedSource !== ""
                                }
                                Controls.Label {
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    text: root.pendingMode === "remove" ? "Sin imagen" : "No hay artwork asignado"
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    visible: root.displayedSource === ""
                                }
                                Controls.Label {
                                    anchors.centerIn: parent
                                    width: parent.width - 24
                                    text: root.currentItem ? root.currentItem.tileLabel : ""
                                    textFormat: Text.PlainText
                                    font.family: "Oxanium"
                                    font.pixelSize: 19
                                    font.bold: true
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WordWrap
                                    color: "#F2F2F2"
                                    visible: root.displayedSource !== ""
                                }
                            }
                            Controls.Label {
                                text: root.pendingMode === "remove" ? "Imagen pendiente de quitar"
                                    : root.pendingMode === "select" ? "Nueva imagen seleccionada"
                                    : ArtworkModel.legacyPreview(root.currentItem) ? "Imagen de prueba de Mini Metro"
                                    : root.currentSource ? "Imagen actual" : "Sin imagen"
                                font.bold: true
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                text: root.pendingMode === "select" && root.pendingInfo.width
                                    ? root.pendingInfo.width + " × " + root.pendingInfo.height + " · " + root.pendingInfo.format + " · " + Math.round(root.pendingInfo.bytes / 1024) + " KiB"
                                    : "JPEG, PNG o WebP estático. Máximo 16 MiB y 24 megapíxeles."
                                textFormat: Text.PlainText
                                opacity: 0.7
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            Controls.Label {
                                text: root.displayedSource
                                textFormat: Text.PlainText
                                opacity: 0.6
                                font.pixelSize: 11
                                wrapMode: Text.WrapAnywhere
                                Layout.fillWidth: true
                                visible: root.displayedSource !== ""
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 8
                                Controls.Button {
                                    text: "Elegir archivo…"
                                    icon.name: "document-open"
                                    enabled: root.currentItem !== null && !root.busy
                                    onClicked: imageDialog.open()
                                }
                                Controls.Button {
                                    text: "Buscar en Steam…"
                                    icon.name: "search"
                                    visible: root.currentItem !== null && root.currentItem.launch.type === "steam"
                                    enabled: !root.busy && root.pendingMode === "" && root.currentItem !== null
                                    onClicked: steamDialog.openForItem(root.currentItem)
                                }
                                Controls.Button {
                                    text: "Quitar imagen"
                                    icon.name: "edit-clear"
                                    enabled: root.currentItem !== null && !root.busy && root.pendingMode !== "remove" && (root.currentSource !== "" || root.pendingMode === "select")
                                    onClicked: root.removeImage()
                                }
                                Controls.Button {
                                    text: "Conservar imagen actual"
                                    visible: ArtworkModel.legacyPreview(root.currentItem)
                                    enabled: root.currentItem !== null && !root.busy && root.currentSource !== ""
                                    onClicked: root.useCurrentImage()
                                }
                            }
                            Controls.Label {
                                text: "La imagen se copia al preparar el cambio. Si pulsas Cancelar en Preferencias, el JSON vuelve a su estado anterior; una copia que haya quedado sin uso podrá limpiarse más adelante."
                                textFormat: Text.PlainText
                                font.pixelSize: 12
                                opacity: 0.75
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Controls.Button {
                                    text: "Descartar selección"
                                    enabled: root.pendingMode !== "" && !root.busy
                                    onClicked: {
                                        root.resetPending()
                                        root.statusError = false
                                        root.statusText = "Selección descartada."
                                    }
                                }
                                Item { Layout.fillWidth: true }
                                Controls.Button {
                                    text: "Guardar imagen"
                                    icon.name: "document-save"
                                    enabled: root.currentItem !== null && root.pendingMode !== "" && !root.busy
                                    onClicked: root.saveImage()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
