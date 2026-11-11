#!/usr/bin/env python3
"""Fail-closed coordination state for the real Azuki Tile Deck preferences.

This program NEVER deletes, moves, restores, quarantines or writes artwork.
It only reads Plasma KConfig and maintains a private coordination state.
"""
import argparse, fcntl, hashlib, json, os, re, secrets, stat, subprocess, sys, time
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import unquote
import maintenance_reservation as maint

SCHEMA=1
PLUGIN_ID="com.azuki.desktop.tiledeck"
STALE_SECONDS=20.0
MAX_LIBRARY=2*1024*1024
INSTANCE=re.compile(r"^[0-9]{1,12}$")
CLIENT=re.compile(r"^[A-Za-z0-9._-]{8,160}$")
CONFIG=Path.home()/".config/plasma-org.kde.plasma.desktop-appletsrc"
PACKAGE_ROOT=Path(__file__).resolve().parents[2]
DEFAULT=PACKAGE_ROOT/"contents/data/default-library.json"
STATE_BASE=Path(os.environ.get("XDG_STATE_HOME") or Path.home()/".local/state")
STATE_ROOT=STATE_BASE/"azuki-tile-deck"/"coordination"
STATE=STATE_ROOT/"state.json"
LOCK=STATE_ROOT/"lock"
MAINTENANCE=STATE_ROOT/"maintenance-reservation.json"

class CoordinationError(Exception): pass
def require(c,m):
    if not c: raise CoordinationError(m)
def sha(data):
    if isinstance(data,str): data=data.encode()
    return hashlib.sha256(data).hexdigest()
def now_ts(): return time.time()
def now_iso(): return datetime.now(timezone.utc).isoformat()

def _strict_object(pairs):
    out={}
    for k,v in pairs:
        require(k not in out,"Biblioteca con claves JSON duplicadas.")
        out[k]=v
    return out

def parse_library(text,label="Biblioteca"):
    require(isinstance(text,str),label+" inválida.")
    try:
        obj=json.loads(text,object_pairs_hook=_strict_object,
                       parse_constant=lambda v: (_ for _ in ()).throw(ValueError("constante JSON inválida: "+v)))
    except (json.JSONDecodeError,ValueError) as exc:
        raise CoordinationError(label+" inválida: "+str(exc)) from exc
    require(type(obj) is dict and obj.get("schemaVersion")==1 and type(obj.get("items")) is list,
            label+" inválida.")
    return obj

def _norm(value):
    if type(value) is float and value.is_integer(): return int(value)
    if type(value) is list: return [_norm(v) for v in value]
    if type(value) is dict: return {k:_norm(v) for k,v in value.items()}
    return value
def canonical_library(text):
    return json.dumps(_norm(parse_library(text)),sort_keys=True,ensure_ascii=False,separators=(",",":"))
def library_sha(text): return sha(canonical_library(text))

def safe_dir(path,create=False):
    path=Path(path).absolute()
    if create:
        path.mkdir(parents=True,exist_ok=True,mode=0o700)
        os.chmod(path,0o700)
    cur=Path(path.anchor)
    for part in path.parts[1:]:
        cur=cur/part
        st=cur.lstat()
        require(stat.S_ISDIR(st.st_mode),"Ruta no regular: "+str(cur))
    st=path.lstat()
    require(st.st_uid==os.getuid() and not st.st_mode&0o077,
            "La carpeta privada debe pertenecer al usuario y tener permisos 700: "+str(path))
    return path

def read_regular(path,limit):
    path=Path(path); st=path.lstat()
    require(stat.S_ISREG(st.st_mode) and st.st_uid==os.getuid() and st.st_nlink==1 and not st.st_mode&0o022,
            "Archivo no regular, compartido o con permisos inseguros: "+str(path))
    require(0<=st.st_size<=limit,"Archivo excesivo: "+str(path))
    fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_CLOEXEC)
    try:
        before=os.fstat(fd); chunks=[]; total=0
        while total<=limit:
            chunk=os.read(fd,min(65536,limit+1-total))
            if not chunk: break
            chunks.append(chunk); total+=len(chunk)
        data=b"".join(chunks); after=os.fstat(fd)
        require(before.st_ino==after.st_ino and before.st_dev==after.st_dev and before.st_size==len(data)
                and before.st_mtime_ns==after.st_mtime_ns and before.st_ctime_ns==after.st_ctime_ns,
                "Archivo cambió durante la lectura: "+str(path))
        return data
    finally: os.close(fd)

