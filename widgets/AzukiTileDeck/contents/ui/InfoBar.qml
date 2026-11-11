import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents

Rectangle {
    id: infoBar

    property bool hasSelection: false

    property string title: ""
    property string description: ""
    property string metadata: ""

    property string actionLabel: "ABRIR"
    property bool actionEnabled: false

    // Icon 
    property string actionIconName: "system-run"

    signal actionRequested()

    radius: 12
    color: "#55111417"

    RowLayout {
        anchors.fill: parent

        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 8
        anchors.bottomMargin: 8

        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            spacing: 2

            // Default or Ttile Text
            Text {
                Layout.fillWidth: true
                
                text:
                    infoBar.hasSelection
                    ? infoBar.title
                    : "Selecciona una aplicación"

                color:
                    infoBar.hasSelection
                    ? "#F2F2F2"
                    : "#BFC5C8"

                font.family:
                    infoBar.hasSelection
                    ? "Oxanium"
                    : "Exo 2"

                font.pixelSize:
                    infoBar.hasSelection
                    ? 17
                    : 18

                font.weight:
                    infoBar.hasSelection
                    ? Font.Medium
                    : Font.Normal

                elide: Text.ElideRight
            }

            // App MetaData
            Text {
                Layout.fillWidth: true

                visible:
                    infoBar.hasSelection
                    && infoBar.metadata !== ""

                text: infoBar.metadata

                color: "#21CFE0"

                font.family: "Exo 2"
                font.pixelSize: 15

                elide: Text.ElideRight
            }

            // App Desc.
            Text {
                Layout.fillWidth: true

                visible:
                    infoBar.hasSelection
                    && infoBar.description !== ""

                text: infoBar.description

                color: "#BFC5C8"

                font.family: "Exo 2"
                font.pixelSize: 16

                elide: Text.ElideRight
            }
        }

        PlasmaComponents.Button {
            visible: infoBar.hasSelection

            Layout.preferredWidth: 105
            Layout.preferredHeight: 38

            text: infoBar.actionLabel

            icon.name: infoBar.actionIconName

            enabled: infoBar.actionEnabled

            onClicked: {
                infoBar.actionRequested()
            }
        }
    }
}

