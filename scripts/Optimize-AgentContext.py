"""Manual, reversible cleanup of imported shared skills; no host or network calls.

Only the named legacy import bundles are eligible. Unknown files and modified
destination skills are preserved. Recovery stays in the target user's runtime.
Run after a vendor import if it recreates duplicate bundles. Audit is default.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

LEGACY = {'built-in-browser', 'canvas-design', 'chrome-browser', 'computer-use',
          'deep-research', 'doc-coauthoring', 'docs', 'docx', 'google-workspace',
          'import-memory', 'internal-comms', 'learn', 'mcp-builder', 'morning',
          'pdf', 'pptx', 'sarosh-voice', 'skill-creator', 'slack-gif-creator',
          'theme-factory', 'web-artifacts-builder', 'xlsx'}
KEEP = {'canvas-design', 'deep-research', 'doc-coauthoring', 'docx', 'mcp-builder',
        'pdf', 'pptx', 'web-artifacts-builder', 'xlsx'}

def tree_hash(path):
    digest = hashlib.sha256()
    for file in sorted(path.rglob('*')):
        if file.is_symlink() or file.is_junction():
            raise ValueError('Linked import content requires manual review')
        if file.is_file():
            digest.update(str(file.relative_to(path)).encode())
            digest.update(file.read_bytes())
    return digest.hexdigest()

def optimize(user, apply=False):
    user = user.resolve()
    shared = user/'.agents/skills'
    imported = shared/'synced'
    recovery = user/'AppData/Local/AgentHub/recovery/context'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    rows = []
    if not imported.is_dir():
        return {'actions': rows, 'recovery': None}
    if imported.is_symlink() or imported.is_junction():
        raise ValueError('Import root must be a physical directory')
    for bundle in sorted(imported.iterdir()):
        if not bundle.is_dir() or bundle.is_symlink() or bundle.is_junction():
            continue
        for source in sorted(bundle.iterdir()):
            if source.name not in LEGACY or not (source/'SKILL.md').is_file():
                continue
            if source.is_symlink() or source.is_junction() or not source.resolve().is_relative_to(imported.resolve()):
                raise ValueError('Import target escapes the declared shared import directory')
            digest = tree_hash(source)
            target = shared/source.name
            action = 'retire-import'
            if source.name in KEEP:
                if target.exists() and tree_hash(target) != digest:
                    rows.append({'path': str(source), 'action': 'preserve-conflicting-copy'})
                    continue
                action = 'retain-one-copy' if not target.exists() else 'deduplicate'
                if apply and not target.exists():
                    shutil.copytree(source, target)
                    if tree_hash(target) != digest:
                        raise ValueError('Retained skill readback mismatch')
            row = {'path': str(source), 'action': action, 'sha256': digest}
            if apply:
                destination = recovery/bundle.name/source.name
                if not destination.resolve().is_relative_to(recovery.resolve()):
                    raise ValueError('Recovery target escapes declared directory')
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(source, destination)
                if tree_hash(destination) != digest:
                    raise ValueError('Recovery readback mismatch')
                shutil.rmtree(source)
            rows.append(row)
        if apply and not any(bundle.iterdir()):
            bundle.rmdir()
    result = {'actions': rows, 'recovery': str(recovery) if apply and rows else None}
    if apply and rows:
        recovery.mkdir(parents=True, exist_ok=True)
        (recovery/'manifest.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    return result

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--user-profile', type=Path, default=Path.home())
    parser.add_argument('--apply', action='store_true')
    options = parser.parse_args()
    print(json.dumps(optimize(options.user_profile, options.apply), indent=2))