def atomic_write(path,data):
    safe_dir(Path(path).parent)
    tmp=Path(path).parent/(".new-"+secrets.token_hex(12))
    fd=os.open(tmp,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_CLOEXEC,0o600)
    try:
        with os.fdopen(fd,"wb") as f:
            fd=-1; f.write(data); f.flush(); os.fsync(f.fileno())
        os.replace(tmp,path)
        dfd=os.open(Path(path).parent,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW|os.O_CLOEXEC)
        try: os.fsync(dfd)
        finally: os.close(dfd)
    finally:
        if fd!=-1: os.close(fd)
        try: tmp.unlink()
        except FileNotFoundError: pass

def ensure_root():
    if not STATE_BASE.exists(): STATE_BASE.mkdir(parents=True,mode=0o700)
    parent=STATE_ROOT.parent
    if not parent.exists(): parent.mkdir(mode=0o700)
    else:
        # Only enforce privacy on Azuki-owned child, not XDG_STATE_HOME itself.
        st=parent.lstat()
        require(stat.S_ISDIR(st.st_mode) and st.st_uid==os.getuid(),"Estado Azuki inseguro.")
        if st.st_mode&0o077: os.chmod(parent,0o700)
    if not STATE_ROOT.exists(): STATE_ROOT.mkdir(mode=0o700)
    safe_dir(STATE_ROOT)
    if not LOCK.exists():
        fd=os.open(LOCK,os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW|os.O_CLOEXEC,0o600); os.close(fd)

class Locked:
    def __enter__(self):
        ensure_root()
        self.fd=os.open(LOCK,os.O_RDWR|os.O_NOFOLLOW|os.O_CLOEXEC)
        fcntl.flock(self.fd,fcntl.LOCK_EX); return self
    def __exit__(self,*args):
        fcntl.flock(self.fd,fcntl.LOCK_UN); os.close(self.fd)

def default_state():
    return {"schemaVersion":SCHEMA,"pluginId":PLUGIN_ID,"revision":0,
            "sessions":{},"instances":{},"incidents":[],"events":[]}

def validate_state(s):
    require(type(s) is dict and set(s)=={"schemaVersion","pluginId","revision","sessions","instances","incidents","events"},
            "Estado de coordinación con campos desconocidos.")
    require(s["schemaVersion"]==SCHEMA and s["pluginId"]==PLUGIN_ID and type(s["revision"]) is int,
            "Estado de coordinación incompatible.")
    require(type(s["sessions"]) is dict and type(s["instances"]) is dict
            and type(s["incidents"]) is list and type(s["events"]) is list,
            "Estado de coordinación inválido.")
    for client,row in s["sessions"].items():
        require(CLIENT.fullmatch(client) is not None and type(row) is dict,"Sesión inválida.")
        required={"instance","state","dirty","baseSha256","draftSha256","expectedSha256","lastSeen","openedAt"}
        require(set(row)==required and INSTANCE.fullmatch(row["instance"]) is not None,
                "Sesión incompatible.")
        require(row["state"] in ("clean","dirty","applying","orphaned") and type(row["dirty"]) is bool,
                "Estado de sesión inválido.")
    return s

def load_state():
    if not STATE.exists(): return default_state()
    return validate_state(json.loads(read_regular(STATE,4*1024*1024).decode("utf-8")))

def persist(state,kind):
    state["revision"]+=1
    state["events"].append({"kind":kind,"at":now_iso(),"revision":state["revision"]})
    require(len(state["events"])<=4000,"Diario de coordinación lleno.")
    atomic_write(STATE,(json.dumps(state,sort_keys=True,ensure_ascii=False,separators=(",",":"))+"\n").encode())

def instance_presence(instance):
    require(INSTANCE.fullmatch(instance or "") is not None,"ID de instancia inválido.")
    require(CONFIG.exists() and not CONFIG.is_symlink(),"No se encontró la configuración real de Plasma.")
    text=read_regular(CONFIG,8*1024*1024).decode("utf-8","strict")
    pat=re.compile(r"^\[Containments\]\[([0-9]+)\]\[Applets\]\["+re.escape(instance)+r"\]\s*$",re.M)
    matches=list(pat.finditer(text))
    if not matches: return "absent"
    if len(matches)!=1: return "ambiguous"
    start=matches[0].end(); nxt=text.find("\n[",start); block=text[start:nxt if nxt!=-1 else len(text)]
    plugin=re.search(r"(?m)^plugin=(.+)$",block)
    if not plugin or plugin.group(1).strip()!=PLUGIN_ID: return "foreign"
    return "present"

