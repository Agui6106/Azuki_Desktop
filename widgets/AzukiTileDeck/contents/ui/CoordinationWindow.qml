import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support

Item {
    id: host
    property string instanceId: ""
    property bool configuring: false
    property bool ready: false
    property int generation: 0
    property double openedAfterMs: 0
    property string clientId: ""
    property string sessionOpenedAt: ""
    property bool halted: true
    property int bindAttempts: 0
    property int sequence: 0
    property var pending: ({})

    function quote(value) { return "'" + String(value).replace(/'/g, "'\"'\"'") + "'" }
    function fail(message) {
        halted = true
        bindTimer.stop()
        console.warn("AZUKI_WINDOW", "error", message)
    }
    function windowChanged() {
        if (!ready) return
        generation++
        bindTimer.stop()
        if (!configuring && openedAfterMs > 0) {
            request("close-clean", ["--instance", instanceId, "--opened-after-ms",
                                   String(openedAfterMs), "--closed-before-ms", String(Date.now())])
        }
        clientId = ""
        sessionOpenedAt = ""
        halted = !configuring
        bindAttempts = 0
        if (configuring) {
            openedAfterMs = Date.now()
            console.info("AZUKI_WINDOW", "opened")
            // The config page may still be constructing its initial session.
            bindTimer.restart()
        } else {
            console.info("AZUKI_WINDOW", "closed")
        }
    }
    function request(kind, args) {
        if (kind !== "close-clean" && (!configuring || halted)) return
        // Do not overlap operations from the current window generation.
        var keys = Object.keys(pending)
        for (var j = 0; j < keys.length; j++)
            if (pending[keys[j]].generation === generation) return
        var url = Qt.resolvedUrl("../scripts/window_link.py").toString()
        if (url.indexOf("file://") !== 0) { fail("No se encontró window_link.py."); return }
        var cmd = "/usr/bin/python3 -S -B " + quote(decodeURIComponent(url.substring(7))) + " " + kind
        for (var i = 0; i < args.length; i++) cmd += " " + quote(args[i])
        // Each executable source must have a unique command key.
        sequence++
        cmd += " --request-id " + quote(String(generation) + "-" + String(sequence))
        pending[cmd] = {kind:kind, generation:generation, started:Date.now()}
        transport.connectSource(cmd)
    }
    function bindSession() {
        bindAttempts++
        request("bind", ["--instance", instanceId, "--opened-after-ms", String(openedAfterMs)])
    }
    function heartbeat() {
        if (clientId !== "")
            request("pulse", ["--instance", instanceId, "--client-id", clientId, "--opened-at", sessionOpenedAt])
    }
    onConfiguringChanged: windowChanged()
    Component.onCompleted: { ready = true; windowChanged() }

    Plasma5Support.DataSource {
        id: transport
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var task = host.pending[source]
            delete host.pending[source]
            transport.disconnectSource(source)
            if (task && task.kind === "close-clean") {
                var closeReply
                try { closeReply = JSON.parse(data["stdout"] || "") } catch (error) { closeReply = {} }
                if (Number(data["exit code"]) !== 0 || closeReply.ok !== true)
                    console.warn("AZUKI_WINDOW", "close_failed", closeReply.message || "Respuesta inválida.")
                else console.info("AZUKI_WINDOW", "close_ok")
                return
            }
            if (!task || task.generation !== host.generation || !host.configuring || host.halted) return
            var response
            try { response = JSON.parse(data["stdout"] || "") }
            catch (error) { host.fail("Respuesta de coordinación inválida."); return }
            if (Number(data["exit code"]) !== 0 || response.ok !== true) {
                host.fail(response.message || "No se pudo renovar la sesión.")
                return
            }
            if (task.kind === "bind") {
                var result = response.data || {}
                if (result.waiting === true) {
                    if (host.bindAttempts < 12) bindTimer.restart()
                    else host.fail("No se encontró la sesión de esta ventana.")
                    return
                }
                if (typeof result.clientId !== "string" || !/^[A-Za-z0-9._-]{8,160}$/.test(result.clientId)
                        || typeof result.openedAt !== "string") {
                    host.fail("Identidad de sesión inválida.")
                    return
                }
                host.clientId = result.clientId
                host.sessionOpenedAt = result.openedAt
                console.info("AZUKI_WINDOW", "bound")
                host.heartbeat()
            } else {
                console.info("AZUKI_WINDOW", "heartbeat_ok")
            }
        }
    }
    Timer { id: bindTimer; interval: 500; repeat: false; onTriggered: host.bindSession() }
    Timer {
        interval: 5000; repeat: true
        running: host.ready && host.configuring && !host.halted && host.clientId !== ""
        onTriggered: host.heartbeat()
    }
    Timer {
        interval: 1000; repeat: true
        running: host.ready
        onTriggered: {
            var keys = Object.keys(host.pending)
            for (var i = 0; i < keys.length; i++) {
                var task = host.pending[keys[i]]
                if (Date.now() - task.started > 4000) {
                    delete host.pending[keys[i]]
                    if (task.kind === "close-clean")
                        console.warn("AZUKI_WINDOW", "close_timeout")
                    else if (task.generation === host.generation && host.configuring)
                        host.fail("La coordinación excedió el tiempo de espera.")
                    transport.disconnectSource(keys[i])
                }
            }
        }
    }
}
