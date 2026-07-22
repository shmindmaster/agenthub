#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ShwikiRoot = 'C:\Repos\shmindmaster\shwiki'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath (Join-Path $ShwikiRoot 'mcp\server.ts') -PathType Leaf)) {
    throw "ShWiki checkout not found at $ShwikiRoot"
}

$source = @'
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const shwikiRoot = process.argv[2];
const transport = new StdioClientTransport({ command: 'pnpm', args: ['--dir', shwikiRoot, 'mcp:wiki'] });
const client = new Client({ name: 'agent-capabilities-shwiki-verifier', version: '1.0.0' });
await client.connect(transport);

const expected = ['wiki.catalog', 'wiki.search', 'wiki.get', 'wiki.analyze', 'repo.inspect', 'repo.read', 'repo.search', 'repo.compare'];
const listed = await client.listTools();
const tools = listed.tools.map((tool) => tool.name);
if (JSON.stringify(tools) !== JSON.stringify(expected)) throw new Error(`Unexpected ShWiki tools: ${tools.join(', ')}`);

const catalog = await client.callTool({ name: 'wiki.catalog', arguments: { view: 'repositories' } });
const repository = await client.callTool({ name: 'repo.inspect', arguments: { repository: 'tellgence-backend', operation: 'status' } });
if (catalog.isError || repository.isError) throw new Error('A safe ShWiki contract probe returned an MCP error.');

console.log(JSON.stringify({ tools, catalogOk: true, localRepositoryOk: true }));
await client.close();
'@

$source | & pnpm --dir $ShwikiRoot exec tsx - $ShwikiRoot
if ($LASTEXITCODE -ne 0) { throw "ShWiki local contract check failed with exit code $LASTEXITCODE." }