def group_for_instance(instance):
    require(instance_presence(instance)=="present","No se encontró una única instancia real de Azuki Tile Deck.")
    text=read_regular(CONFIG,8*1024*1024).decode("utf-8","strict")
    pat=re.compile(r"^\[Containments\]\[([0-9]+)\]\[Applets\]\["+re.escape(instance)+r"\]\s*$",re.M)
    return pat.search(text).group(1)

def committed_library(instance):
    containment=group_for_instance(instance)
    tool="/usr/bin/kreadconfig6"
    require(Path(tool).is_file(),"No se encontró /usr/bin/kreadconfig6.")
    cp=subprocess.run([tool,"--file",str(CONFIG),"--group","Containments","--group",containment,
                       "--group","Applets","--group",instance,"--group","Configuration",
                       "--group","General","--key","libraryJson"],
                      stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=3,check=False)
    require(cp.returncode==0,"kreadconfig6 no pudo leer la configuración de Azuki Tile Deck.")
    value=cp.stdout.rstrip("\n")
    if not value:
        value=read_regular(DEFAULT,MAX_LIBRARY).decode("utf-8")
    require(len(value.encode())<=MAX_LIBRARY,"Biblioteca excesiva.")
    parse_library(value,"Biblioteca comprometida")
    return value

def decode_expected(value):
    require(type(value) is str and len(value)<=MAX_LIBRARY*3,"Borrador codificado inválido.")
    text=unquote(value)
    require(len(text.encode())<=MAX_LIBRARY,"Borrador excesivo.")
    parse_library(text,"Borrador")
    return text

def stale(state):
    changed=False; t=now_ts()
    for client,row in state["sessions"].items():
        if row["state"]!="orphaned" and t-float(row["lastSeen"])>STALE_SECONDS:
            row["state"]="orphaned"  # preserve dirty exactly
            msg="Sesión de Preferencias sin heartbeat: "+row["instance"]
            if msg not in state["incidents"]: state["incidents"].append(msg)
            changed=True
    if changed: persist(state,"stale-session")

def source_problems(state):
    problems=[]
    # Only closed/known instances are compared globally. Active sessions are
    # validated by their own base/draft/expected hashes.
    active={row["instance"] for row in state["sessions"].values()}
    for instance,expected in state["instances"].items():
        if instance in active: continue
        try: current=library_sha(committed_library(instance))
        except Exception as exc: problems.append(instance+": "+str(exc)); continue
        if current!=expected: problems.append(instance+": configuración cambió fuera del protocolo")
    return problems

def maintenance_snapshot():
    return maint.load(MAINTENANCE,read_regular,atomic_write)

def require_preferences_allowed():
    lease=maintenance_snapshot()
    require(lease is None or lease["phase"]=="released",
            "Reserva exclusiva de mantenimiento activa o huérfana: Preferencias BLOQUEADAS.")

def summary(state):
    stale(state)
    lease=maintenance_snapshot()
    problems=source_problems(state)
    sessions=[]
    for client,row in sorted(state["sessions"].items()):
        sessions.append({"clientId":client[:12]+"…","instance":row["instance"],
                         "state":row["state"],"dirty":row["dirty"],
                         "lastSeenAge":round(max(0,now_ts()-float(row["lastSeen"])),2)})
    return {"mode":"azuki-tiledeck-coordination","schemaVersion":SCHEMA,"pluginId":PLUGIN_ID,
            "realDeletionAvailable":False,"deletionAuthorized":False,"revision":state["revision"],
            "sessions":sessions,"incidents":list(state["incidents"]),
            "sourceProblems":problems,
            "maintenanceAllowed":not sessions and not state["incidents"] and not problems and
                                 (lease is None or lease["phase"]=="released"),
            "maintenanceReservation":maint.public(lease),
            "staleAfterSeconds":STALE_SECONDS}

