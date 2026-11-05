#!/usr/bin/env python3
"""Apply registry/context-limits.json to each coding host.

Audit is the default; --apply writes. Host config files can hold keys, so this prints only the
values named in the registry and booleans or numbers read from those same keys.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
parser = argparse.ArgumentParser()
parser.add_argument('--apply', action='store_true')
parser.add_argument('--home', help='Run against this folder instead of the real home; skips user-env entries.')
parser.add_argument('--registry', default=os.path.join(ROOT, 'registry', 'context-limits.json'))
args = parser.parse_args()

HOME = args.home or os.path.expanduser('~')
APPDATA = os.path.join(HOME, 'AppData', 'Roaming') if args.home else os.environ.get('APPDATA', '')
BACKUPS = os.path.join(HOME, 'backups') if args.home else os.path.join(
    os.environ.get('LOCALAPPDATA', HOME), 'AgentHub', 'backups', f'context-limits-{datetime.date.today():%Y%m%d}')


def resolve(template):
    return os.path.normpath(template.replace('~', HOME, 1).replace('%APPDATA%', APPDATA))


def shown(value):
    return value if isinstance(value, (bool, int, float)) or value is None else 'set'


def read(path):
    with open(path, encoding='utf-8-sig', newline='') as handle:
        return handle.read()


def json_targets(data, key):
    """Yield (parent, last key) for each place the key names, expanding '*' over existing children."""
    nodes = [data]
    for part in key[:-1]:
        next_nodes = []
        for node in nodes:
            if part == '*':
                next_nodes.extend(child for child in node.values() if isinstance(child, dict))
            else:
                next_nodes.append(node.setdefault(part, {}))
        nodes = next_nodes
    return [(node, key[-1]) for node in nodes]


def edit_json(text, key, value):
    data = json.loads(text)
    before = []
    for parent, last in json_targets(data, key):
        before.append(parent.get(last))
        parent[last] = value
    newline = '\r\n' if '\r\n' in text else '\n'
    out = json.dumps(data, indent=2, ensure_ascii=False).replace('\n', newline)
    if text.endswith(('\n', '\r\n')):
        out += newline
    return out, before


def edit_jsonc(text, key, value):
    """VS Code settings allow comments, so this edits one line and leaves the rest of the file alone."""
    name = re.escape(key[0])
    literal = json.dumps(value)
    match = re.search(rf'("{name}"\s*:\s*)(true|false|-?[\d.]+|"[^"\n]*")', text)
    if match:
        return text[:match.start(2)] + literal + text[match.end(2):], [json.loads(match.group(2))]
    newline = '\r\n' if '\r\n' in text else '\n'
    return text.replace('{', '{' + newline + f'    "{key[0]}": {literal},', 1), [None]


def edit_toml(text, key, value):
    """Changes one line, which keeps the file's comments and order. The table must already exist."""
    name = re.escape(key[-1])
    literal = json.dumps(value)
    newline = '\r\n' if '\r\n' in text else '\n'
    start = 0
    if len(key) > 1:
        header = re.search(rf'^\[{re.escape(".".join(key[:-1]))}\][ \t]*\r?\n', text, re.M)
        if not header:
            raise ValueError(f'table for {key[-1]} is missing')
        start = header.end()
    tables = re.compile(r'^\s*\[', re.M).search(text, start)
    end = tables.start() if tables else len(text)
    match = re.compile(rf'^({name}\s*=\s*)(.*?)(\r?)$', re.M).search(text, start, end)
    current = tomllib.loads(text)
    for part in key[:-1]:
        current = current[part]
    if match:
        return text[:match.start(2)] + literal + text[match.end(2):], [current.get(key[-1])]
    line = f'{key[-1]} = {literal}{newline}'
    at = start if len(key) > 1 else end
    return text[:at] + line + text[at:], [None]


EDITORS = {'json': edit_json, 'jsonc': edit_jsonc, 'toml': edit_toml}


def check_parses(text, kind):
    if kind == 'json':
        json.loads(text)
    elif kind == 'toml':
        tomllib.loads(text)


def user_env(name, value):
    if args.home:
        return 'skipped'
    current = os.environ.get(name) if sys.platform != 'win32' else subprocess.run(
        ['powershell', '-NoProfile', '-Command', f"[Environment]::GetEnvironmentVariable('{name}','User')"],
        capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW).stdout.strip()
    if current == value:
        return 'current'
    if args.apply:
        subprocess.run(['powershell', '-NoProfile', '-Command', f"[Environment]::SetEnvironmentVariable('{name}','{value}','User')"],
                       check=True, creationflags=subprocess.CREATE_NO_WINDOW)
        return 'written'
    return 'drift'


registry = json.load(open(args.registry, encoding='utf-8'))
contents = {}
states = {}
for row in registry['settings']:
    label = f"[{row['host']}] {'.'.join(row['key'])}"
    if row['format'] == 'user-env':
        state = user_env(row['key'][0], row['value'])
        print(f'{label}: {state}')
        states[state] = states.get(state, 0) + 1
        continue
    path = resolve(row['file'])
    if not os.path.exists(path):
        print(f'{label}: file missing')
        states['missing'] = states.get('missing', 0) + 1
        continue
    text = contents.get(path) or read(path)
    out, before = EDITORS[row['format']](text, row['key'], row['value'])
    check_parses(out, row['format'])
    state = 'current' if out == text or all(item == row['value'] for item in before) else 'drift'
    contents[path] = out
    previous = sorted({str(shown(item)) for item in before})
    print(f"{label}: {state} ({', '.join(previous)} -> {row['value']})")
    states[state] = states.get(state, 0) + 1

removed = registry.get('removedPlugins', {})
for config in removed.get('configs', []):
    path = resolve(config['file'])
    if not os.path.exists(path):
        continue
    source = read(path)
    data = tomllib.loads(source) if config['format'] == 'toml' else json.loads(source)
    for key, value in (data.get(config['key']) or {}).items():
        enabled = value.get('enabled', True) if isinstance(value, dict) else bool(value)
        if enabled and key.split('@')[0] in removed.get('names', []):
            print(f"[{config['host']}] {key}: removed plugin is back")
            states['drift'] = states.get('drift', 0) + 1

written = 0
if args.apply:
    for path, out in contents.items():
        original = read(path)
        if out == original:
            continue
        os.makedirs(BACKUPS, exist_ok=True)
        target = os.path.join(BACKUPS, re.sub(r'[\\/:]+', '_', os.path.relpath(path, HOME)))
        if not os.path.exists(target):
            shutil.copy2(path, target)
        with open(path, 'w', encoding='utf-8', newline='') as handle:
            handle.write(out)
        written += 1

print(f'context-limits: {states} files written={written}')
