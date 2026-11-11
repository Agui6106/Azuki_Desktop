import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import "TileModel.js" as TileModel
import "TileDefaults.js" as TileDefaults
import org.kde.plasma.plasmoid

Item {
    id: page

    readonly property string protocolInstanceId: String(Plasmoid.id)
    function committedDraftText() {
        return cfg_libraryJson && cfg_libraryJson.trim() ? cfg_libraryJson : TileDefaults.json
    }
    function saveConfig() {
        coordination.prepareApply(committedDraftText())
    }

    // Plasma mantiene esta propiedad como borrador y gestiona Aplicar/Cancelar.
    property string cfg_libraryJson: ""
    property var draftLibrary: ({schemaVersion: 1, groups: [], items: []})
    property string selectedId: ""
    readonly property var currentItem: TileModel.findItem(draftLibrary.items, selectedId)
    property var form: ({})
    property bool formDirty: false
    property bool loadingForm: false
    property bool publishing: false
    property string lastPublishedJson: ""
    property string libraryError: ""
    property string formError: ""
    property var pendingAction: null
    property string removalId: ""
    property int idCounter: 0

    function loadFromConfiguration() {
        if (publishing || (cfg_libraryJson === lastPublishedJson && lastPublishedJson !== "" && libraryError === ""))
            return
        try {
            var input = cfg_libraryJson && cfg_libraryJson.trim()
                        ? cfg_libraryJson : TileDefaults.json
            var result = TileModel.parseLibrary(input)
            draftLibrary = result
            libraryError = ""
            lastPublishedJson = cfg_libraryJson
            var nextId = TileModel.findItem(result.items, selectedId)
                         ? selectedId : (result.items.length ? result.items[0].id : "")
            loadForm(nextId)
        } catch (e) {
            libraryError = "No se pudo cargar la biblioteca: " + e
        }
    }

    function loadForm(id) {
        loadingForm = true
        selectedId = id
        var item = TileModel.findItem(draftLibrary.items, id)
        form = item ? TileModel.formFromItem(item) : ({})
        formDirty = false
        formError = ""
        loadingForm = false
    }

    function edit(field, value) {
        if (loadingForm || !currentItem) return
        var next = Object.assign({}, form)
        next[field] = value
        form = next
        coordination.markDirty()
        formDirty = true
        formError = TileModel.formError(currentItem, form)
    }

    function publish(candidate) {
        try {
            var normalized = TileModel.normalizeLibrary(candidate)
            var json = JSON.stringify(normalized)
            draftLibrary = normalized
            libraryError = ""
            // No escribir directamente a Plasmoid.configuration: se respeta Cancelar.
            lastPublishedJson = json
            coordination.markDirty(json)
            publishing = true
            cfg_libraryJson = json
            publishing = false
            return true
        } catch (e) {
            publishing = false
            libraryError = String(e.message || e)
            return false
        }
    }

    function saveItem() {
        if (!currentItem) return false
        try {
            var item = TileModel.itemFromForm(currentItem, form)
            var next = TileModel.replaceItem(draftLibrary, item)
            if (!publish(next)) return false
            loadForm(item.id)
            return true
        } catch (e) {
            formError = String(e.message || e)
            return false
        }
    }

    function requestAction(kind, id) {
        if (formDirty) {
            pendingAction = {kind: kind, id: id || ""}
            unsavedDialog.open()
            return
        }
        performAction(kind, id || "")
    }

    function performAction(kind, id) {
        if (kind === "select") {
            loadForm(id)
            return
        }
        if (kind === "add") {
            if (draftLibrary.items.length >= TileModel.MAX_ITEMS) {
                libraryError = "Se alcanzó el máximo de elementos."
                return
            }
            var newId
            do {
                idCounter++
                newId = "custom-" + Date.now().toString(36) + "-" + idCounter.toString(36)
            } while (TileModel.findItem(draftLibrary.items, newId))
            var item = TileModel.createItem(newId)
            if (!draftLibrary.groups.some(function(g) { return g.id === "main" }))
                item.groupId = draftLibrary.groups[0].id
            if (publish(TileModel.insertItem(draftLibrary, item))) loadForm(newId)
            return
        }
        if (kind === "remove") {
            removalId = id
            removeDialog.open()
            return
        }
        if (kind === "up" || kind === "down") {
            publish(TileModel.moveItem(draftLibrary, id, kind === "up" ? -1 : 1))
        }
    }

    function confirmRemove() {
        var id = removalId
        removalId = ""
        if (!TileModel.findItem(draftLibrary.items, id)) return
        try {
            var oldIndex = -1
            for (var i = 0; i < draftLibrary.items.length; ++i) {
                if (draftLibrary.items[i].id === id) { oldIndex = i; break }
            }
            var next = TileModel.removeItem(draftLibrary, id)
            if (publish(next)) {
                var index = Math.min(oldIndex, next.items.length - 1)
                loadForm(index >= 0 ? next.items[index].id : "")
            }
        } catch (e) {
            libraryError = String(e.message || e)
        }
    }

    function selectedIndex() {
        for (var i = 0; i < draftLibrary.items.length; ++i)
            if (draftLibrary.items[i].id === selectedId) return i
        return -1
    }

    function typeLabel(type) {
        if (type === "game") return "Juego"
        if (type === "folder") return "Carpeta"
        return "Aplicación"
    }

    onCfg_libraryJsonChanged: loadFromConfiguration()
    Component.onCompleted: loadFromConfiguration()

    CoordinationProbe {
        id: coordination
        instanceId: page.protocolInstanceId
        Component.onCompleted: openSession(page.committedDraftText())
    }

    // Guaradste?
    Controls.Dialog {
        id: unsavedDialog
        title: "Cambios sin guardar"
        modal: true
        parent: page
        anchors.centerIn: parent
        width: Math.min(420, page.width - 24)
        standardButtons: Controls.Dialog.NoButton
        contentItem: Controls.Label {
            text: "Este elemento tiene cambios sin guardar. Guárdalos antes de continuar o descártalos."
            wrapMode: Text.WordWrap
        }
        footer: Controls.DialogButtonBox {
            Controls.Button {
                text: "Seguir editando"
                Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.RejectRole
                onClicked: {
                    page.pendingAction = null
                    unsavedDialog.close()
                }
            }
            Controls.Button {
                text: "Descartar y continuar"
                Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.DestructiveRole
                onClicked: {
                    var action = page.pendingAction
                    page.pendingAction = null
                    unsavedDialog.close()
                    page.loadForm(page.selectedId)
                    if (action) page.performAction(action.kind, action.id)
                }
            }
        }
        onRejected: page.pendingAction = null
    }

    // Elimar del deck
    Controls.Dialog {
        id: removeDialog
        title: "Quitar del Tile Deck"
        modal: true
        parent: page
        anchors.centerIn: parent
        width: Math.min(420, page.width - 24)
        standardButtons: Controls.Dialog.NoButton
        contentItem: Controls.Label {
            text: "¿Quitar este acceso? No se desinstalará el juego o aplicación ni se borrarán sus archivos."
            wrapMode: Text.WordWrap
        }
        footer: Controls.DialogButtonBox {
            Controls.Button {
                text: "Cancelar"
                Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.RejectRole
                onClicked: {
                    page.removalId = ""
                    removeDialog.close()
                }
            }
            Controls.Button {
                text: "Quitar acceso"
                Controls.DialogButtonBox.buttonRole: Controls.DialogButtonBox.DestructiveRole
                onClicked: {
                    removeDialog.close()
                    page.confirmRemove()
                }
            }
        }
        onRejected: page.removalId = ""
    }

    // Titulos y separacion de columnas
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
            text: "Biblioteca de Azuki Tile Deck"
            font.bold: true
            font.pixelSize: 18
            Layout.fillWidth: true
        }
        Controls.Label {
            text: "Edita un elemento, pulsa Guardar elemento y después Aplicar. Los cambios se guardan únicamente en este widget."
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
        Controls.Label {
            visible: page.libraryError !== ""
            text: page.libraryError
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Controls.SplitView {
            id: split
            Layout.fillWidth: true
            Layout.fillHeight: true
            orientation: page.width < 640 ? Qt.Vertical : Qt.Horizontal

            Item {
                Controls.SplitView.preferredWidth: 215
                Controls.SplitView.minimumWidth: 170
                Controls.SplitView.preferredHeight: 190
                Controls.SplitView.minimumHeight: 130

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6
                    Controls.Label {
                        text: "Elementos (" + page.draftLibrary.items.length + ")"
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    ListView {
                        id: itemList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: page.draftLibrary.items
                        currentIndex: page.selectedIndex()
                        delegate: Controls.ItemDelegate {
                            width: itemList.width
                            height: 58
                            highlighted: modelData.id === page.selectedId
                            text: modelData.name + "\n" + page.typeLabel(modelData.type) + " · "
                                  + modelData.size.columns + "×" + modelData.size.rows
                            onClicked: page.requestAction("select", modelData.id)
                        }
                        Controls.ScrollBar.vertical: Controls.ScrollBar {}
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.Button {
                            text: "+ Agregar"
                            enabled: page.draftLibrary.items.length < TileModel.MAX_ITEMS
                            onClicked: page.requestAction("add", "")
                        }
                        Controls.Button {
                            text: "Quitar"
                            enabled: page.currentItem !== null
                            onClicked: page.requestAction("remove", page.selectedId)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.Button {
                            text: "↑ Subir"
                            enabled: page.selectedIndex() > 0
                            onClicked: page.requestAction("up", page.selectedId)
                        }
                        Controls.Button {
                            text: "↓ Bajar"
                            enabled: page.selectedIndex() >= 0 && page.selectedIndex() < page.draftLibrary.items.length - 1
                            onClicked: page.requestAction("down", page.selectedId)
                        }
                    }
                }
            }
            
            // Config Scrolleable
            Controls.ScrollView {
                id: formScroll
                Controls.SplitView.fillWidth: true
                Controls.SplitView.fillHeight: true
                Controls.SplitView.minimumWidth: 240
                Controls.SplitView.minimumHeight: 220
                clip: true
                contentWidth: availableWidth

                ColumnLayout {
                    width: formScroll.availableWidth
                    spacing: 8
                    enabled: page.currentItem !== null

                    Controls.Label {
                        text: page.currentItem ? "Editar: " + page.currentItem.name : "Selecciona o agrega un elemento"
                        font.bold: true
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        visible: page.formDirty
                        text: "Hay cambios sin guardar. Pulsa Guardar elemento antes de Aplicar."
                        color: Kirigami.Theme.neutralTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        visible: page.formError !== ""
                        text: page.formError
                        color: Kirigami.Theme.negativeTextColor
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Controls.Label { text: "Nombre completo" }
                    Controls.TextField {
                        Layout.fillWidth: true
                        text: page.form.name || ""
                        placeholderText: "Nombre que se mostrará en InfoBar"
                        onTextEdited: page.edit("name", text)
                    }
                    Controls.Label { text: "Etiqueta del mosaico" }
                    Controls.TextArea {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 62
                        text: page.form.tileLabel || ""
                        wrapMode: TextEdit.Wrap
                        placeholderText: "Puedes escribir el título en varias líneas"
                        onTextChanged: {
                            if (!page.loadingForm && page.currentItem && text !== page.form.tileLabel)
                                page.edit("tileLabel", text)
                        }
                    }
                    Controls.Label { text: "Tipo" }
                    Controls.ComboBox {
                        id: typeCombo
                        Layout.fillWidth: true
                        enabled: page.form.type !== "folder"
                        model: page.form.type === "folder"
                               ? ["Aplicación", "Juego", "Carpeta (pendiente de v0.9)"]
                               : ["Aplicación", "Juego"]
                        currentIndex: page.form.type === "game" ? 1 : page.form.type === "folder" ? 2 : 0
                        onActivated: page.edit("type", index === 1 ? "game" : "application")
                    }
                    Controls.Label { text: "Tamaño" }
                    Controls.ComboBox {
                        Layout.fillWidth: true
                        model: ["1x1", "2x1", "2x2"]
                        currentIndex: Math.max(0, ["1x1", "2x1", "2x2"].indexOf(page.form.size || "1x1"))
                        onActivated: page.edit("size", ["1x1", "2x1", "2x2"][index])
                    }
                    Controls.Label { text: "Descripción" }
                    Controls.TextArea {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 74
                        text: page.form.description || ""
                        wrapMode: TextEdit.Wrap
                        placeholderText: "Descripción breve del elemento"
                        onTextChanged: {
                            if (!page.loadingForm && page.currentItem && text !== page.form.description)
                                page.edit("description", text)
                        }
                    }

                    Controls.Label {
                        text: "Lanzamiento"
                        font.bold: true
                        Layout.topMargin: 8
                    }
                    Controls.Label {
                        visible: page.form.type === "folder"
                        text: "La navegación de carpetas se implementará en v0.9."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Controls.ComboBox {
                        id: launchCombo
                        Layout.fillWidth: true
                        enabled: page.form.type !== "folder"
                        model: ["Sin comando", "Steam", "Aplicación local", "URL web"]
                        currentIndex: page.form.launchType === "steam" ? 1
                                      : page.form.launchType === "executable" ? 2
                                      : page.form.launchType === "url" ? 3 : 0
                        onActivated: page.edit("launchType", ["none", "steam", "executable", "url"][index])
                    }
                    Controls.Label {
                        visible: page.form.launchType === "steam" && page.form.type !== "folder"
                        text: "AppID de Steam"
                    }
                    Controls.TextField {
                        Layout.fillWidth: true
                        visible: page.form.launchType === "steam" && page.form.type !== "folder"
                        text: page.form.appId || ""
                        placeholderText: "2357570"
                        inputMethodHints: Qt.ImhDigitsOnly
                        onTextEdited: page.edit("appId", text)
                    }
                    Controls.Label {
                        visible: page.form.launchType === "executable" && page.form.type !== "folder"
                        text: "Comando local"
                    }
                    Controls.TextField {
                        Layout.fillWidth: true
                        visible: page.form.launchType === "executable" && page.form.type !== "folder"
                        text: page.form.command || ""
                        placeholderText: "/snap/bin/code"
                        onTextEdited: page.edit("command", text)
                    }
                    Controls.Label {
                        visible: page.form.launchType === "executable" && page.form.type !== "folder"
                        text: "El comando se ejecutará únicamente al pulsar ABRIR/JUGAR. Utiliza comandos de confianza."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        visible: page.form.launchType === "url" && page.form.type !== "folder"
                        text: "URL"
                    }
                    Controls.TextField {
                        Layout.fillWidth: true
                        visible: page.form.launchType === "url" && page.form.type !== "folder"
                        text: page.form.url || ""
                        placeholderText: "https://ejemplo.com"
                        onTextEdited: page.edit("url", text)
                    }

                    Controls.Label {
                        text: "Información adicional"
                        font.bold: true
                        Layout.topMargin: 8
                    }
                    Controls.Label { text: "Año o fecha de lanzamiento" }
                    Controls.TextField {
                        Layout.fillWidth: true
                        text: page.form.releaseDate || ""
                        placeholderText: "AAAA o AAAA-MM-DD"
                        onTextEdited: page.edit("releaseDate", text)
                    }
                    Controls.Label { text: "Desarrolladores (separados por comas)"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Controls.TextField {
                        Layout.fillWidth: true
                        text: page.form.developers || ""
                        onTextEdited: page.edit("developers", text)
                    }
                    Controls.Label { text: "Publishers (separados por comas)"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Controls.TextField {
                        Layout.fillWidth: true
                        text: page.form.publishers || ""
                        onTextEdited: page.edit("publishers", text)
                    }
                    Controls.Label { text: "Géneros o categoría (separados por comas)"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                    Controls.TextField {
                        Layout.fillWidth: true
                        text: page.form.genres || ""
                        onTextEdited: page.edit("genres", text)
                    }
                    Controls.Label {
                        text: "Las imágenes, RAWG, grupos y carpetas se añadirán en fases posteriores."
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                        opacity: 0.7
                    }
                    Controls.Button {
                        text: "Guardar elemento"
                        icon.name: "document-save"
                        enabled: page.currentItem !== null && page.formDirty && page.formError === ""
                        Layout.alignment: Qt.AlignRight
                        onClicked: page.saveItem()
                    }
                    Item { Layout.preferredHeight: 8 }
                }
            }
        }
    }
}
