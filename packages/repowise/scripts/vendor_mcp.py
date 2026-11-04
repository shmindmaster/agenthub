"""Start the vendor RepoWise MCP server on the MahumTech Azure embedder.

Vendor `repowise mcp` reads OPENAI_BASE_URL and OPENAI_API_KEY from its own
process and has no Azure provider. Setting them here keeps Azure scoped to this
process tree, so machine-wide OpenAI settings stay untouched and no key is
copied into a config file. If Azure is unavailable the vendor server still
starts and serves keyword retrieval.
"""
from __future__ import annotations

import shutil
import subprocess
import sys

from shared_server import configure_remote_embedder

CREATE_NO_WINDOW = 0x08000000


def main() -> int:
    executable = shutil.which('repowise')
    if not executable:
        print('RepoWise CLI not found', file=sys.stderr)
        return 1
    try:
        configure_remote_embedder()
    except (RuntimeError, ValueError) as error:
        print(f'RepoWise vector retrieval unavailable: {error}', file=sys.stderr)
    flags = CREATE_NO_WINDOW if sys.platform == 'win32' else 0
    # Pass stdio explicitly: Windows does not hand pipes to a child otherwise.
    return subprocess.call([executable, 'mcp', *sys.argv[1:]], stdin=sys.stdin,
                           stdout=sys.stdout, stderr=sys.stderr, creationflags=flags)


if __name__ == '__main__':
    raise SystemExit(main())
