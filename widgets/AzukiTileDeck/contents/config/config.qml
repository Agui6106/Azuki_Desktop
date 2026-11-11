import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Elementos"
        icon: "view-grid"
        source: "ConfigTiles.qml"
    }
    ConfigCategory {
        name: "Buscar juegos"
        icon: "search"
        source: "ConfigRawg.qml"
    }
    ConfigCategory {
        name: "Imágenes"
        icon: "image-x-generic"
        source: "ConfigArtwork.qml"
    }
    ConfigCategory {
        name: "Mantenimiento"
        icon: "tools"
        source: "ConfigMaintenance.qml"
    }
}
