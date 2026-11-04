"""Serve vendor RepoWise to one host session through the one shared server.

The vendor plugin's .mcp.json points here (Install-RepoWiseVendorLauncher.ps1).
A `repowise mcp` per session holds about 330 MB each, measured at 3.3 GB across
10 sessions; the shared vendor server holds 760 MB for all of them, and this
process stays small. The bridge starts that server when it is down, and the
server exits after 30 idle minutes, so nothing runs without a session using it.
"""
from __future__ import annotations

from repowise_bridge import main

if __name__ == '__main__':
    raise SystemExit(main())
