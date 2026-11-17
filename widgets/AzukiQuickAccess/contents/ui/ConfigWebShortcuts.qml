import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    property string cfg_webShortcutsJson: "[]"

    property bool loadingConfiguration: false
    property int selectedIndex: -1

    ListModel {
        id: shortcutsModel
    }

    function loadShortcuts() {
        loadingConfiguration = true
        shortcutsModel.clear()

        try {
            var data = JSON.parse(cfg_webShortcutsJson)

            if (Array.isArray(data)) {
                for (var i = 0; i < data.length; i++) {
                    shortcutsModel.append({
                        name: data[i].name || "",
                        url: data[i].url || "",
                        icon: data[i].icon || "internet-web-browser"
                    })
                }
            }
        } catch (e) {
            console.log(
                "Azuki Quick Access Config:",
                e
            )
        }

        selectedIndex =
            shortcutsModel.count > 0 ? 0 : -1

        loadingConfiguration = false
    }

    function saveShortcuts() {
        if (loadingConfiguration)
            return

        var data = []

        for (var i = 0; i < shortcutsModel.count; i++) {
            var item = shortcutsModel.get(i)

            data.push({
                name: item.name,
                url: item.url,
                icon: item.icon
            })
        }

        cfg_webShortcutsJson =
            JSON.stringify(data)
    }

    function addShortcut() {
        shortcutsModel.append({
            name: "Nuevo acceso",
            url: "https://",
            icon: "internet-web-browser"
        })

        selectedIndex =
            shortcutsModel.count - 1

        shortcutList.currentIndex =
            selectedIndex

        saveShortcuts()
    }

    function removeShortcut() {
        if (selectedIndex < 0)
            return

        shortcutsModel.remove(selectedIndex)

        if (shortcutsModel.count === 0)
            selectedIndex = -1
        else if (selectedIndex >= shortcutsModel.count)
            selectedIndex = shortcutsModel.count - 1

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

    onCfg_webShortcutsJsonChanged: {
        if (!loadingConfiguration)
            loadShortcuts()
    }

    Component.onCompleted:
        loadShortcuts()

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Label {
            text: "Accesos web"
            font.bold: true
            font.pixelSize: 18
        }

        Label {
            text:
                "Estos accesos se abrirán utilizando el " +
                "navegador predeterminado del sistema."

            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ListView {
            id: shortcutList

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 200

            clip: true
            model: shortcutsModel

            delegate: ItemDelegate {
                width: ListView.view.width
                height: 54

                highlighted:
                    index === root.selectedIndex

                contentItem: Column {
                    Label {
                        text: model.name
                        font.bold: true
                    }

                    Label {
                        text: model.url
                        opacity: 0.65
                        elide: Text.ElideRight
                        width: parent.width
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
                onClicked:
                    root.addShortcut()
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
                    text: "Dirección web"
                }

                TextField {
                    Layout.fillWidth: true
                    enabled:
                        root.selectedIndex >= 0

                    text:
                        root.selectedIndex >= 0
                        ? shortcutsModel.get(
                              root.selectedIndex
                          ).url
                        : ""

                    placeholderText:
                        "https://ejemplo.com"

                    onEditingFinished: {
                        if (root.selectedIndex < 0)
                            return

                        shortcutsModel.setProperty(
                            root.selectedIndex,
                            "url",
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
                        "Nombre de icono o /ruta/icono.svg"

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
