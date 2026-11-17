import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    // Web Shortcuts list
    property var webShortcuts: []

    // Shortcuts list
    property var localShortcuts: []

    readonly property var allShortcuts: {
        var webItems = webShortcuts.map(function(item) {
            return {
                id: "web-" + item.name,
                name: item.name,
                icon: item.icon,
                command: "xdg-open '" + item.url + "'"
            }
        })

        var braveIndex = -1

        for (var i = 0; i < localShortcuts.length; i++) {
            if (localShortcuts[i].id === "brave") {
                braveIndex = i
                break
            }
        }

        // Si Brave existe, insertamos las webs justo después.
        if (braveIndex >= 0) {
            return localShortcuts
                .slice(0, braveIndex + 1)
                .concat(webItems)
                .concat(
                    localShortcuts.slice(
                        braveIndex + 1
                    )
                )
        }

        // Si el usuario eliminó Brave, simplemente colocamos
        // los accesos web después de los locales.
        return localShortcuts.concat(webItems)
    }

    // ============================================================
    // LANZADOR
    // ============================================================

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

    function launch(command) {
        if (command === "azuki-power") {
            powerDialog.visible = true
            return
        }

        executable.exec(command)
    }

    // Read icons
    function resolveIcon(icon) {
        if (icon === "azuki-discord")
            return Qt.resolvedUrl("../images/discord.svg")

        if (icon === "azuki-whatsapp")
            return Qt.resolvedUrl("../images/whatsapp.svg")

        if (icon === "azuki-instagram")
            return Qt.resolvedUrl("../images/instagram.svg")

        if (icon.startsWith("file://"))
            return icon

        if (icon.startsWith("/"))
            return "file://" + icon

        return icon
    }

    // Open web pages
    function loadWebShortcuts() {
        try {
            var parsed = JSON.parse(
                Plasmoid.configuration.webShortcutsJson
            )

            webShortcuts = Array.isArray(parsed)
                ? parsed
                : []

        } catch (e) {
            console.log(
                "Azuki Quick Access: error leyendo accesos web:",
                e
            )

            webShortcuts = []
        }
    }

    // Local Shortcuts
    function loadLocalShortcuts() {
        try {
            var parsed = JSON.parse(
                Plasmoid.configuration.localShortcutsJson
            )

            localShortcuts =
                Array.isArray(parsed)
                ? parsed
                : []

        } catch (e) {
            console.log(
                "Azuki Quick Access: error leyendo accesos locales:",
                e
            )

            localShortcuts = []
        }
    }

    // Power Stuff
    function launchPowerAction(action) {
        powerDialog.visible = false

        switch (action) {
        case "suspend":
            executable.exec("systemctl suspend")
            break

        case "reboot":
            executable.exec(
                "qdbus6 org.kde.LogoutPrompt /LogoutPrompt promptReboot"
            )
            break

        case "shutdown":
            executable.exec(
                "qdbus6 org.kde.LogoutPrompt /LogoutPrompt promptShutDown"
            )
            break
        }
    }

    Component.onCompleted: {
        loadLocalShortcuts()
        loadWebShortcuts()
    }

    Connections {
        target: Plasmoid.configuration

        function onLocalShortcutsJsonChanged() {
            root.loadLocalShortcuts()
        }

        function onWebShortcutsJsonChanged() {
            root.loadWebShortcuts()
        }
    }

    // ============================================================
    // ACCESOS
    // ============================================================

    property var shortcuts: [
        {
            name: "Steam",
            icon: "steam",
            command: "/usr/games/steam"
        },
        {
            name: "Discord",
            icon: "azuki-discord",
            command: "/snap/bin/discord"
        },
        {
            name: "Brave",
            icon: "brave-browser",
            command: "/usr/bin/brave-browser"
        },
        {
            name: "Capturas",
            icon: "folder-pictures",
            command: "dolphin '/home/azuki505/Imágenes/Capturas de pantalla'"
        },
        {
            name: "Archivos",
            icon: "system-file-manager",
            command: "/usr/bin/nautilus"
        },
        {
            name: "Configuración",
            icon: "settings-configure",
            command: "/usr/bin/systemsettings"
        }
    ]

    // ============================================================
    // INTERFAZ
    // ============================================================

    // Power settings Dialog
    PlasmaCore.Dialog {
        id: powerDialog

        visible: false

        backgroundHints: PlasmaCore.Dialog.NoBackground
        
        flags: Qt.Dialog
            | Qt.FramelessWindowHint
            | Qt.WindowStaysOnTopHint

        // Centrado dinámico
        x: Math.round(
            (Screen.width - width) / 2
        )

        y: Math.round(
            (Screen.height - height) / 2
        )

        mainItem: Rectangle {
            width: 220
            height: 220
            
            focus: true

            Keys.onEscapePressed: {
                powerDialog.visible = false
            }

            radius: 22
            color: "#E61A1D21"

            border.width: 2
            border.color: "#9921CFE0"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Item {
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.Label {
                        text: "ENERGÍA"

                        font.family: "Oxanium"
                        font.pixelSize: 22
                        font.weight: Font.Medium
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "window-close"

                        onClicked: {
                            powerDialog.visible = false
                        }

                        PlasmaComponents.ToolTip {
                            text: "Cerrar"
                        }
                    }
                }

                ////////

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 10

                    PlasmaComponents.Button {
                        text: "Suspender"
                        icon.name: "system-suspend"

                        Layout.preferredWidth: 180

                        onClicked: {
                            root.launchPowerAction("suspend")
                        }
                    }

                    PlasmaComponents.Button {
                        text: "Reiniciar"
                        icon.name: "system-reboot"

                        Layout.preferredWidth: 180

                        onClicked: {
                            root.launchPowerAction("reboot")
                        }
                    }

                    PlasmaComponents.Button {
                        text: "Apagado"
                        icon.name: "system-shutdown"

                        Layout.preferredWidth: 180

                        onClicked: {
                            root.launchPowerAction("shutdown")
                        }
                    }
                }

                //////

                PlasmaComponents.Label {
                    text: "Selecciona una acción"
                    opacity: 0.65

                    font.family: "Exo 2"
                    font.pixelSize: 13

                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // General working flow of widget
    fullRepresentation: Item {
        id: representation

        // Tamaño solicitado inicialmente a Plasma.
        Layout.minimumWidth: 78
        Layout.preferredWidth: 78
        Layout.maximumWidth: 78

        Layout.minimumHeight: 80

        Rectangle {
            id: panel

            anchors {
                top: parent.top
                horizontalCenter: parent.horizontalCenter
            }

            width: 78
            height: quickColumn.height + 28

            radius: 22
            color: "#331A1D21"

            border.width: 1
            border.color: "#6621CFE0"

            Column {
                id: quickColumn

                anchors {
                    top: parent.top
                    topMargin: 14
                    horizontalCenter: parent.horizontalCenter
                }

                spacing: 8

                Repeater {
                    model: root.allShortcuts

                    Item {
                        width: 52
                        height: 52

                        Rectangle {
                            id: buttonBackground

                            anchors.centerIn: parent

                            width: 46
                            height: 46
                            radius: width / 2

                            color: buttonMouse.containsMouse
                                ? "#6621CFE0"
                                : "#44111417"

                            border.width:
                                buttonMouse.containsMouse ? 2 : 1

                            border.color:
                                buttonMouse.containsMouse
                                ? "#21CFE0"
                                : "#4421CFE0"

                            scale:
                                buttonMouse.pressed
                                ? 0.94
                                : buttonMouse.containsMouse
                                    ? 1.10
                                    : 1.0

                            Behavior on scale {
                                NumberAnimation {
                                    duration: 120
                                    easing.type: Easing.OutCubic
                                }
                            }

                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            Behavior on border.color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }

                            Kirigami.Icon {
                                anchors.centerIn: parent

                                width: 28
                                height: 28

                                source:
                                    root.resolveIcon(modelData.icon)
                            }

                            MouseArea {
                                id: buttonMouse

                                anchors.fill: parent

                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor

                                onClicked: {
                                    root.launch(modelData.command)
                                }
                            }

                            PlasmaComponents.ToolTip {
                                visible:
                                    buttonMouse.containsMouse

                                text: modelData.name
                            }
                        }
                    }
                }
            }
        }
    }
}