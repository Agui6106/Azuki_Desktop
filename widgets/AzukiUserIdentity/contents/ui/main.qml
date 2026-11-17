import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    /*
     * En el panel siempre mostramos la representación compacta.
     * Al hacer clic, Plasma abre automáticamente fullRepresentation
     * como un popup externo al panel.
     */
    preferredRepresentation: compactRepresentation

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"

        function exec(command) {
            connectSource(command)
        }

        onNewData: function(source, data) {
            disconnectSource(source)
        }
    }

    /*
     * ============================================================
     * REPRESENTACIÓN DEL PANEL
     * ============================================================
     */

    compactRepresentation: RowLayout {
        id: identityRow

        spacing: 8

        Layout.minimumWidth: implicitWidth
        Layout.preferredWidth: implicitWidth
        Layout.fillHeight: true

        Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
            Layout.alignment: Qt.AlignVCenter

            radius: width / 2
            color: "#21CFE0"

            Item {
                anchors.centerIn: parent
                width: 34
                height: 34

                Image {
                    id: avatarSource
                    anchors.fill: parent

                    source: "file:///var/lib/AccountsService/icons/azuki505"

                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true

                    visible: false
                }

                Rectangle {
                    id: avatarMask
                    anchors.fill: parent

                    radius: width / 2
                    color: "white"

                    visible: false
                    layer.enabled: true
                }

                MultiEffect {
                    anchors.fill: parent

                    source: avatarSource

                    maskEnabled: true
                    maskSource: avatarMask
                }
            }
        }

        PlasmaComponents.Label {
            text: "Jose"

            font.family: "Oxanium"
            font.pixelSize: 18
            font.weight: Font.Medium

            verticalAlignment: Text.AlignVCenter
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton

            onTapped: {
                root.expanded = !root.expanded
            }
        }

    }

    /*
     * ============================================================
     * POPUP
     * ============================================================
     */

    fullRepresentation: Item {
        id: popup

        Layout.minimumWidth: 300
        Layout.preferredWidth: 300
        Layout.maximumWidth: 300

        Layout.minimumHeight: menuColumn.implicitHeight + 16
        Layout.preferredHeight: menuColumn.implicitHeight + 16
        Layout.maximumHeight: menuColumn.implicitHeight + 16

        Column {
            id: menuColumn

            x: 8
            y: 8
            width: parent.width - 16

            spacing: 4


            PlasmaComponents.ItemDelegate {
                width: parent.width
                height: 48

                contentItem: RowLayout {
                    spacing: 12

                    Kirigami.Icon {
                        source: "system-file-manager"

                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                    }

                    PlasmaComponents.Label {
                        text: "Archivos"

                        font.family: "Exo 2"
                        font.pixelSize: 18

                        verticalAlignment: Text.AlignVCenter
                        Layout.fillWidth: true
                    }
                }

                onClicked: {
                    executable.exec("nautilus")
                    root.expanded = false
                }
            }

            PlasmaComponents.ItemDelegate {
                width: parent.width
                height: 48


                // VS Code
                contentItem: RowLayout {
                    spacing: 12

                    Kirigami.Icon {
                        source: "file:///snap/code/current/meta/gui/vscode.png"

                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                    }

                    PlasmaComponents.Label {
                        text: "Visual Studio Code"

                        font.family: "Exo 2"
                        font.pixelSize: 18

                        verticalAlignment: Text.AlignVCenter
                        Layout.fillWidth: true
                    }

                    /*
                    TapHandler {
                        onTapped: {
                            executable.connectSource("code")
                            root.expanded = false
                        }
                    }
                    */
                }

                onClicked: {
                    executable.exec("code")
                    root.expanded = false
                }
                
            }

            PlasmaComponents.ItemDelegate {
                width: parent.width
                height: 48

                contentItem: RowLayout {
                    spacing: 12

                    Kirigami.Icon {
                        source: "settings-configure"

                        Layout.preferredWidth: 26
                        Layout.preferredHeight: 26
                        Layout.alignment: Qt.AlignVCenter
                    }

                    PlasmaComponents.Label {
                        text: "Configuración del sistema"

                        font.family: "Exo 2"
                        font.pixelSize: 18

                        verticalAlignment: Text.AlignVCenter
                        Layout.fillWidth: true
                    }
                }

                onClicked: {
                    executable.exec("systemsettings")
                    root.expanded = false
                }
            }
        }
    }
}
