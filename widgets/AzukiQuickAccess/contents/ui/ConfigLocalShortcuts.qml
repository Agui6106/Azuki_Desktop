import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property string cfg_localShortcutsJson: "[]"

    property bool loadingConfiguration: false
    property int selectedIndex: -1

    ListModel {
        id: shortcutsModel
    }

    function loadShortcuts() {
        loadingConfiguration = true
        shortcutsModel.clear()

        try {
            var data = JSON.parse(cfg_localShortcutsJson)

            if (Array.isArray(data)) {
                for (var i = 0; i < data.length; i++) {
                    shortcutsModel.append({
                        shortcutId: data[i].id || ("custom-" + i),
                        name: data[i].name || "",
                        icon: data[i].icon || "application-x-executable",
                        command: data[i].command || ""
                    })
                }
            }
        } catch (e) {
            console.log(
                "Azuki Quick Access Local Config:",
                e
            )
        }

        selectedIndex =
            shortcutsModel.count > 0 ? 0 : -1

        shortcutList.currentIndex = selectedIndex

        loadingConfiguration = false
    }

    function saveShortcuts() {
        if (loadingConfiguration)
            return

        var data = []

        for (var i = 0; i < shortcutsModel.count; i++) {
            var item = shortcutsModel.get(i)

            data.push({
                id: item.shortcutId,
                name: item.name,
                icon: item.icon,
                command: item.command
            })
        }

        cfg_localShortcutsJson =
            JSON.stringify(data)
    }

    function addShortcut() {
        var newId =
            "custom-" +
            Date.now().toString()

        shortcutsModel.append({
            shortcutId: newId,
            name: "Nueva aplicación",
            icon: "application-x-executable",
            command: ""
        })

        selectedIndex =
            shortcutsModel.count - 1

        shortcutList.currentIndex =
            selectedIndex

        saveShortcuts()
    }

    function removeShortcut() {
        if (selectedIndex < 0 ||
            selectedIndex >= shortcutsModel.count)
            return

        shortcutsModel.remove(selectedIndex)

        if (shortcutsModel.count === 0) {
            selectedIndex = -1
        } else if (selectedIndex >= shortcutsModel.count) {
            selectedIndex =
                shortcutsModel.count - 1
        }

        shortcutList.currentIndex =
            selectedIndex

        saveShortcuts()
    }

    function moveUp() {
        if (selectedIndex <= 0)
            return

        shortcutsModel.move(
            selectedIndex,
            selectedIndex - 1,
            1
        )

        selectedIndex--

        shortcutList.currentIndex =
            selectedIndex

        saveShortcuts()
    }

    function moveDown() {
        if (selectedIndex < 0 ||
            selectedIndex >= shortcutsModel.count - 1)
            return

        shortcutsModel.move(
            selectedIndex,
            selectedIndex + 1,
            1
        )

        selectedIndex++

        shortcutList.currentIndex =
            selectedIndex

        saveShortcuts()
    }

    onCfg_localShortcutsJsonChanged: {
        if (!loadingConfiguration)
            loadShortcuts()
    }

    Component.onCompleted:
        loadShortcuts()

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Label {
            text: "Accesos locales"
            font.bold: true
            font.pixelSize: 18
        }

        Label {
            text:
                "Estas aplicaciones se ejecutan directamente desde Azuki Quick Access."

            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ListView {
            id: shortcutList

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 210

            clip: true

            model: shortcutsModel
            currentIndex: root.selectedIndex

            delegate: ItemDelegate {
                width: ListView.view.width
                height: 56

                highlighted:
                    index === root.selectedIndex

                contentItem: Column {
                    spacing: 2

                    Label {
                        text: model.name
                        font.bold: true

                        width: parent.width
                        elide: Text.ElideRight
                    }

                    Label {
                        text: model.command

                        opacity: 0.65

                        width: parent.width
                        elide: Text.ElideRight
                    }
                }

                onClicked: {
                    root.selectedIndex = index
                    shortcutList.currentIndex = index
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: "+ Agregar"
                onClicked: root.addShortcut()
            }

            Button {
                text: "Eliminar"

                enabled:
                    root.selectedIndex >= 0

                onClicked:
                    root.removeShortcut()
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                text: "↑ Subir"

                enabled:
                    root.selectedIndex > 0

                onClicked:
                    root.moveUp()
            }

            Button {
                text: "↓ Bajar"

                enabled:
                    root.selectedIndex >= 0 &&
                    root.selectedIndex <
                    shortcutsModel.count - 1

                onClicked:
                    root.moveDown()
            }
        }

        Frame {
            Layout.fillWidth: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Label {
                    text: "Editar acceso"
                    font.bold: true
                }

                Label {
                    text: "Nombre"
                }

                TextField {
                    Layout.fillWidth: true

                    enabled:
                        root.selectedIndex >= 0

                    text:
                        root.selectedIndex >= 0
                        ? shortcutsModel.get(
                              root.selectedIndex
                          ).name
                        : ""

                    onEditingFinished: {
                        if (root.selectedIndex < 0)
                            return

                        shortcutsModel.setProperty(
                            root.selectedIndex,
                            "name",
                            text
                        )

                        root.saveShortcuts()
                    }
                }

                Label {
                    text: "Comando"
                }

                TextField {
                    Layout.fillWidth: true

                    enabled:
                        root.selectedIndex >= 0

                    text:
                        root.selectedIndex >= 0
                        ? shortcutsModel.get(
                              root.selectedIndex
                          ).command
                        : ""

                    placeholderText:
                        "/usr/bin/aplicacion"

                    onEditingFinished: {
                        if (root.selectedIndex < 0)
                            return

                        shortcutsModel.setProperty(
                            root.selectedIndex,
                            "command",
                            text
                        )

                        root.saveShortcuts()
                    }
                }

                Label {
                    text: "Icono"
                }

                TextField {
                    Layout.fillWidth: true

                    enabled:
                        root.selectedIndex >= 0

                    text:
                        root.selectedIndex >= 0
                        ? shortcutsModel.get(
                              root.selectedIndex
                          ).icon
                        : ""

                    placeholderText:
                        "Nombre del icono o /ruta/icono.svg"

                    onEditingFinished: {
                        if (root.selectedIndex < 0)
                            return

                        shortcutsModel.setProperty(
                            root.selectedIndex,
                            "icon",
                            text
                        )

                        root.saveShortcuts()
                    }
                }
            }
        }
    }
}
