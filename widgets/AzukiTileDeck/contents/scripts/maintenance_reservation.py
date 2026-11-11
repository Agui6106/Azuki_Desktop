#!/usr/bin/env python3
"""Azuki g13.2.0 staged cooperative lease engine. Synthetic tests ONLY.

The package has NO installer and NO physical executor. Every call must run
under the coordination_guard.Locked mutex. Hash chains detect accidental
corruption; they are not a defense against a malicious same-user writer.
"""
import hashlib, json, secrets, re, time
from pathlib import Path

HEX64=re.compile(r"^[a-f0-9]{64}$")
SCHEMA=1
FIELDS={'schemaVersion','mode','phase','leaseId','tokenDigest','expectedRevision',
        'sourceBindingDigest','ttlSeconds','createdAt','lastHeartbeat','operation',
        'incident','journal','journalHead','checksum'}

def _require(ok, msg):
    if not ok: raise LeaseError(msg)

class LeaseError(Exception): pass

def _digest(value):
    return hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,
                                    separators=(',',':'),allow_nan=False).encode()).hexdigest()

def _record(row, event):
    prev=row['journalHead']
    entry={'index':len(row['journal'])+1,'kind':event,'previous':prev}
    entry['digest']=_digest(entry)
    row['journal'].append(entry)
    row['journalHead']=entry['digest']

def _checksum(row):
    row['checksum']=_digest({k:v for k,v in row.items() if k!='checksum'})

def load(path, read_regular, atomic_write, now=None):
    """Read, validate and mark stale leases orphaned; fail closed on corruption."""
    path=Path(path)
    _require(not path.is_symlink(),'Reserva simbólica rechazada.')
    if not path.exists(): return None
    try: row=json.loads(read_regular(path,256*1024).decode('utf8'))
    except (OSError,ValueError,UnicodeError) as exc: raise LeaseError('Reserva ilegible.') from exc
    _require(type(row) is dict and set(row)==FIELDS,'Esquema de reserva incompatible.')
    _require(row['schemaVersion']==SCHEMA and row['mode']=='cooperative-staged',
             'Esquema de reserva incorrecto.')
    _require(row['phase'] in ('active','orphaned','released') and
             row['operation'] in ('none','synthetic-inflight','synthetic-completed'),
             'Estado de reserva incorrecto.')
    _require(type(row['expectedRevision']) is int and row['expectedRevision']>=0 and
             type(row['ttlSeconds']) is int and 15<=row['ttlSeconds']<=600,
             'Revisión o duración inválida.')
    _require(all(type(row[k]) is str and HEX64.fullmatch(row[k]) for k in
                 ('tokenDigest','sourceBindingDigest','journalHead','checksum')),
             'Digest inválido.')
    _require(type(row['leaseId']) is str and re.fullmatch(r'[a-f0-9]{32}',row['leaseId']) and
             type(row['journal']) is list and 1<=len(row['journal'])<=1000,
             'Identidad o diario inválidos.')
    _require(row['incident'] is None or isinstance(row['incident'],str),
             'Incidencia inválida.')
    head='0'*64
    for n,event in enumerate(row['journal'],start=1):
        _require(type(event) is dict and set(event)=={'index','kind','previous','digest'} and
                 event['index']==n and event['previous']==head and
                 type(event['kind']) is str and HEX64.fullmatch(event['digest']),
                 'Diario de reserva corrupto.')
        _require(_digest({k:v for k,v in event.items() if k!='digest'})==event['digest'],
                 'Digest del diario incorrecto.')
        head=event['digest']
    _require(head==row['journalHead'] and
             _digest({k:v for k,v in row.items() if k!='checksum'})==row['checksum'],
             'Integridad de reserva incorrecta.')
    timestamp=time.time() if now is None else now
    if row['phase']=='active' and (timestamp < row['lastHeartbeat'] or
                                   timestamp-row['lastHeartbeat']>=row['ttlSeconds']):
        row['phase']='orphaned'
        row['incident']='clock-regression' if timestamp < row['lastHeartbeat'] else 'heartbeat-timeout'
        _record(row,'orphaned-'+row['incident']); _checksum(row)
        atomic_write(path,(json.dumps(row,sort_keys=True)+'\n').encode())
    return row

