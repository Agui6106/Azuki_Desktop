#!/usr/bin/env python3
"""Renew a Preferences session and finalize a verified Apply on window close."""
import argparse
from datetime import datetime
import json
import math
import sys
import time
import coordination_guard as guard


def opened_ms(row):
    value = datetime.fromisoformat(row['openedAt'])
    guard.require(value.tzinfo is not None, 'Fecha de apertura sin zona horaria.')
    return math.floor(value.timestamp() * 1000)


def bind(instance, after_ms):
    guard.require(guard.INSTANCE.fullmatch(instance or '') is not None, 'Instancia inválida.')
    guard.require(type(after_ms) is int and 0 < after_ms <= math.floor(guard.now_ts() * 1000),
                  'La hora de la ventana es inválida o el reloj retrocedió.')
    with guard.Locked():
        state = guard.load_state()
        guard.stale(state)
        guard.require_preferences_allowed()
        matches = [(client, row) for client, row in state['sessions'].items()
                   if row['instance'] == instance]
        if not matches:
            return {'waiting': True}
        guard.require(len(matches) == 1, 'Hay más de una sesión para esta instancia.')
        client, row = matches[0]
        guard.require(row['state'] != 'orphaned', 'La sesión está huérfana; no se renovará.')
        guard.require(opened_ms(row) >= after_ms,
                      'La sesión pertenece a una ventana anterior; no se renovará.')
        return {'waiting': False, 'clientId': client, 'openedAt': row['openedAt']}


def pulse(instance, client, opened_at):
    with guard.Locked():
        state = guard.load_state()
        guard.stale(state)
        guard.require_preferences_allowed()
        row = guard.get_session(state, client, instance)
        guard.require(row['openedAt'] == opened_at, 'La identidad de la sesión cambió.')
        guard.require(row['state'] != 'orphaned', 'La sesión está huérfana; no se renovará.')
        guard.require(guard.now_ts() >= float(row['lastSeen']), 'El reloj retrocedió.')
        row['lastSeen'] = guard.now_ts()
        guard.persist(state, 'heartbeat')
        return {'state': row['state'], 'dirty': row['dirty']}


def close_clean(instance, opened_after_ms, closed_before_ms):
    """Finish only a clean session or an Apply whose bytes reached KConfig."""
    guard.require(guard.INSTANCE.fullmatch(instance or '') is not None, 'Instancia inválida.')
    guard.require(type(opened_after_ms) is int and type(closed_before_ms) is int
                  and 0 < opened_after_ms <= closed_before_ms <= math.floor(guard.now_ts() * 1000) + 2000,
                  'Intervalo de ventana inválido.')
    # Plasma may tear down the QML page immediately after Apply. Its
    # prepare-apply subprocess and KConfig write can still be completing.
    # Never sleep while holding the coordination lock.
    deadline = time.monotonic() + 2.0
    while True:
        with guard.Locked():
            state = guard.load_state()
            guard.stale(state)
            guard.require_preferences_allowed()
            matches = [(client, row) for client, row in state['sessions'].items()
                       if row['instance'] == instance and opened_after_ms <= opened_ms(row) <= closed_before_ms]
            guard.require(len(matches) == 1, 'No hay una única sesión de esta ventana.')
            client, row = matches[0]
            current = guard.library_sha(guard.committed_library(instance))
            clean = (row['state'] == 'clean' and row['dirty'] is False
                     and row['expectedSha256'] is None and current == row['baseSha256'])
            applied = (row['state'] == 'applying' and row['dirty'] is True
                       and row['expectedSha256'] is not None
                       and row['draftSha256'] == row['expectedSha256']
                       and current == row['expectedSha256'])
            if clean or applied:
                del state['sessions'][client]
                state['instances'][instance] = current
                guard.persist(state, 'window-close-applied' if applied else 'window-close-clean')
                return {'closed': True, 'applied': applied}
            # Only a pending Apply gets time to finish. Bare/unsaved edits
            # remain blocked and require manual review as before.
            waiting = (row['state'] in ('dirty', 'applying') and row['dirty'] is True)
        if not waiting or time.monotonic() >= deadline:
            raise guard.CoordinationError('La sesión no está limpia; requiere revisión.')
        time.sleep(0.1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    b = sub.add_parser('bind')
    b.add_argument('--instance', required=True)
    b.add_argument('--opened-after-ms', type=int, required=True)
    b.add_argument('--request-id')
    p = sub.add_parser('pulse')
    p.add_argument('--instance', required=True)
    p.add_argument('--client-id', required=True)
    p.add_argument('--opened-at', required=True)
    p.add_argument('--request-id')
    c = sub.add_parser('close-clean')
    c.add_argument('--instance', required=True)
    c.add_argument('--opened-after-ms', type=int, required=True)
    c.add_argument('--closed-before-ms', type=int, required=True)
    c.add_argument('--request-id')
    args = parser.parse_args()
    try:
        if args.action == 'bind':
            result = bind(args.instance, args.opened_after_ms)
        elif args.action == 'pulse':
            result = pulse(args.instance, args.client_id, args.opened_at)
        else:
            result = close_clean(args.instance, args.opened_after_ms, args.closed_before_ms)
        print(json.dumps({'ok': True, 'data': result}, ensure_ascii=False))
        return 0
    except (guard.CoordinationError, guard.maint.LeaseError, OSError, ValueError, KeyError, TypeError) as exc:
        print(json.dumps({'ok': False, 'message': str(exc)}, ensure_ascii=False))
        return 2


if __name__ == '__main__':
    sys.exit(main())