def get_session(state,client,instance=None):
    require(CLIENT.fullmatch(client or "") is not None and client in state["sessions"],
            "Sesión de Preferencias desconocida.")
    row=state["sessions"][client]
    if instance is not None: require(row["instance"]==instance,"La sesión pertenece a otra instancia.")
    return row

def open_or_attach(state,instance,client,expected):
    require_preferences_allowed()
    require(INSTANCE.fullmatch(instance or "") is not None,"ID de instancia inválido.")
    require(CLIENT.fullmatch(client or "") is not None,"ID de cliente inválido.")
    expected_text=decode_expected(expected)
    current=committed_library(instance); current_sha=library_sha(current); draft_sha=library_sha(expected_text)
    if client in state["sessions"]:
        row=state["sessions"][client]
        require(row["instance"]==instance and row["state"]!="orphaned","La sesión existente no puede adjuntarse.")
        allowed={row["baseSha256"]}
        if row.get("draftSha256"): allowed.add(row["draftSha256"])
        if row.get("expectedSha256"): allowed.add(row["expectedSha256"])
        require(draft_sha in allowed,"El borrador de la nueva página no coincide con la sesión activa.")
        row["lastSeen"]=now_ts(); persist(state,"attach-page")
        return row
    require(not state["incidents"],"Hay una incidencia de coordinación pendiente.")
    require(not source_problems(state),"La configuración cambió fuera del protocolo.")
    require(all(r["instance"]!=instance for r in state["sessions"].values()),
            "Ya existe otra ventana de Preferencias para esta instancia.")
    require(draft_sha==current_sha,"El borrador inicial no coincide con la configuración comprometida.")
    row={"instance":instance,"state":"clean","dirty":False,"baseSha256":current_sha,
         "draftSha256":current_sha,"expectedSha256":None,"lastSeen":now_ts(),"openedAt":now_iso()}
    state["sessions"][client]=row; state["instances"][instance]=current_sha; persist(state,"open")
    return row

def perform(args):
    with Locked():
        state=load_state(); stale(state)
        if args.action=="status": return summary(state)
        require_preferences_allowed()
        if args.action=="open":
            row=open_or_attach(state,args.instance,args.client_id,args.expected_encoded)
            return {"state":row["state"],"dirty":row["dirty"]}
        row=get_session(state,args.client_id,args.instance)
        require(row["state"]!="orphaned","La sesión está huérfana; requiere reconciliación.")
        if args.action=="heartbeat":
            row["lastSeen"]=now_ts(); persist(state,"heartbeat")
            return {"state":row["state"],"dirty":row["dirty"]}
        if args.action=="dirty":
            row["dirty"]=True; row["state"]="dirty"; row["lastSeen"]=now_ts()
            if args.expected_encoded:
                row["draftSha256"]=library_sha(decode_expected(args.expected_encoded))
            persist(state,"dirty")
            return {"state":"dirty","dirty":True}
        if args.action=="prepare-apply":
            caller_expected=library_sha(decode_expected(args.expected_encoded))
            known={row["baseSha256"],row["draftSha256"]}
            require(caller_expected in known,
                    "Una página intentó aplicar un borrador que no coincide con el estado coordinado.")
            # If another loaded page still exposes the committed/base draft while a
            # newer coordinated draft exists, never let that stale page replace it.
            expected=row["draftSha256"] if row["dirty"] else caller_expected
            if row["state"]=="applying":
                require(row["expectedSha256"]==expected,
                        "Dos páginas intentaron aplicar borradores distintos.")
                row["lastSeen"]=now_ts(); persist(state,"prepare-apply-repeat")
            else:
                row["dirty"]=True; row["state"]="applying"; row["expectedSha256"]=expected
                row["lastSeen"]=now_ts(); persist(state,"prepare-apply")
            return {"state":"applying","dirty":True}
        if args.action=="verify-apply":
            current=library_sha(committed_library(row["instance"]))
            good=row["expectedSha256"] is not None and current==row["expectedSha256"]
            row["lastSeen"]=now_ts()
            if good:
                row["baseSha256"]=current; row["draftSha256"]=current; row["expectedSha256"]=None
                row["dirty"]=False; row["state"]="clean"; state["instances"][row["instance"]]=current
                persist(state,"apply-verified")
            else: persist(state,"apply-not-yet-verified")
            return {"verified":good,"state":row["state"],"dirty":row["dirty"]}
        raise CoordinationError("Acción desconocida.")

