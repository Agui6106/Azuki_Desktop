import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Controls.Frame {
    id: notice
    property string protocolState: ""
    property string details: ""
    visible: protocolState === "error" || protocolState === "orphaned" || protocolState === "closed"
    z: 10
    padding: 8
    contentItem: Column {
        spacing: 4
        Controls.Label {
            width: parent.width
            text: "No se puede editar esta configuración"
            font.bold: true
            color: Kirigami.Theme.negativeTextColor
            wrapMode: Text.WordWrap
        }
        Controls.Label {
            width: parent.width
            text: notice.details
            wrapMode: Text.WordWrap
        }
    }
}
