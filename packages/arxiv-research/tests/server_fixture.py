"""Synthetic stdio peer for client lifecycle/error tests. No external I/O."""
import asyncio
import os
from mcp.server.fastmcp import FastMCP

server = FastMCP('arxiv-client-fixture')


@server.tool()
def identify() -> dict:
    return {'pid':os.getpid(), 'fixture':True}


@server.tool()
def fail() -> str:
    raise ValueError('synthetic upstream failure')


@server.tool()
async def wait() -> str:
    await asyncio.sleep(60)
    return 'unexpected completion'


if __name__ == '__main__':
    server.run(transport='stdio')
