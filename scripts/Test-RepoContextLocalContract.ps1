#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoContextRoot = 'C:\Repos\shmindmaster\repocontext'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath (Join-Path $RepoContextRoot 'src\server.ts') -PathType Leaf)) {
    throw "RepoContext checkout not found at $RepoContextRoot"
}

$source = @'
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

const repoContextRoot = process.argv[2];
const transport = new StdioClientTransport({ command: 'pnpm', args: ['--dir', repoContextRoot, 'mcp:serve'] });
const client = new Client({ name: 'agenthub-repocontext-verifier', version: '1.0.0' });
await client.connect(transport);

const expected = ['wiki.catalog', 'wiki.search', 'wiki.get', 'wiki.analyze', 'repo.inspect', 'repo.read', 'repo.search', 'repo.compare'];
const listed = await client.listTools();
const tools = listed.tools.map((tool) => tool.name);
if (JSON.stringify(tools) !== JSON.stringify(expected)) throw new Error(`Unexpected RepoContext tools: ${tools.join(', ')}`);

const catalog = await client.callTool({ name: 'wiki.catalog', arguments: { view: 'repositories' } });
const repository = await client.callTool({ name: 'repo.inspect', arguments: { repository: 'crewscore', operation: 'status' } });
if (catalog.isError || repository.isError) throw new Error('A safe RepoContext contract probe returned an MCP error.');

console.log(JSON.stringify({ tools, catalogOk: true, localRepositoryOk: true }));
await client.close();
'@

$source | & pnpm --dir $RepoContextRoot exec tsx - $RepoContextRoot
if ($LASTEXITCODE -ne 0) { throw "RepoContext local contract check failed with exit code $LASTEXITCODE." }
