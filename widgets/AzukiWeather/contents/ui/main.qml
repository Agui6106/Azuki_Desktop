import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    preferredRepresentation: fullRepresentation

    property int currentCityIndex: 0

    property string cityQuery: cities[currentCityIndex].query

    property string adminArea: ""
    property string countryName: ""

    property string cityName: "Cargando..."
    property real latitude: 0
    property real longitude: 0

    readonly property string displayLocation:
        cities.length > 0 && cities[currentCityIndex]
        ? cities[currentCityIndex].label
        : "Sin ciudad"

    property string temperature: "--"
    property string condition: "--"
    property string minimumTemperature: "--"
    property string maximumTemperature: "--"

    // Local time
    property string localTime: "--:--"
    property string timezoneName: ""
    property int utcOffsetSeconds: 0

    // Cities
    property var cities: []

    function loadCities() {
        try {
            var parsed = JSON.parse(Plasmoid.configuration.citiesJson)

            if (Array.isArray(parsed) && parsed.length > 0) {
                cities = parsed
            } else {
                cities = []
            }

        } catch (e) {
            console.log(
                "Azuki Weather: error leyendo ciudades:",
                e
            )

            cities = []
        }
    }

    function nextCity() {
        currentCityIndex =
            (currentCityIndex + 1) % cities.length

        changeCity()
    }

    function previousCity() {
        currentCityIndex =
            (currentCityIndex - 1 + cities.length) % cities.length

        changeCity()
    }

    function changeCity() {
        if (cities.length === 0)
            return

        var city = cities[currentCityIndex]

        cityQuery = city.query

        cityName = "Cargando..."
        adminArea = ""
        countryName = ""

        temperature = "--"
        condition = "--"
        minimumTemperature = "--"
        maximumTemperature = "--"

        if (city.latitude &&
            city.longitude &&
            city.latitude !== 0 &&
            city.longitude !== 0) {

            latitude = city.latitude
            longitude = city.longitude

            loadWeather()

        } else {
            findCity()
        }
    }

    function shortAdminName(name) {
        if (!name)
            return ""

        var result = name.trim()

        var prefixes = [
            "Estado de ",
            "Provincia de ",
            "Región de ",
            "Region de ",
            "Departamento de ",
            "Distrito de ",
            "Prefectura de "
        ]

        for (var i = 0; i < prefixes.length; i++) {
            if (result.startsWith(prefixes[i])) {
                result = result.substring(prefixes[i].length)
                break
            }
        }

        // Normalizaciones conocidas de nombres administrativos
        var aliases = {
            "Veracruz-Llave": "Veracruz",
            "México": "Estado de México"
        }

        if (aliases[result])
            result = aliases[result]

        return result
    }

    function weatherDescription(code) {
        switch (code) {
        case 0:
            return "Despejado"
        case 1:
        case 2:
            return "Parcialmente nublado"
        case 3:
            return "Nublado"
        case 45:
        case 48:
            return "Niebla"
        case 51:
        case 53:
        case 55:
            return "Llovizna"
        case 61:
        case 63:
        case 65:
            return "Lluvia"
        case 71:
        case 73:
        case 75:
            return "Nieve"
        case 80:
        case 81:
        case 82:
            return "Chubascos"
        case 95:
        case 96:
        case 99:
            return "Tormenta"
        default:
            return "Condición desconocida"
        }
    }

    function findCity() {
        var xhr = new XMLHttpRequest()

        var url =
            "https://geocoding-api.open-meteo.com/v1/search" +
            "?name=" + encodeURIComponent(cityQuery) +
            "&count=1" +
            "&language=es" +
            "&format=json"

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var data = JSON.parse(xhr.responseText)

                    if (data.results && data.results.length > 0) {
                        var place = data.results[0]

                        cityName = place.name
                        latitude = place.latitude
                        longitude = place.longitude

                        adminArea = place.admin1 || ""
                        countryName = place.country || ""

                        loadWeather()
                
                    } else {
                        cityName = "Ciudad no encontrada"
                    }
                } else {
                    cityName = "Error de ubicación"
                }
            }
        }

        xhr.open("GET", url)
        xhr.send()
    }

    function loadWeather() {
        var xhr = new XMLHttpRequest()

        var url =
            "https://api.open-meteo.com/v1/forecast" +
            "?latitude=" + latitude +
            "&longitude=" + longitude +
            "&current=temperature_2m,weather_code" +
            "&daily=temperature_2m_max,temperature_2m_min" +
            "&timezone=auto" +
            "&forecast_days=1"

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    var data = JSON.parse(xhr.responseText)

                    temperature =
                        Math.round(data.current.temperature_2m) + "°C"

                    condition =
                        weatherDescription(data.current.weather_code)

                    maximumTemperature =
                        Math.round(data.daily.temperature_2m_max[0]) + "°"

                    minimumTemperature =
                        Math.round(data.daily.temperature_2m_min[0]) + "°"

                    // Local time
                    timezoneName = data.timezone || ""
                    utcOffsetSeconds = data.utc_offset_seconds || 0
                    
                    updateLocalTime()



                } else {
                    condition = "Error al obtener clima"
                }
            }
        }

        xhr.open("GET", url)
        xhr.send()
    }

    function updateLocalTime() {
        var nowUtcMs = Date.now()

        var localMs =
            nowUtcMs +
            (utcOffsetSeconds * 1000)

        var localDate = new Date(localMs)

        var hours = localDate.getUTCHours()
        var minutes = localDate.getUTCMinutes()

        var hh = hours < 10 ? "0" + hours : hours
        var mm = minutes < 10 ? "0" + minutes : minutes

        localTime = hh + ":" + mm
    }

    // For weather
    Timer {
        interval: 15 * 60 * 1000
        repeat: true
        running: true

        onTriggered: loadWeather()
    }

    // For Local time
    Timer {
        interval: 30 * 1000
        repeat: true
        running: true

        onTriggered: updateLocalTime()
    }

    Component.onCompleted: {
        loadCities()

        if (cities.length > 0) {
            currentCityIndex = 0
            changeCity()
        }
    }

    Connections {
        target: Plasmoid.configuration

        function onCitiesJsonChanged() {
            console.log("Azuki Weather: configuración de ciudades modificada")

            var previousIndex = currentCityIndex

            loadCities()

            if (cities.length === 0) {
                currentCityIndex = 0
                return
            }

            if (previousIndex >= cities.length)
                currentCityIndex = cities.length - 1
            else
                currentCityIndex = previousIndex

            changeCity()
        }
    }

    fullRepresentation: Rectangle {
        radius: 14

        color: "#661A1D21"

        border.width: 1
        border.color: "#6621CFE0"

        Layout.minimumWidth: 300
        Layout.preferredWidth: 320
        Layout.maximumWidth: 320

        Layout.minimumHeight: 170
        Layout.preferredHeight: 170
        Layout.maximumHeight: 170

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14

            spacing: 8

            PlasmaComponents.Label {
                text: "WEATHER"

                font.family: "Oxanium"
                font.pixelSize: 20
                font.weight: Font.Medium
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.ToolButton {
                    text: "‹"
                    font.pixelSize: 24

                    onClicked: previousCity()
                }

                PlasmaComponents.Label {
                    text: displayLocation

                    font.family: "Exo 2"
                    font.pixelSize: 15
                    color: "#21CFE0"

                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true

                    Layout.minimumWidth: 0

                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                PlasmaComponents.ToolButton {
                    text: "›"
                    font.pixelSize: 24

                    onClicked: nextCity()
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: 12
                spacing: 6

                Repeater {
                    model: cities.length

                    Item {
                        width: 12
                        height: 12

                        Rectangle {
                            anchors.centerIn: parent

                            width: index === currentCityIndex ? 10 : 7
                            height: width
                            radius: width / 2

                            color: index === currentCityIndex
                                ? "#21CFE0"
                                : "#66777A80"
                        }
                    }
                }
            }

            RowLayout {
                spacing: 16

                PlasmaComponents.Label {
                    text: temperature

                    font.family: "Oxanium"
                    font.pixelSize: 36
                    font.weight: Font.Medium
                }

                PlasmaComponents.Label {
                    text: condition

                    font.family: "Exo 2"
                    font.pixelSize: 16

                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }
            }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text:
                        "Mín " + minimumTemperature +
                        "    Máx " + maximumTemperature

                    font.family: "Exo 2"
                    font.pixelSize: 15
                }

                Item {
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    text: localTime + " Hrs"

                    font.family: "Exo 2"
                    font.pixelSize: 15
                    color: "#21CFE0"
                }
            }
        }
    }
}

