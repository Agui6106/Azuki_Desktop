import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: "Accesos locales"
        icon: "applications-all"
        source: "ConfigLocalShortcuts.qml"
    }

    ConfigCategory {
        name: "Accesos web"
        icon: "internet-web-browser"
        source: "ConfigWebShortcuts.qml"
    }
}