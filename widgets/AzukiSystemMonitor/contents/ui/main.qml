import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    preferredRepresentation: fullRepresentation

    function safeNumber(v) {
        var n = Number(v)
        return isNaN(n) ? 0 : n
    }

    function clamp01(v) {
        return Math.max(0, Math.min(1, v))
    }

    function percent01(v) {
        return clamp01(safeNumber(v) / 100.0)
    }

    function bytesToHuman(bytes) {
        var b = safeNumber(bytes)
        var units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var i = 0
        while (b >= 1024 && i < units.length - 1) {
            b /= 1024
            i++
        }
        return b.toFixed(i === 0 ? 0 : 1) + " " + units[i]
    }

    function diskTotalBytes() {
        return safeNumber(diskUsed.value) + safeNumber(diskFree.value)
    }

    function diskUsedRatio() {
        var total = diskTotalBytes()
        if (total <= 0) {
            return 0
        }
        return clamp01(safeNumber(diskUsed.value) / total)
    }

    function vramRatio() {
        var total = safeNumber(vramTotal.value)
        if (total <= 0) {
            return 0
        }
        return clamp01(safeNumber(vramUsed.value) / total)
    }

    // ============================================================
    // SENSORES
    // ============================================================

    Sensors.Sensor {
        id: cpuUsage
        sensorId: "cpu/all/system"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: cpuTemperature
        sensorId: "cpu/all/averageTemperature"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: ramUsage
        sensorId: "memory/physical/usedPercent"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: gpuUsage
        sensorId: "gpu/gpu1/usage"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: gpuTemperature
        sensorId: "gpu/gpu1/temperature"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: vramUsed
        sensorId: "gpu/gpu1/usedVram"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: vramTotal
        sensorId: "gpu/gpu1/totalVram"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: netDownload
        sensorId: "network/all/download"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: netUpload
        sensorId: "network/all/upload"
        updateRateLimit: 1000
    }

    Sensors.Sensor {
        id: diskUsed
        sensorId: "disk/9a4032ce-175f-4a2a-aa7f-5623dd72d97b/used"
        updateRateLimit: 2000
    }

    Sensors.Sensor {
        id: diskFree
        sensorId: "disk/9a4032ce-175f-4a2a-aa7f-5623dd72d97b/free"
        updateRateLimit: 2000
    }

    // ============================================================
    // INTERFAZ
    // ============================================================

    fullRepresentation: Rectangle {
        id: panel

        radius: 14
        color: "#801A1D21"  
        //color: "#3D0000FF"
        border.width: 1
        border.color: "#6621CFE0"

        Layout.minimumWidth: 660
        Layout.preferredWidth: 690
        Layout.maximumWidth: 690

        Layout.minimumHeight: contentColumn.implicitHeight + 24
        Layout.preferredHeight: contentColumn.implicitHeight + 24
        Layout.maximumHeight: contentColumn.implicitHeight + 24

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            PlasmaComponents.Label {
                text: "SYSTEM STATUS"
                font.family: "Oxanium"
                font.pixelSize: 20
                font.weight: Font.Medium
                color: "#F2F5F7"
            }

            GridLayout {
                columns: 3
                rowSpacing: 10
                columnSpacing: 10
                Layout.fillWidth: true

                // CPU
                Rectangle {
                    radius: 10
                    color: "#66111417"
                    border.width: 1
                    border.color: "#3321CFE0"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 210
                    implicitHeight: 92

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        PlasmaComponents.Label {
                            text: "CPU"
                            font.family: "Oxanium"
                            font.pixelSize: 14
                            color: "#21CFE0"
                        }

                        PlasmaComponents.Label {
                            text: cpuUsage.formattedValue + "    " + cpuTemperature.formattedValue
                            font.family: "Exo 2"
                            font.pixelSize: 17
                            color: "#F2F5F7"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: "#3321CFE0"

                            Rectangle {
                                width: parent.width * percent01(cpuUsage.value)
                                height: parent.height
                                radius: 4
                                color: "#21CFE0"
                            }
                        }
                    }
                }

                // RAM
                Rectangle {
                    radius: 10
                    color: "#66111417"
                    border.width: 1
                    border.color: "#3321CFE0"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 210
                    implicitHeight: 92

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        PlasmaComponents.Label {
                            text: "RAM"
                            font.family: "Oxanium"
                            font.pixelSize: 14
                            color: "#21CFE0"
                        }

                        PlasmaComponents.Label {
                            text: ramUsage.formattedValue
                            font.family: "Exo 2"
                            font.pixelSize: 17
                            color: "#F2F5F7"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: "#3321CFE0"

                            Rectangle {
                                width: parent.width * percent01(ramUsage.value)
                                height: parent.height
                                radius: 4
                                color: "#21CFE0"
                            }
                        }
                    }
                }

                // RED

                // RED
                Rectangle {
                    radius: 10
                    color: "#66111417"
                    border.width: 1
                    border.color: "#3321CFE0"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 210
                    implicitHeight: 92

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        PlasmaComponents.Label {
                            text: "RED"
                            font.family: "Oxanium"
                            font.pixelSize: 14
                            color: "#21CFE0"
                        }

                        PlasmaComponents.Label {
                            text: "↓ " + netDownload.formattedValue
                            font.family: "Exo 2"
                            font.pixelSize: 16
                            color: "#F2F5F7"
                        }

                        PlasmaComponents.Label {
                            text: "↑ " + netUpload.formattedValue
                            font.family: "Exo 2"
                            font.pixelSize: 16
                            color: "#F2F5F7"
                        }
                    }
                }

                // GPU
                Rectangle {
                    radius: 10
                    color: "#66111417"
                    border.width: 1
                    border.color: "#3321CFE0"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 210
                    implicitHeight: 92

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        PlasmaComponents.Label {
                            text: "GPU"
                            font.family: "Oxanium"
                            font.pixelSize: 14
                            color: "#21CFE0"
                        }

                        PlasmaComponents.Label {
                            text: gpuUsage.formattedValue + "    " + gpuTemperature.formattedValue
                            font.family: "Exo 2"
                            font.pixelSize: 17
                            color: "#F2F5F7"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: "#3321CFE0"

                            Rectangle {
                                width: parent.width * percent01(gpuUsage.value)
                                height: parent.height
                                radius: 4
                                color: "#21CFE0"
                            }
                        }
                    }
                }

                // VRAM
                Rectangle {
                    radius: 10
                    color: "#66111417"
                    border.width: 1
                    border.color: "#3321CFE0"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 210
                    implicitHeight: 92

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        PlasmaComponents.Label {
                            text: "VRAM"
                            font.family: "Oxanium"
                            font.pixelSize: 14
                            color: "#21CFE0"
                        }

                        PlasmaComponents.Label {
                            text: vramUsed.formattedValue + " / " + vramTotal.formattedValue
                            font.family: "Exo 2"
                            font.pixelSize: 15
                            color: "#F2F5F7"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: "#3321CFE0"

                            Rectangle {
                                width: parent.width * vramRatio()
                                height: parent.height
                                radius: 4
                                color: "#21CFE0"
                            }
                        }
                    }
                }

                // NVMe
                Rectangle {
                    radius: 10
                    color: "#66111417"
                    border.width: 1
                    border.color: "#3321CFE0"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 210
                    implicitHeight: 92

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6

                        PlasmaComponents.Label {
                            text: "NVMe"
                            font.family: "Oxanium"
                            font.pixelSize: 14
                            color: "#21CFE0"
                        }

                        PlasmaComponents.Label {
                            text: bytesToHuman(diskUsed.value) + " / " + bytesToHuman(diskTotalBytes())
                            font.family: "Exo 2"
                            font.pixelSize: 15
                            color: "#F2F5F7"
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 8
                            radius: 4
                            color: "#3321CFE0"

                            Rectangle {
                                width: parent.width * diskUsedRatio()
                                height: parent.height
                                radius: 4
                                color: "#21CFE0"
                            }
                        }
                    }
                }
            }
        }
    }
}