def save(path,row,atomic_write):
    _checksum(row)
    atomic_write(path,(json.dumps(row,sort_keys=True,separators=(',',':'))+'\n').encode())

def public(row):
    if row is None: return {'phase':'none','active':False,'orphaned':False}
    return {'phase':row['phase'],'active':row['phase']=='active',
            'orphaned':row['phase']=='orphaned','leaseId':row['leaseId'],
            'operation':row['operation'],'incident':row['incident'],
            'expectedRevision':row['expectedRevision'],'journalEntries':len(row['journal'])}

def acquire(path,read_regular,atomic_write,revision,binding_digest,ttl=60,now=None):
    old=load(path,read_regular,atomic_write,now)
    _require(old is None or old['phase']=='released',
             'Reserva activa o huérfana; adquisición BLOQUEADA.')
    _require(type(revision) is int and revision>=0 and type(binding_digest) is str and
             HEX64.fullmatch(binding_digest),'Binding o revisión inválidos.')
    _require(type(ttl) is int and 15<=ttl<=600,'TTL fuera de rango.')
    secret=secrets.token_hex(32); timestamp=time.time() if now is None else now
    row={'schemaVersion':SCHEMA,'mode':'cooperative-staged','phase':'active',
         'leaseId':secrets.token_hex(16),'tokenDigest':hashlib.sha256(secret.encode()).hexdigest(),
         'expectedRevision':revision,'sourceBindingDigest':binding_digest,
         'ttlSeconds':ttl,'createdAt':timestamp,'lastHeartbeat':timestamp,
         'operation':'none','incident':None,'journal':[],'journalHead':'0'*64,'checksum':''}
    _record(row,'acquire'); save(path,row,atomic_write)
    return row,secret

def check_owner(row,secret,revision):
    _require(row is not None and row['phase']=='active',
             'La reserva no está activa; operación BLOQUEADA.')
    _require(type(secret) is str and secrets.compare_digest(row['tokenDigest'],
              hashlib.sha256(secret.encode()).hexdigest()),'Token inválido.')
    if revision!=row['expectedRevision']:
        row['phase']='orphaned'; row['incident']='revision-drift'
        _record(row,'orphaned-revision-drift')
        raise DriftError('Revisión diferente: reserva huérfana.')

class DriftError(LeaseError): pass

def heartbeat(row,secret,revision,now=None):
    check_owner(row,secret,revision)
    _require(row['operation']!='synthetic-inflight','Operación incompleta.')
    row['lastHeartbeat']=time.time() if now is None else now
    _record(row,'heartbeat')

def begin(row,secret,revision):
    check_owner(row,secret,revision)
    _require(row['operation']=='none','Una operación ya comenzó.')
    row['operation']='synthetic-inflight'; _record(row,'synthetic-begin')

def finish(row,secret,revision):
    check_owner(row,secret,revision)
    _require(row['operation']=='synthetic-inflight','No hay operación en curso.')
    row['operation']='synthetic-completed'; _record(row,'synthetic-finish')

def release(row,secret,revision):
    check_owner(row,secret,revision)
    _require(row['operation']!='synthetic-inflight','No liberar operación incompleta.')
    row['phase']='released'; _record(row,'clean-release')

def orphan(row,reason):
    _require(row['phase']=='active','No se puede marcar una reserva inactiva.')
    row['phase']='orphaned'; row['incident']=reason
    _record(row,'orphaned-'+reason)

def reconcile(row,revision,confirmation):
    _require(row['phase']=='orphaned' and row['operation']=='none' and
             row['incident'] in ('heartbeat-timeout','synthetic-crash-after-acquire') and
             revision==row['expectedRevision'] and
             confirmation=='RECONCILIAR RESERVA SINTETICA SIN OPERACION',
             'Reconciliación imposible o confirmación incorrecta.')
    row['phase']='released'; _record(row,'explicit-synthetic-reconciliation')
