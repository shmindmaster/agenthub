#Requires -Version 5.1
<#
.SYNOPSIS
  Guidance + status for official Chrome DevTools MCP --autoConnect (authenticated).

.DESCRIPTION
  As of Chrome 136+, --remote-debugging-port does NOT work on the Default profile.
  Official path for agents to use your signed-in Chrome:

    1. Start normal TaskBar Google Chrome (no special flags).
    2. Open chrome://inspect/#remote-debugging and enable remote debugging.
    3. Agent MCP uses chrome-devtools-mcp --autoConnect.
    4. Click Allow when Chrome prompts.

  This script does NOT launch a second Chrome and does NOT ForceRestart by default.
  Use -OpenRemoteDebuggingPage to open the enable page in your default browser handler.

.LINK
  https://developer.chrome.com/blog/chrome-devtools-mcp-debug-your-browser-session
  https://developer.chrome.com/blog/remote-debugging-port
#>
[CmdletBinding()]
param(
    [switch]$OpenRemoteDebuggingPage
)

Write-Host @"
Chrome DevTools MCP — authenticated (fleet standard)
----------------------------------------------------
MCP id:  chrome-devtools
Flags:   --autoConnect  (NOT --isolated, NOT 9222 on Default profile)

Owner checklist:
  [1] TaskBar Google Chrome is running (your normal Sarosh/Gmail profile).
  [2] Visit chrome://inspect/#remote-debugging  and enable remote debugging.
  [3] New agent session (Grok/Claude/Cursor/Codex/Gemini) so MCP reloads.
  [4] First browser tool call → click Allow on Chrome's permission dialog.
  [5] list_pages should show YOUR tabs, not only about:blank.

QA blank browser: use MCP id chrome-devtools-isolated (--isolated).

Docs: C:\Repos\shmindmaster\agenthub\docs\CHROME_CDP.md
"@

if ($OpenRemoteDebuggingPage) {
    Start-Process "chrome://inspect/#remote-debugging"
    Write-Host "Opened chrome://inspect/#remote-debugging (if Chrome is default handler)."
}

$chrome = Get-Process -Name chrome -ErrorAction SilentlyContinue
Write-Host "Chrome processes running: $($chrome.Count)"
exit 0
