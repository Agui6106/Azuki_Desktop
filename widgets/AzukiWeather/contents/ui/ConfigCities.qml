import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root

    /*
     * Plasma guarda esta propiedad en citiesJson.
     *
     * No enlazamos directamente el texto de ningún control.
     * En su lugar generamos el JSON a partir del ListModel.
     */
    property string cfg_citiesJson: "[]"

    property bool loadingConfiguration: false
    property int selectedIndex: -1

    property bool searchVisible: false
    property bool searchInProgress: false
    property string searchError: ""

    ListModel {
        id: citiesModel
    }

    ListModel {
        id: searchResultsModel
    }

    /*
     * ============================================================
     * JSON → MODELO
     * ============================================================
     */

    function loadCities() {
        loadingConfiguration = true

        citiesModel.clear()

        try {
            var data = JSON.parse(cfg_citiesJson)

            if (Array.isArray(data)) {
                for (var i = 0; i < data.length; i++) {
                    citiesModel.append({
                        query: data[i].query || "",
                        label: data[i].label || "",
                        latitude: data[i].latitude || 0,
                        longitude: data[i].longitude || 0
                    })
                }
            }
        } catch (e) {
            console.log(
                "Azuki Weather Config: error leyendo ciudades:",
                e
            )
        }

        selectedIndex = citiesModel.count > 0 ? 0 : -1

        loadingConfiguration = false
    }

    /*
     * ============================================================
     * MODELO → JSON
     * ============================================================
     */

    function saveCities() {
        if (loadingConfiguration)
            return

        var data = []

        for (var i = 0; i < citiesModel.count; i++) {
            var city = citiesModel.get(i)

            data.push({
                query: city.query,
                label: city.label,
                latitude: city.latitude,
                longitude: city.longitude
            })
        }

        cfg_citiesJson = JSON.stringify(data)
    }

    /*
     * ============================================================
     * ACCIONES
     * ============================================================
     */

    function searchCity(searchText) {
        var text = searchText.trim()

        if (text.length < 2) {
            searchError = "Escribe al menos 2 caracteres."
            return
        }

        searchResultsModel.clear()
        searchError = ""
        searchInProgress = true

        var xhr = new XMLHttpRequest()

        var url =
            "https://geocoding-api.open-meteo.com/v1/search" +
            "?name=" + encodeURIComponent(text) +
            "&count=8" +
            "&language=es" +
            "&format=json"

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            searchInProgress = false

            if (xhr.status !== 200) {
                searchError = "No se pudo consultar Open-Meteo."
                return
            }

            try {
                var data = JSON.parse(xhr.responseText)

                if (!data.results || data.results.length === 0) {
                    searchError = "No se encontraron ciudades."
                    return
                }

                for (var i = 0; i < data.results.length; i++) {
                    var place = data.results[i]

                    var label = buildLocationLabel(place)

                    searchResultsModel.append({
                        cityName: place.name || "",
                        adminArea: place.admin1 || "",
                        countryName: place.country || "",
                        countryCode: place.country_code || "",
                        latitude: place.latitude || 0,
                        longitude: place.longitude || 0,
                        label: label
                    })
                }
            } catch (e) {
                searchError = "Error leyendo la respuesta."
                console.log("Azuki Weather Config:", e)
            }
        }

        xhr.open("GET", url)
        xhr.send()
    }
    
    function buildLocationLabel(place) {
        var city = place.name || ""
        var admin = place.admin1 || ""
        var country = place.country || ""

        // Evitamos repeticiones tipo "Seúl, Seúl"
        if (admin === city)
            admin = ""

        if (admin !== "" && country !== "")
            return city + ", " + admin + ", " + country

        if (country !== "")
            return city + ", " + country

        return city
    }

    function addSearchResult(resultIndex) {
        if (resultIndex < 0 ||
            resultIndex >= searchResultsModel.count)
            return

        var place = searchResultsModel.get(resultIndex)

        /*
        * La query utiliza el nombre + país para que Open-Meteo
        * pueda encontrar nuevamente la ciudad desde main.qml.
        */
        var query =
            place.cityName +
            (place.countryName !== ""
                ? ", " + place.countryName
                : "")

        citiesModel.append({
            query: query,
            label: place.label,
            latitude: place.latitude,
            longitude: place.longitude
        })

        selectedIndex = citiesModel.count - 1
        cityList.currentIndex = selectedIndex

        saveCities()

        searchVisible = false
        searchResultsModel.clear()
        searchField.text = ""
    }




    function addCity() {
        citiesModel.append({
            query: "Nueva ciudad, País",
            label: "Nueva ciudad, País"
        })

        selectedIndex = citiesModel.count - 1
        cityList.currentIndex = selectedIndex

        saveCities()
    }

    function removeCity() {
        if (selectedIndex < 0 ||
            selectedIndex >= citiesModel.count)
            return

        citiesModel.remove(selectedIndex)

        if (citiesModel.count === 0) {
            selectedIndex = -1
        } else if (selectedIndex >= citiesModel.count) {
            selectedIndex = citiesModel.count - 1
        }

        cityList.currentIndex = selectedIndex

        saveCities()
    }

    function moveUp() {
        if (selectedIndex <= 0)
            return

        citiesModel.move(
            selectedIndex,
            selectedIndex - 1,
            1
        )

        selectedIndex--
        cityList.currentIndex = selectedIndex

        saveCities()
    }

    function moveDown() {
        if (selectedIndex < 0 ||
            selectedIndex >= citiesModel.count - 1)
            return

        citiesModel.move(
            selectedIndex,
            selectedIndex + 1,
            1
        )

        selectedIndex++
        cityList.currentIndex = selectedIndex

        saveCities()
    }

    /*
     * Plasma establece cfg_citiesJson después de crear la página.
     * Cuando cambie, reconstruimos el modelo.
     */
    onCfg_citiesJsonChanged: {
        if (!loadingConfiguration)
            loadCities()
    }

    Component.onCompleted: loadCities()

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        Label {
            text: "Ciudades guardadas"

            font.bold: true
            font.pixelSize: 18
        }

        Label {
            text:
                "La consulta se utiliza para encontrar la ciudad en " +
                "Open-Meteo. El nombre mostrado es el texto que " +
                "aparecerá en Azuki Weather."

            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        ListView {
            id: cityList

            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 220

            clip: true

            model: citiesModel
            currentIndex: selectedIndex

            delegate: ItemDelegate {
                width: ListView.view.width
                height: 58

                highlighted:
                    index === root.selectedIndex

                contentItem: Column {
                    spacing: 2

                    Label {
                        text: model.label

                        font.bold: true
                        elide: Text.ElideRight

                        width: parent.width
                    }

                    Label {
                        text: model.query

                        opacity: 0.65
                        elide: Text.ElideRight

                        width: parent.width
                    }
                }

                onClicked: {
                    root.selectedIndex = index
                    cityList.currentIndex = index
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true

            Button {
                text: "+ Agregar"

                onClicked: {
                    root.searchVisible = !root.searchVisible

                    if (root.searchVisible)
                        searchField.forceActiveFocus()
                }
            }

            Button {
                text: "Eliminar"

                enabled: root.selectedIndex >= 0

                onClicked: root.removeCity()
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                text: "↑ Subir"

                enabled: root.selectedIndex > 0

                onClicked: root.moveUp()
            }

            Button {
                text: "↓ Bajar"

                enabled:
                    root.selectedIndex >= 0 &&
                    root.selectedIndex <
                    citiesModel.count - 1

                onClicked: root.moveDown()
            }
        }

        Frame {
            Layout.fillWidth: true
            visible: root.searchVisible

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Label {
                    text: "Agregar ciudad"
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true

                    TextField {
                        id: searchField

                        Layout.fillWidth: true

                        placeholderText:
                            "Ej. Tokyo, Querétaro, Berlin..."

                        onAccepted: {
                            root.searchCity(text)
                        }
                    }

                    Button {
                        text: "Buscar"

                        enabled:
                            !root.searchInProgress &&
                            searchField.text.trim().length >= 2

                        onClicked: {
                            root.searchCity(searchField.text)
                        }
                    }
                }

                Label {
                    visible: root.searchInProgress
                    text: "Buscando..."
                    opacity: 0.7
                }

                Label {
                    visible: root.searchError !== ""
                    text: root.searchError
                    color: "#E57373"
                }

                ListView {
                    id: searchResultsList

                    visible: searchResultsModel.count > 0

                    Layout.fillWidth: true
                    Layout.preferredHeight:
                        Math.min(contentHeight, 250)

                    clip: true

                    model: searchResultsModel

                    delegate: ItemDelegate {
                        width: ListView.view.width
                        height: 52

                        contentItem: Column {
                            spacing: 2

                            Label {
                                text: model.label
                                font.bold: true

                                width: parent.width
                                elide: Text.ElideRight
                            }

                            Label {
                                text:
                                    Number(model.latitude).toFixed(2) +
                                    ", " +
                                    Number(model.longitude).toFixed(2)

                                opacity: 0.6
                                font.pixelSize: 12
                            }
                        }

                        onClicked: {
                            root.addSearchResult(index)
                        }
                    }
                }
            }
        }



        Frame {
            Layout.fillWidth: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                Label {
                    text: "Editar ciudad"
                    font.bold: true
                }

                Label {
                    text: "Consulta de Open-Meteo"
                }

                TextField {
                    id: queryField

                    Layout.fillWidth: true

                    enabled: root.selectedIndex >= 0

                    text:
                        root.selectedIndex >= 0 &&
                        root.selectedIndex < citiesModel.count
                        ? citiesModel.get(
                              root.selectedIndex
                          ).query
                        : ""

                    placeholderText:
                        "Ej. Santiago de Queretaro, Mexico"

                    onEditingFinished: {
                        if (root.selectedIndex < 0)
                            return

                        citiesModel.setProperty(
                            root.selectedIndex,
                            "query",
                            text
                        )

                        root.saveCities()
                    }
                }

                Label {
                    text: "Nombre mostrado"
                }

                TextField {
                    id: labelField

                    Layout.fillWidth: true

                    enabled: root.selectedIndex >= 0

                    text:
                        root.selectedIndex >= 0 &&
                        root.selectedIndex < citiesModel.count
                        ? citiesModel.get(
                              root.selectedIndex
                          ).label
                        : ""

                    placeholderText:
                        "Ej. Querétaro, Mexico"

                    onEditingFinished: {
                        if (root.selectedIndex < 0)
                            return

                        citiesModel.setProperty(
                            root.selectedIndex,
                            "label",
                            text
                        )

                        root.saveCities()
                    }
                }
            }
        }
    }
}