def finalize(instance,confirmation):
    require(INSTANCE.fullmatch(instance or "") is not None,"ID de instancia inválido.")
    require(confirmation=="FINALIZAR EDICION TILE DECK "+instance,"Frase de finalización incorrecta.")
    with Locked():
        state=load_state(); stale(state); require_preferences_allowed()
        matches=[(c,r) for c,r in state["sessions"].items() if r["instance"]==instance]
        require(len(matches)==1,"No existe una única sesión activa para finalizar.")
        client,row=matches[0]
        require(row["state"]=="clean" and not row["dirty"] and row["expectedSha256"] is None,
                "La sesión no está limpia.")
        current=library_sha(committed_library(instance))
        require(current==row["baseSha256"],"La configuración comprometida cambió antes de finalizar.")
        del state["sessions"][client]; state["instances"][instance]=current
        persist(state,"finalize")
        return summary(state)

def reconcile(instance,confirmation):
    require(INSTANCE.fullmatch(instance or "") is not None,"ID de instancia inválido.")
    require(confirmation=="RECONCILIAR TILE DECK "+instance,"Frase de reconciliación incorrecta.")
    with Locked():
        state=load_state(); stale(state); require_preferences_allowed()
        matches=[(c,r) for c,r in state["sessions"].items() if r["instance"]==instance]
        require(len(matches)==1,"No existe una única sesión huérfana.")
        client,row=matches[0]; require(row["state"]=="orphaned","La sesión todavía está activa.")
        current=library_sha(committed_library(instance))
        allowed={row["baseSha256"],row["draftSha256"]}
        if row["expectedSha256"]: allowed.add(row["expectedSha256"])
        require(current in allowed,"La configuración comprometida no coincide con un estado conocido.")
        del state["sessions"][client]; state["instances"][instance]=current
        exact="Sesión de Preferencias sin heartbeat: "+instance
        state["incidents"]=[x for x in state["incidents"] if x!=exact]
        persist(state,"manual-reconcile")
        return summary(state)

def retire(instance,confirmation):
    require(INSTANCE.fullmatch(instance or "") is not None,"ID de instancia inválido.")
    require(confirmation=="RETIRAR INSTANCIA TILE DECK "+instance,"Frase de retiro incorrecta.")
    with Locked():
        state=load_state(); stale(state); require_preferences_allowed()
        matches=[(c,r) for c,r in state["sessions"].items() if r["instance"]==instance]
        require(len(matches)==1,"No existe una única sesión de esa instancia.")
        client,row=matches[0]
        require(row["state"]=="orphaned" and row["dirty"] is False and row["expectedSha256"] is None,
                "Solo puede retirarse una sesión huérfana limpia.")
        require(instance_presence(instance)=="absent","La instancia no está inequívocamente ausente de Plasma.")
        del state["sessions"][client]; state["instances"].pop(instance,None)
        exact="Sesión de Preferencias sin heartbeat: "+instance
        state["incidents"]=[x for x in state["incidents"] if x!=exact]
        persist(state,"retire-absent-instance")
        return summary(state)

def parser():
    p=argparse.ArgumentParser(description=__doc__); sp=p.add_subparsers(dest="action",required=True)
    sp.add_parser("status")
    o=sp.add_parser("open"); o.add_argument("--instance",required=True); o.add_argument("--client-id",required=True); o.add_argument("--expected-encoded",required=True)
    for name in ("heartbeat","verify-apply"):
        x=sp.add_parser(name); x.add_argument("--instance",required=True); x.add_argument("--client-id",required=True)
    d=sp.add_parser("dirty"); d.add_argument("--instance",required=True); d.add_argument("--client-id",required=True); d.add_argument("--expected-encoded",default="")
    a=sp.add_parser("prepare-apply"); a.add_argument("--instance",required=True); a.add_argument("--client-id",required=True); a.add_argument("--expected-encoded",required=True)
    return p

def main():
    args=parser().parse_args()
    try:
        result=perform(args)
        print(json.dumps({"ok":True,"data":result},ensure_ascii=False,separators=(",",":"))); return 0
    except (CoordinationError,OSError,ValueError,KeyError,json.JSONDecodeError,subprocess.TimeoutExpired) as exc:
        print(json.dumps({"ok":False,"message":str(exc)},ensure_ascii=False,separators=(",",":"))); return 2
if __name__=="__main__": sys.exit(main())
