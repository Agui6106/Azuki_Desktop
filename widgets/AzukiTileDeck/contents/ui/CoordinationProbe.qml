import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "CoordinationSession.js" as CoordinationSession

Item {
    id: probe
    property string instanceId: ""
    readonly property string clientId: CoordinationSession.clientId()
    property string protocolState: "opening"
    property string message: "Abriendo coordinación segura…"
    property bool dirty: false
    property bool requestInFlight: false
    property int verifyAttempts: 0
    property string deferredApply: ""
    property int deferredAttempts: 0
    property bool deferredDirtyBare: false
    property string deferredDirtyExpected: ""
    readonly property bool editingAllowed: protocolState !== "opening" && protocolState !== "error" && protocolState !== "orphaned" && protocolState !== "closed"

    function shellQuote(text) { return "'" + String(text).replace(/'/g, "'\\\"'\\\"'") + "'" }
    function scriptPath() {
        var url=Qt.resolvedUrl("../scripts/coordination_guard.py").toString()
        return url.indexOf("file://")===0 ? decodeURIComponent(url.substring(7)) : ""
    }
    function encoded(text) { return encodeURIComponent(String(text)).replace(/[!'()*]/g,function(c){return "%"+c.charCodeAt(0).toString(16).toUpperCase()}) }
    function run(kind,args) {
        var path=scriptPath()
        if (!path) { protocolState="error"; message="No se encontró el coordinador de Azuki."; return }
        var cmd="/usr/bin/python3 -B "+shellQuote(path)+" "+kind
        for (var i=0;i<args.length;i++) cmd+=" "+shellQuote(args[i])
        pending[cmd]=kind
        if (kind!=="heartbeat") requestInFlight=true
        executable.connectSource(cmd)
    }
    function openSession(expected) {
        run("open",["--instance",instanceId,"--client-id",clientId,"--expected-encoded",encoded(expected)])
    }
    function markDirty(expected) {
        if (!editingAllowed) return
        var hasExpected=expected!==undefined && String(expected)!==""
        dirty=true
        protocolState="dirty"
        message="Borrador detectado: mantenimiento bloqueado."
        if (requestInFlight) {
            if (hasExpected) deferredDirtyExpected=String(expected)
            else deferredDirtyBare=true
            deferredDirtyTimer.restart()
            return
        }
        var args=["--instance",instanceId,"--client-id",clientId]
        if (hasExpected) args.push("--expected-encoded",encoded(expected))
        run("dirty",args)
    }
    function prepareApply(expected) {
        if (!editingAllowed) return
        if (requestInFlight || deferredDirtyBare || deferredDirtyExpected!=="") {
            deferredApply=String(expected); deferredAttempts=0
            if (deferredDirtyBare || deferredDirtyExpected!=="") deferredDirtyTimer.restart()
            deferredApplyTimer.restart(); return
        }
        deferredApply=""; verifyAttempts=0
        run("prepare-apply",["--instance",instanceId,"--client-id",clientId,"--expected-encoded",encoded(expected)])
    }
    function verifyApply() {
        if (protocolState==="error" || protocolState==="orphaned") return
        run("verify-apply",["--instance",instanceId,"--client-id",clientId])
    }
    function heartbeat() {
        if (editingAllowed && !requestInFlight)
            run("heartbeat",["--instance",instanceId,"--client-id",clientId])
    }

    property var pending: ({})
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName,data) {
            executable.disconnectSource(sourceName)
            var kind=pending[sourceName]; delete pending[sourceName]
            if (!kind) return
            if (kind!=="heartbeat") requestInFlight=false
            var payload
            try { payload=JSON.parse(data["stdout"]||"") }
            catch(e) { protocolState="error"; message="El coordinador no devolvió JSON válido."; return }
            if (Number(data["exit code"])!==0 || payload.ok!==true) {
                protocolState="error"; message=payload.message||"La coordinación de Preferencias falló."; return
            }
            var result=payload.data||{}
            if (kind==="open") {
                protocolState=result.state||"clean"; dirty=result.dirty===true
                message="Coordinación activa. El mantenimiento permanece bloqueado mientras Preferencias esté abierta."
            } else if (kind==="dirty") {
                protocolState="dirty"; dirty=true; message="Borrador detectado: mantenimiento bloqueado."
                if (deferredApply!=="") deferredApplyTimer.restart()
            } else if (kind==="prepare-apply") {
                protocolState="applying"; dirty=true; message="Aplicar solicitado; verificando persistencia en KConfig."
                verifyTimer.restart()
            } else if (kind==="verify-apply") {
                if (result.verified===true) {
                    protocolState="clean"; dirty=false; verifyAttempts=0
                    message="Aplicación verificada. Finaliza la edición segura antes de cerrar Preferencias."
                } else {
                    verifyAttempts++
                    if (verifyAttempts<8) verifyTimer.restart()
                    else { protocolState="error"; message="No se pudo verificar la persistencia después de Aplicar." }
                }
            } else if (kind==="heartbeat") {
                protocolState=result.state||protocolState; dirty=result.dirty===true
                if (protocolState==="orphaned") message="La sesión quedó huérfana; se requiere reconciliación."
            }
        }
    }
    Timer { interval:5000; repeat:true; running:probe.editingAllowed; onTriggered:probe.heartbeat() }
    Timer { id:verifyTimer; interval:500; repeat:false; onTriggered:probe.verifyApply() }
    Timer {
        id:deferredDirtyTimer; interval:80; repeat:false
        onTriggered: {
            if (!probe.editingAllowed) return
            if (probe.requestInFlight) { restart(); return }
            if (probe.deferredDirtyExpected!=="") {
                var value=probe.deferredDirtyExpected
                probe.deferredDirtyExpected=""
                probe.deferredDirtyBare=false
                probe.markDirty(value)
            } else if (probe.deferredDirtyBare) {
                probe.deferredDirtyBare=false
                probe.markDirty()
            }
        }
    }
    Timer {
        id:deferredApplyTimer; interval:100; repeat:false
        onTriggered: {
            if (probe.deferredApply==="") return
            if (!probe.requestInFlight && !probe.deferredDirtyBare && probe.deferredDirtyExpected==="") {
                var v=probe.deferredApply; probe.deferredApply=""; probe.prepareApply(v)
            } else {
                probe.deferredAttempts++
                if (probe.deferredAttempts<30) restart()
                else { probe.protocolState="error"; probe.message="No se pudo iniciar la verificación de Aplicar." }
            }
        }
    }
}
