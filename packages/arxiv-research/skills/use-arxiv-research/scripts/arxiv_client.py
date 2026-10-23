"""Bounded, serialized MCP sessions against the unmodified upstream server."""
from __future__ import annotations

import argparse
import asyncio
from contextlib import contextmanager
from datetime import datetime, timezone
from importlib.metadata import version
import json
import os
from pathlib import Path
import sys

class ResearchError(Exception):
    pass


def runtime_root() -> Path:
    base = Path(os.environ['LOCALAPPDATA']) if os.name == 'nt' else Path.home() / '.local/share'
    return base / 'AgentHub/runtime/arxiv-research'


@contextmanager
def session_lock(path: Path):
    """An OS-owned lock survives contention and releases when the caller dies."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('a+b') as handle:
        if path.stat().st_size == 0:
            handle.write(b'0')
            handle.flush()
        handle.seek(0)
        try:
            if os.name == 'nt':
                import msvcrt
                msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise ResearchError('Another arXiv research session holds the shared lock; retry after it finishes.') from None
        try:
            yield
        finally:
            handle.seek(0)
            if os.name == 'nt':
                msvcrt.locking(handle.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(handle, fcntl.LOCK_UN)


def validate_plan(plan):
    if not isinstance(plan, list) or not 1 <= len(plan) <= 30:
        raise ResearchError('A plan must contain 1 to 30 operations.')
    for step in plan:
        if not isinstance(step, dict) or step.get('operation') not in {'tools','call','prompts','prompt'}:
            raise ResearchError('Unknown research operation.')
        if step['operation'] in {'call','prompt'} and not isinstance(step.get('name'), str):
            raise ResearchError('call/prompt requires a name.')
        if not isinstance(step.get('arguments', {}), dict):
            raise ResearchError('Tool/prompt arguments must be a JSON object.')
    return plan


async def execute(plan, params, log, timeout):
    import anyio
    from mcp import ClientSession
    from mcp.client.stdio import stdio_client

    results = []
    ok = True
    with anyio.fail_after(timeout):
        async with stdio_client(params, errlog=log) as (reader, writer):
            async with ClientSession(reader, writer) as session:
                initialized = await session.initialize()
                for step in plan:
                    operation = step['operation']
                    if operation == 'tools':
                        result = await session.list_tools()
                    elif operation == 'prompts':
                        result = await session.list_prompts()
                    elif operation == 'prompt':
                        result = await session.get_prompt(step['name'], step.get('arguments', {}))
                    else:
                        result = await session.call_tool(step['name'], step.get('arguments', {}))
                    payload = result.model_dump(mode='json', exclude_none=True)
                    failed = bool(payload.get('isError'))
                    # Preserve upstream structured errors even if a provider omits isError.
                    for content in payload.get('content', []):
                        if content.get('type') == 'text':
                            try:
                                parsed = json.loads(content['text'])
                                failed |= isinstance(parsed, dict) and parsed.get('status') == 'error'
                            except (ValueError, KeyError):
                                pass
                    results.append({'operation':operation, 'name':step.get('name'), 'ok':not failed, 'result':payload})
                    if failed:
                        ok = False
                        break
    return {'ok':ok, 'protocol':initialized.protocolVersion, 'server':initialized.serverInfo.model_dump(mode='json'), 'results':results}


def read_json(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['tools','call','prompts','prompt','batch'])
    parser.add_argument('--name')
    parser.add_argument('--arguments-file')
    parser.add_argument('--plan-file')
    parser.add_argument('--output-file')
    parser.add_argument('--timeout', type=int, choices=range(1,601), default=180, metavar='1..600')
    args = parser.parse_args()
    root = runtime_root()
    try:
        pinned = Path(__file__).with_name('requirements.txt').read_text().strip().split('==')[1]
        if version('arxiv-mcp-server') != pinned:
            raise ResearchError('Installed arXiv MCP version differs from AgentHub. Run -Operation install explicitly.')
        if args.operation == 'batch':
            if not args.plan_file:
                raise ResearchError('batch requires --plan-file.')
            plan = read_json(args.plan_file)
        else:
            plan = [{'operation':args.operation, 'name':args.name, 'arguments':read_json(args.arguments_file) if args.arguments_file else {}}]
        validate_plan(plan)
        with session_lock(root / 'session.lock'):
            from mcp import StdioServerParameters

            library = root / 'papers'
            library.mkdir(parents=True, exist_ok=True)
            params = StdioServerParameters(
                command=sys.executable,
                args=['-c','from arxiv_mcp_server import main; main()', '--storage-path',str(library)],
                cwd=str(root),
                env={'TRANSPORT':'stdio','PYTHONUTF8':'1','PYTHONDONTWRITEBYTECODE':'1'},
            )
            with (root / 'server.log').open('a', encoding='utf-8') as log:
                payload = asyncio.run(execute(plan, params, log, args.timeout))
        payload['storage'] = str(library)
    except BaseException as exc:
        if isinstance(exc, (KeyboardInterrupt, SystemExit)):
            raise
        # Do not serialize exception groups, request headers or inherited env.
        message = str(exc) if isinstance(exc, ResearchError) else f'{type(exc).__name__}; inspect the local server log for details.'
        payload = {'ok':False, 'error':message, 'log':str(root / 'server.log')}
    payload['retrieved_at'] = datetime.now(timezone.utc).isoformat()
    encoded = json.dumps(payload, ensure_ascii=False, indent=2) + '\n'
    if args.output_file:
        target = Path(args.output_file).resolve()
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(encoded, encoding='utf-8')
        print(json.dumps({'ok':payload['ok'], 'output_file':str(target)}))
    else:
        sys.stdout.reconfigure(encoding='utf-8')
        print(encoded, end='')
    return 0 if payload['ok'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
