import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import "TileDefaults.js" as TileDefaults

Item {
    id: page

    readonly property string protocolInstanceId: String(Plasmoid.id)
    property string cfg_libraryJson: ""
    property int cfg_retentionDays: 30

    function committedDraftText() {
        return cfg_libraryJson && cfg_libraryJson.trim() ? cfg_libraryJson : TileDefaults.json
    }

    function saveConfig() {
        // v0.6g.7 keeps the validated v0.6g.4 coordinator byte-identical.
        // The active Preferences session is still fail-closed; policy eligibility
        // is freshly evaluated only after Apply + explicit finalize.
        coordination.prepareApply(committedDraftText())
    }

    function setRetentionDays(days) {
        var n = Math.max(7, Math.min(3650, Number(days)))
        if (n === cfg_retentionDays)
            return
        cfg_retentionDays = n
        coordination.markDirty()
    }

    CoordinationProbe {
        id: coordination
        instanceId: page.protocolInstanceId
        Component.onCompleted: openSession(page.committedDraftText())
    }

    Controls.Dialog {
        id: earlyReviewDialog
        parent: page
        modal: true
        anchors.centerIn: parent
        width: Math.min(page.width - 32, 620)
        title: "Revisión manual anticipada"
        standardButtons: Controls.Dialog.Close

        contentItem: ColumnLayout {
            spacing: 10
            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "v0.6g.7 no borra archivos. Para revisar candidatos anticipados de forma segura, primero pulsa Aplicar, finaliza la sesión de Preferencias y después ejecuta policy_eval.py manual-review desde el paquete v0.6g.7."
            }
            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.75
                text: "La revisión vuelve a capturar coordinación, referencias, respaldos, manifiestos y cuarentena. Incluso con candidatos válidos, deletionAuthorized permanece en false."
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

    Controls.ScrollView {
        anchors.fill: parent
        anchors.topMargin: coordinationWarning.visible ? coordinationWarning.implicitHeight + 8 : 0
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: parent.width
            spacing: 12
            enabled: coordination.editingAllowed

            Controls.Label {
                text: "Mantenimiento y retención"
                font.bold: true
                font.pixelSize: 18
                Layout.fillWidth: true
            }

            Controls.Label {
                text: "Configura cuánto tiempo debe permanecer un archivo en cuarentena antes de convertirse en candidato por tiempo. Cambiar este valor no mueve ni elimina ningún archivo."
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Controls.Frame {
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: 8
                    Controls.Label {
                        text: "Período de retención"
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.SpinBox {
                            id: retentionSpin
                            from: 7
                            to: 3650
                            value: page.cfg_retentionDays
                            editable: true
                            onValueModified: page.setRetentionDays(value)
                        }
                        Controls.Label { text: "días" }
                        Item { Layout.fillWidth: true }
                        Controls.Button {
                            text: "Restablecer a 30"
                            enabled: page.cfg_retentionDays !== 30
                            onClicked: page.setRetentionDays(30)
                        }
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        opacity: 0.72
                        text: "Rango permitido: 7–3650 días. El valor predeterminado es 30. Pulsa Aplicar para guardar el cambio."
                    }
                }
            }

            Controls.Frame {
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: 8
                    Controls.Label {
                        text: "Cuarentena"
                        font.bold: true
                        Layout.fillWidth: true
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Por seguridad, Preferencias no ejecuta una auditoría fresca mientras esta ventana está abierta. El evaluador externo usa el valor ya comprometido y vuelve a comprobar todas las fuentes con Preferencias cerrada."
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Controls.Button {
                            text: "Revisar borrado anticipado…"
                            onClicked: earlyReviewDialog.open()
                        }
                        Controls.Button {
                            text: "Eliminar ahora"
                            enabled: false
                            Controls.ToolTip.visible: hovered
                            Controls.ToolTip.text: "No disponible en v0.6g.7. Esta fase no contiene ejecutor de borrado."
                        }
                        Item { Layout.fillWidth: true }
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Kirigami.Theme.neutralTextColor
                        text: "Un candidato manual anticipado nunca equivale a autorización. La futura acción destructiva deberá pedir una confirmación nueva y repetir la captura inmediatamente antes de borrar."
                    }
                }
            }

            Controls.Frame {
                Layout.fillWidth: true
                contentItem: ColumnLayout {
                    spacing: 6
                    Controls.Label {
                        text: "Estado de esta fase"
                        font.bold: true
                    }
                    Controls.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "• Política configurable: activa\n• Coordinación de Preferencias: activa\n• Elegibilidad fresca: disponible fuera de Preferencias\n• Borrado real: no disponible\n• Autorización de borrado: no disponible"
                    }
                }
            }

            Item { Layout.fillHeight: true; Layout.minimumHeight: 8 }
        }
    }
}
