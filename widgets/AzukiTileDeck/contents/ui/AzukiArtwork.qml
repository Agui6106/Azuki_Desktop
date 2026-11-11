import QtQuick
import QtQuick.Effects

Item {
    id: artwork

    property url source: ""
    property real cornerRadius: 16

    // La imagen se carga solamente cuando el tile tiene artwork.
    Rectangle {
        id: roundedMask
        anchors.fill: parent
        radius: artwork.cornerRadius
        color: "white"
        visible: false
        layer.enabled: true
    }

    Image {
        id: cover
        anchors.fill: parent
        source: artwork.source
        asynchronous: true
        cache: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: 1024
        sourceSize.height: 0
        visible: status === Image.Ready

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: roundedMask
            blurEnabled: false
            shadowEnabled: false
        }
    }

    // Capa oscura estática. No hay blur, timers ni animación continua.
    Rectangle {
        anchors.fill: parent
        radius: artwork.cornerRadius
        visible: cover.status === Image.Ready
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#55101418" }
            GradientStop { position: 1.0; color: "#AA101418" }
        }
    }
}
