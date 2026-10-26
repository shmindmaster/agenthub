"""Count or archive stale coding-agent sessions that live as SQLite rows.

Called by Remove-StaleAgentSessions.ps1. Never deletes a row: --apply backs up
every row it is about to change to --backup (JSON), then sets the store's own
archived flag, which is what the app's "archive" action sets. The caller is
responsible for confirming the owning app is not running.

Stores:
  cursor   state.vscdb composerHeaders.isArchived (+ composerData JSON flag)
  opencode opencode.db session/session_v2.time_archived
  codex    state_5.sqlite threads.archived / archived_at

Prints one JSON object: {"store", "db", "total", "stale", "archived"}.
"""
import argparse
import json
import sqlite3
import time


def connect(db, apply):
    path = db.replace('\\', '/')
    if apply:
        return sqlite3.connect(path, timeout=10)
    return sqlite3.connect('file:' + path + '?mode=ro', uri=True, timeout=10)


def cursor_store(c, cutoff_ms, apply, backup):
    total = c.execute('select count(*) from composerHeaders').fetchone()[0]
    rows = c.execute(
        'select composerId, isArchived, value from composerHeaders '
        'where coalesce(isArchived, 0) = 0 and coalesce(lastUpdatedAt, createdAt, 0) < ?',
        (cutoff_ms,)).fetchall()
    if not apply:
        return total, len(rows), 0
    saved = {'headers': [], 'composerData': []}
    for cid, arch, val in rows:
        saved['headers'].append({'composerId': cid, 'isArchived': arch, 'value': val})
        kv = c.execute('select value from cursorDiskKV where key = ?', ('composerData:' + cid,)).fetchone()
        if kv:
            saved['composerData'].append({'composerId': cid, 'isArchived': json.loads(kv[0]).get('isArchived')})
    write_backup(backup, saved)
    for cid, arch, val in rows:
        head = json.loads(val)
        head['isArchived'] = True
        c.execute('update composerHeaders set isArchived = 1, value = ? where composerId = ?', (json.dumps(head), cid))
        kv = c.execute('select value from cursorDiskKV where key = ?', ('composerData:' + cid,)).fetchone()
        if kv:
            data = json.loads(kv[0])
            data['isArchived'] = True
            c.execute('update cursorDiskKV set value = ? where key = ?', (json.dumps(data), 'composerData:' + cid))
    return total, len(rows), len(rows)


def opencode_store(c, cutoff_ms, apply, backup):
    tables = [t for (t,) in c.execute("select name from sqlite_master where type = 'table'") if t in ('session', 'session_v2')]
    total = stale = 0
    saved = {}
    for t in tables:
        total += c.execute(f'select count(*) from {t}').fetchone()[0]
        ids = [r[0] for r in c.execute(
            f'select id from {t} where time_archived is null and coalesce(time_updated, time_created, 0) < ?', (cutoff_ms,))]
        stale += len(ids)
        saved[t] = ids
    if not apply:
        return total, stale, 0
    write_backup(backup, {'time_archived_was_null': saved})
    now = int(time.time() * 1000)
    for t, ids in saved.items():
        c.executemany(f'update {t} set time_archived = ? where id = ? and time_archived is null', [(now, i) for i in ids])
    return total, stale, stale


def codex_store(c, cutoff_ms, apply, backup):
    total = c.execute('select count(*) from threads').fetchone()[0]
    cutoff_s = cutoff_ms // 1000
    ids = [r[0] for r in c.execute(
        'select id from threads where archived = 0 and coalesce(updated_at, created_at, 0) < ?', (cutoff_s,))]
    if not apply:
        return total, len(ids), 0
    write_backup(backup, {'archived_was_0': ids})
    now = int(time.time())
    c.executemany('update threads set archived = 1, archived_at = ? where id = ? and archived = 0', [(now, i) for i in ids])
    return total, len(ids), len(ids)


def write_backup(path, data):
    if not path:
        raise SystemExit('--apply requires --backup')
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(data, f)


STORES = {'cursor': cursor_store, 'opencode': opencode_store, 'codex': codex_store}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--store', required=True, choices=sorted(STORES))
    p.add_argument('--db', required=True)
    p.add_argument('--cutoff-ms', required=True, type=int)
    p.add_argument('--apply', action='store_true')
    p.add_argument('--backup')
    a = p.parse_args()
    c = connect(a.db, a.apply)
    total, stale, archived = STORES[a.store](c, a.cutoff_ms, a.apply, a.backup)
    if a.apply:
        c.commit()
    print(json.dumps({'store': a.store, 'db': a.db, 'total': total, 'stale': stale, 'archived': archived}))


if __name__ == '__main__':
    main()
