# Proposal: Windows UI Automation Capability & Windows-MCP Evaluation

**Status:** Proposed  
**Date:** 2026-10-21  
**Target:** SH-DESKTOP (Windows 11 Pro, Single Interactive Workstation)  
**Scope:** Autonomous Desktop Application Driving (Codex Desktop App, PowerToys, Outlook, Native Windows Tools)  
**Author:** AgentHub Architecture & Capability Review

---

## 1. Executive Summary & Recommendation

### The Objective
Coding agents operating across the AgentHub fleet (Claude Code, Codex CLI, Gemini CLI, Cursor, OpenCode) require the capability to inspect and drive native desktop applications on this Windows 11 machine without relying on Anthropic's proprietary computer-use beta. Specifically, agents need to interact with applications such as the **Codex desktop app**, **PowerToys**, **Outlook**, and native system utilities where standard web, DOM, or CLI interfaces are unavailable.

Today, an orchestrator session successfully validated direct Windows desktop automation using raw Windows UI Automation from PowerShell via .NET:
```powershell
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
# Find window via AutomationElement.RootElement.FindAll(...)
# Invoke sidebar controls via InvokePattern
# Insert text into composer via ValuePattern.SetValue(...)
# Dispatch action via [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
```
This proved that native Windows UI Automation (UIA) can drive target applications deterministically, with zero additional background daemons, zero network telemetry, zero window flashing, and complete compliance with local process policies.

### Evaluation of Upstream Alternatives
We evaluated **`CursorTouch/Windows-MCP`** (packaged Python-based FastMCP server exposing UI automation, screenshots, and system tools) and **`trycua/cua`** (sandboxed VM and container agent framework).

### The Recommendation

1. **Short-Term / Fleet-Standard Recommendation: AgentHub-Native UI Automation Provider (`packages/windows-ui-automation`)**
   - Package the raw PowerShell/.NET `System.Windows.Automation` approach proven today into a dedicated, deterministic CLI and skill package (`Invoke-WindowsUIAutomation.ps1` in a new `packages/windows-ui-automation`).
   - **Rationale:** 
     - **Zero dependency burden:** Uses built-in Windows .NET assemblies (`UIAutomationClient`, `UIAutomationTypes`, `System.Windows.Forms`). Does not require Python 3.14 toolchains, `comtypes`, `pywin32`, or DirectX capture libraries.
     - **Zero security blast radius:** Exposes only targeted window discovery, element patterns (`InvokePattern`, `ValuePattern`, `SelectionItemPattern`), and text dispatch. Does not bundle arbitrary PowerShell execution, registry tampering, or file system backdoors.
     - **Deterministic execution:** Runs synchronously in-process with the agent's existing PowerShell runner; leaves no orphan background daemons, creates no overlay windows, has no stuck modifier keys from C-level keyboard hooks, and sends zero telemetry beacons.
     - **Policy perfect fit:** Inherently satisfies the mandatory "capability-invoked start only", "no login start", and "hidden window" constraints.

2. **Conditional Alternative: Sandboxed `CursorTouch/Windows-MCP` On-Demand MCP Registration**
   - If interactive vision-guided screenshot clicking, cross-app drag-and-drop, or browser DOM bridging (`use_dom=True`) is explicitly required beyond accessibility tree manipulation, register `CursorTouch/Windows-MCP` under `registry/mcps.json` **strictly as an on-demand, heavily sanitized local MCP server**.
   - **Mandatory Hardening:**
     - Must explicitly strip dangerous tools via CLI flags: `--exclude-tools PowerShell,Registry,FileSystem,Process,Scrape`.
     - Must disable physical input takeover hooks and overlay indicator windows via `--no-control` (avoiding UIA tree stalls and `comtypes.gen` startup race conditions).
     - Must suppress visual screenshot flash windows via `WINDOWS_MCP_DISABLE_FLASH=1`.
     - Must disable telemetry via `ANONYMIZED_TELEMETRY=false`.
     - Must NEVER be installed as a login task or background service (`windows-mcp install` is strictly prohibited).

3. **Rejection of `trycua/cua` for Single Live Windows Desktop**
   - `trycua/cua` is architecturally rejected for this workstation. It is an isolated VM and container framework (macOS Lume and Linux gVisor/Docker). Running isolated VMs or container sandboxes cannot drive the user's live Windows 11 desktop applications and would violate the machine's strict concurrency policy (`SH-DESKTOP hard-locks when graphics work, coding hosts, and local models run together...`).

---

## 2. Technical Evaluation: `CursorTouch/Windows-MCP`

- **Repository:** `https://github.com/CursorTouch/Windows-MCP`
- **Maintainer:** CursorTouch (Jeomon George)
- **License:** MIT License
- **Version Evaluated:** v0.8.8 (PyPI) / Git commit `d13c9bb` (2026-10-21)
- **Architecture:** Python package built on `FastMCP` (v3.0+), wrapping `Python-UIAutomation-for-Windows` via `comtypes`, Win32 user32/gdi32/kernel32 APIs, and screen capture libraries (`dxcam`, `mss`, `Pillow`).

### 2.1 What It Exposes

Windows-MCP exposes 21 distinct MCP tools categorized into four functional groups:

| Category | Tools | Capabilities & Implementation |
|---|---|---|
| **Input & Control** | `Click`, `Type`, `Scroll`, `Move`, `Shortcut`, `Wait`, `WaitFor` | - Coordinates `[x, y]` or integer `label` referencing elements from `Snapshot`.<br>- Mouse clicks: left, right, middle; single, double, hover.<br>- `Type`: text injection with optional `clear=True`, `press_enter=True`, caret positioning (`start`, `idle`, `end`).<br>- `Move`: hover or atomic drag-and-drop (`from_loc` to `loc`, interpolation over `duration`).<br>- `Shortcut`: virtual key combinations (`ctrl+c`, `alt+tab`, `win+r`).<br>- `WaitFor`: polling UIA tree internally until conditions (`text_exists`, `active_window`, `element_exists`, `element_enabled`, `focused_element`) match without client roundtrips. |
| **Inspection & Vision** | `Snapshot`, `Screenshot`, `DisplayInventory`, `ControlStatus` | - `Snapshot`: full desktop state capture. Builds UIA tree of interactive elements with assigned integer labels, focused window, scrollable regions, and optional DOM-mode for Chrome/Edge/Firefox. Supports optional screenshot with annotated bounding boxes.<br>- `Screenshot`: fast capture bypassing UIA tree traversal. Supports multi-monitor indices (`display=[0,1]`) and bounding rectangles (`region=[l,t,r,b]`).<br>- `DisplayInventory`: enumerates monitor layout, virtual desktop bounds, DPI scale factors.<br>- `ControlStatus`: reports desktop lease ownership (`ai` vs `user`) and takeover cooldown state. |
| **System Execution** | `PowerShell`, `App`, `Process`, `FileSystem`, `Registry` | - `PowerShell`: executes arbitrary PowerShell scripts on the host.<br>- `App`: launches apps by Start Menu localized display name or executable path; resizes, moves, switches windows.<br>- `Process`: lists running processes or terminates them by PID/name.<br>- `FileSystem`: reads, writes, copies, deletes, searches files/directories.<br>- `Registry`: reads, writes, deletes, lists Windows Registry keys/values. |
| **Utilities & Network** | `Clipboard`, `Notification`, `Scrape` | - `Clipboard`: reads and writes UTF-16 text and HTML formats.<br>- `Notification`: sends native Windows toast notifications.<br>- `Scrape`: web scraper with basic SSRF protection (blocks private IP ranges and local loopback). |

#### Element Discovery Mechanism
Element discovery is performed via Microsoft UI Automation COM interfaces:
- Connects to `UIAutomationCore.dll` using `comtypes.client.CreateObject("{ff48dba4-60ef-4201-aa87-54103eef594e}")` (`CUIAutomation` / `IUIAutomation`). For newer TextEdit changed handlers, it instantiates `CUIAutomation8` (`IUIAutomation3`).
- Uses `RawViewWalker` and `CreateCacheRequest` to walk child elements.
- Extracts control properties: `Name`, `ControlType`, `AutomationId`, `BoundingRectangle`, and supported patterns (`InvokePattern`, `ValuePattern`, `SelectionItemPattern`, `ExpandCollapsePattern`).
- **DOM Mode (`use_dom=True`):** In Chromium-based browsers (Chrome, Edge), it navigates into the `RootWebArea` accessibility node and filters out browser toolbars/tabs to expose only web elements. In Firefox, it falls back to `IAccessible2`.
- **Exclusion Filter (`WINDOWS_MCP_EXCLUDE_PROCESSES`):** Allows excluding specific process names (e.g. `Code.exe,Cursor.exe`) from traversal to mitigate UIA tree crawl freezes.

#### Screenshot Pipeline
- Employs a multi-backend fallback chain: `dxcam` (DirectX Desktop Duplication API for hardware-accelerated GPU capture) -> `mss` (fast multi-monitor capture) -> `Pillow` (Win32 GDI `BitBlt` capture).
- Supports virtual desktop coordinate cropping (`region=[left, top, right, bottom]`) and downscaling (`WINDOWS_MCP_SCREENSHOT_SCALE=0.5`).
- **Visual Artifacts:** By default, it renders an orange-red glowing transparent border window over the captured region as visual confirmation. This behavior must be suppressed in headless agent environments via `WINDOWS_MCP_DISABLE_FLASH=1`.

#### Keyboard & Mouse Simulation
- Directly calls Win32 `user32.dll` APIs: `SendInput`, `mouse_event`, `SetCursorPos`, and `keybd_event`.
- Translates coordinates to virtual desktop space (`MOUSEEVENTF_VIRTUALDESK | MOUSEEVENTF_ABSOLUTE`).
- Implements physical input takeover detection via low-level Windows hooks (`WH_MOUSE_LL`, `WH_KEYBOARD_LL`). When physical user input exceeds a threshold (500 device units) or `Ctrl+Alt+Shift+Backspace` is pressed, AI control pauses for a 10-second idle timeout.

---

### 2.2 Runtime Requirements

1. **Operating System:** Windows 10 (Build 19041+) or Windows 11.
2. **Python & Packaging:**
   - **Upstream pyproject metadata:** Specifies `requires-python = ">=3.14"` (updated in commit `e597bbc` / PR #364).
   - **Local Host Reality:** SH-DESKTOP is running `Python 3.13.15` and `uv 0.13.3`.
   - **Impact:** Running `uvx windows-mcp serve` forces `uv` to download and maintain an isolated standalone Python 3.14 toolchain, adding ~100MB of runtime cache. Alternatively, running from source allows execution under Python 3.13 without issues.
3. **Node.js:** Not required. Windows-MCP is pure Python with compiled C extensions (`comtypes`, `dxcam`, `Pillow`, `pywin32`).
4. **Privileges & Elevation:**
   - Does **not** require Administrator elevation for standard user-space automation.
   - **UIPI Limitation:** Due to Windows User Interface Privilege Isolation (UIPI), a non-elevated Windows-MCP process cannot send input messages (`WM_COMMAND`, `SendInput`) or attach UIA events to applications running elevated ("Run as Administrator").
   - Running Windows-MCP as Administrator is strongly discouraged, as any connected agent would gain unconstrained system-level execution.
5. **Display & Session Requirements:**
   - Requires an active, interactive Windows desktop window station (`winsta0\default`).
   - Fails if the workstation is locked, running in a headless SSH session without a GUI station, or disconnected from RDP (DirectX Duplication API and `GetDC` fail with access denied).

---

### 2.3 Launching for Claude Code and Codex CLI

#### Claude Code
Claude Code registers stdio MCP servers via its CLI command.

**Hardened Registration:**
```shell
claude mcp add --transport stdio windows-mcp `
  -e ANONYMIZED_TELEMETRY=false `
  -e WINDOWS_MCP_DISABLE_FLASH=1 `
  -e WINDOWS_MCP_EXCLUDE_TOOLS=PowerShell,Registry,FileSystem,Process,Scrape `
  -- uvx windows-mcp@0.8.8 serve --no-control
```
*Note: Using `--no-control` disables the background takeover hooks and indicator windows, preventing UIA traversal slowdowns.*

#### Codex CLI
In `%USERPROFILE%\.codex\config.toml`:
```toml
[mcp_servers.windows-mcp]
command = "uvx"
args = [
  "windows-mcp@0.8.8",
  "serve",
  "--no-control",
  "--exclude-tools",
  "PowerShell,Registry,FileSystem,Process,Scrape"
]

[mcp_servers.windows-mcp.env]
ANONYMIZED_TELEMETRY = "false"
WINDOWS_MCP_DISABLE_FLASH = "1"
```

---

### 2.4 Licence & Community Health

- **License:** MIT License (Permissive, commercial and private use authorized).
- **Maintenance Activity:** Very active repository (~9,850 stars, ~1,000 forks). Pushed commits are frequent (latest commits October 20-21, 2026 covering IME support, UIA handle filtering, and dependency upgrades).
- **Open Issues (30 open):** Several open issues highlight operational vulnerabilities on Windows 11:
  - **Issue #483:** *Modifier keys can be left stuck down:* `Shortcut()`, `MultiSelect()`, and `Scroll()` can leave `Ctrl`, `Alt`, or `Shift` pressed if the command fails mid-execution or is interrupted, severely corrupting the physical desktop session.
  - **Issue #478:** *Indicator render failure leaves controller permanently unavailable:* Transparent overlay windows can crash under Windows 11 Smart App Control or when PIL font rendering fails.
  - **Issue #476:** *Overlay windows stall UIA tree traversal:* Creating overlay windows in the server process adds top-level HWNDs that slowed `Snapshot` from 0.5s to 15.2s until patched.
  - **Issue #412:** *Startup race condition on `comtypes.gen`:* Multiple MCP instances launching simultaneously trigger file lock collisions in the shared COM typelib cache.
  - **Issue #416:** *Hybrid GPU crash:* Display-filtered screenshots crash with `IndexError` on multi-GPU setups.

---

### 2.5 Security Concerns for an Always-Available Input Server

Deploying Windows-MCP as an ambient, persistent service poses severe security risks:

1. **Extreme Blast Radius / Over-Privileged Surface:**
   The inclusion of `PowerShell`, `FileSystem`, and `Registry` bypasses all agent containment. An agent tasked with a simple UI action could execute arbitrary shell commands, overwrite arbitrary files outside the repository root, or alter Windows registry hives.
2. **Ambient Authority & Credential Snooping:**
   An unrestricted screenshot and UIA tool running in the user's interactive session can inspect all active windows. If 1Password, Bitwarden, Outlook, personal banking, or sensitive client documents are visible on any display, an agent can read and exfiltrate their text.
3. **Insecure Upstream Defaults (`windows-mcp install`):**
   Upstream documentation encourages running `windows-mcp install`, which provisions a persistent Windows Scheduled Task (`windows-mcp-server`) that launches at every user logon and writes to `~/.windows-mcp/`. This directly violates AgentHub fleet policy: *"No automatic scheduled jobs for agent, lab, inference, retrieval, or update work: no logon, startup, daily, or repeating scheduled tasks, Run keys, startup-folder entries, or auto-start services."*
4. **Unsolicited Telemetry Beacons:**
   The server bundles `posthog-python` and defaults `ANONYMIZED_TELEMETRY=true`. In an enterprise/fleet environment, outbound telemetry beacons are a compliance risk and must be explicitly disabled via `ANONYMIZED_TELEMETRY=false`.
5. **Physical Session Hijacking & Stuck Keys:**
   Because the server injects real Win32 hardware events, race conditions or aborted tool calls can leave modifier keys (`Ctrl`, `Alt`, `Shift`) pressed down, freezing the developer's physical keyboard until manual recovery.

---

## 3. Framework Comparison: `CursorTouch/Windows-MCP` vs. `trycua/cua`

| Evaluation Dimension | `CursorTouch/Windows-MCP` | `trycua/cua` |
|---|---|---|
| **Core Architecture** | Native Windows host integration via Win32, UIA COM, and Desktop Duplication. | Sandboxed VM and container agent framework (Cua Spaces, Lume, gVisor, Docker). |
| **Primary Platforms** | Windows 10 and Windows 11. | macOS (Apple Silicon / Lume) and Linux containers; Windows support is experimental. |
| **Isolation Model** | None (acts directly on host desktop). | Strong VM / container isolation ("Spaces"). |
| **Ability to Drive Host Windows Apps** | **Yes.** Directly accesses Windows 11 windows (Codex desktop app, Outlook, PowerToys). | **No.** Agents run inside isolated guest VMs or containers; cannot touch the host's Windows 11 window station. |
| **Resource Overhead** | Low memory footprint (~60–120 MB RAM), but runs local Python/COM worker. | Massive overhead (spins up full guest VMs or Docker container daemon). |
| **Machine Concurrency Fit (SH-DESKTOP)** | **Acceptable (when single-instance and on-demand).** Does not violate GPU/virtualization rules. | **Prohibited.** Directly violates machine mandate: *"SH-DESKTOP hard-locks when graphics work, coding hosts, and local models run together... Docker is allowed only when the task is the Duckie stack..."* |
| **Fit for Single Live Windows Desktop** | **Fits the technical interface**, but requires strict security filtering. | **Does NOT fit.** Wrong abstraction for driving live host desktop applications. |

**Verdict:** `trycua/cua` is entirely unsuitable for driving existing native Windows desktop applications on this workstation. `Windows-MCP` mechanically fits the requirement, but its unconstrained surface area requires rigorous fleet governance.

---

## 4. Policy Constraints & Fleet Governance

Any desktop UI automation integration on SH-DESKTOP must adhere to the following mandatory policy constraints:

1. **Capability-Invoked Start Only:**
   - The server must have `activationMode: "on-demand-local"` and `startupEnabled: false`.
   - It must never be started eagerly at agent session launch. It is invoked only when an agent explicitly calls a skill or workflow requiring desktop automation.
2. **Strict Prohibition of Login / Scheduled Tasks:**
   - Upstream's `windows-mcp install` command must **never** be executed.
   - No Scheduled Tasks, Run keys, or auto-start services may be registered.
3. **Zero Screen Takeover / Hidden Window:**
   - Any background process launched by an agent or script must run completely hidden (`CreateNoWindow = true`, `WindowStyle = Hidden`). It must never spawn a visible console window or steal keyboard focus from the user.
4. **Visual Flash & Indicator Suppression:**
   - `WINDOWS_MCP_DISABLE_FLASH=1` must be enforced to eliminate transparent glowing overlay windows.
   - The server must run with `--no-control` to prevent the creation of helper overlay windows that stall UIA tree traversal.
5. **Tool Hardening & Principle of Least Privilege:**
   - Tools that duplicate or bypass standard agent capabilities (`PowerShell`, `FileSystem`, `Registry`, `Process`, `Scrape`) must be excluded via `--exclude-tools`.
6. **Telemetry Opt-Out:**
   - `ANONYMIZED_TELEMETRY=false` must be set in the process environment.
7. **Single Process / Host Serialization:**
   - In accordance with the machine concurrency rule (*"One coding host at a time... multiple hosts must not each spawn their own instance of the same server"*), only one UI automation instance may run at any time.

---

## 5. Registry Entry Specifications

The following entries define the exact schema shapes required for `registry/mcps.json` and `registry/capabilities.json`.

### 5.1 `registry/mcps.json` Specification

```json
{
  "id": "windows-mcp",
  "name": "Windows UI Automation MCP (CursorTouch)",
  "scope": "on-demand-desktop",
  "transport": "stdio",
  "activationMode": "on-demand-local",
  "startupEnabled": false,
  "command": "uvx",
  "args": [
    "windows-mcp@0.8.8",
    "serve",
    "--no-control",
    "--exclude-tools",
    "PowerShell,Registry,FileSystem,Process,Scrape"
  ],
  "env": {
    "ANONYMIZED_TELEMETRY": "false",
    "WINDOWS_MCP_DISABLE_FLASH": "1",
    "WINDOWS_MCP_EXCLUDE_PROCESSES": "Code.exe,Cursor.exe"
  },
  "hosts": [
    "claude",
    "codex",
    "gemini",
    "cursor",
    "opencode"
  ],
  "credentialPolicy": "local-windows-desktop-session",
  "providesCapabilities": [
    "desktop.ui-automation",
    "desktop.inspection"
  ],
  "providesCapabilitiesNote": "Packaged Windows UI Automation desktop driver for native applications (Codex desktop app, PowerToys, Outlook). Strictly excludes PowerShell, Registry, FileSystem, and Process tools in favor of native agent capabilities. Flash overlays and telemetry disabled.",
  "protocol": {
    "revision": null,
    "verifiedOn": "2026-10-21",
    "verification": "Package windows-mcp@0.8.8 is published on PyPI. stdio initialize requires interactive Windows GUI session; left null until live smoke verification."
  },
  "localProcessPolicy": {
    "instancing": "one-process-per-host-session",
    "declaredByHostCount": 0,
    "note": "On-demand local stdio. Must never be registered as an auto-start login task or persistent background service. Concurrency policy prohibits overlapping instances."
  },
  "owner": {
    "type": "capability",
    "id": "windows-ui-automation"
  },
  "hostScopeNote": "hosts[] is eligibility. Pinned on-demand; never persisted to session-start stdio in host configs."
}
```

### 5.2 `registry/capabilities.json` Specification

```json
{
  "id": "windows-ui-automation",
  "owner": "desktop-automation",
  "capabilityType": "plugin+mcp+skills",
  "canonicalSource": "packages/windows-ui-automation",
  "managedSkillNames": [
    "windows-ui-automation"
  ],
  "status": "proposed",
  "notes": "Packaged Windows UI Automation desktop driver. Gated on-demand MCP wrapping Windows UI Automation and native input injection for desktop apps (Codex desktop app, PowerToys, Outlook). Strictly excludes PowerShell/Registry/FileSystem tools and disables overlay flashes.",
  "hostMappings": [
    {
      "hostId": "claude",
      "deploymentStatus": "managed"
    },
    {
      "hostId": "codex",
      "deploymentStatus": "managed"
    },
    {
      "hostId": "gemini",
      "deploymentStatus": "managed-loose-skills"
    },
    {
      "hostId": "cursor",
      "deploymentStatus": "managed"
    },
    {
      "hostId": "opencode",
      "deploymentStatus": "managed-loose-skills"
    }
  ]
}
```

---

## 6. Verification: Safe Smoke Test Procedure

To verify that the MCP server initializes correctly, enforces tool exclusions, and terminates cleanly without modifying the workstation state, run the following automated PowerShell smoke test:

```powershell
<#
.SYNOPSIS
    Non-destructive smoke test for Windows-MCP server in on-demand stdio mode.
.DESCRIPTION
    Launches windows-mcp with hidden console and security exclusions, conducts
    the MCP JSON-RPC initialize handshake, asserts dangerous tools are excluded,
    queries display inventory, and exits cleanly.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# 1. Prepare environment variables
$env:ANONYMIZED_TELEMETRY = 'false'
$env:WINDOWS_MCP_DISABLE_FLASH = '1'

# 2. Configure process start info (Hidden window, stdio redirection)
$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = 'uvx.exe'
$psi.Arguments = 'windows-mcp@0.8.8 serve --no-control --exclude-tools PowerShell,Registry,FileSystem,Process,Scrape'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

Write-Host '[1/4] Spawning windows-mcp process with hidden window...' -ForegroundColor Cyan
$process = [System.Diagnostics.Process]::Start($psi)

try {
    # 3. Send MCP initialize request
    $initRequest = @{
        jsonrpc = '2.0'
        id = 1
        method = 'initialize'
        params = @{
            protocolVersion = '2025-11-25'
            capabilities = @{}
            clientInfo = @{ name = 'agenthub-smoke-tester'; version = '1.0.0' }
        }
    } | ConvertTo-Json -Compress

    Write-Host '[2/4] Sending MCP initialize handshake...' -ForegroundColor Cyan
    $process.StandardInput.WriteLine($initRequest)
    $responseLine = $process.StandardOutput.ReadLine()
    $response = $responseLine | ConvertFrom-Json

    if ($response.result.serverInfo.name -notmatch 'windows-mcp|Windows-MCP') {
        throw "Unexpected server info: $($responseLine)"
    }
    Write-Host " -> Server acknowledged: $($response.result.serverInfo.name) v$($response.result.serverInfo.version)" -ForegroundColor Green

    # Send notifications/initialized
    $initNotification = @{
        jsonrpc = '2.0'
        method = 'notifications/initialized'
    } | ConvertTo-Json -Compress
    $process.StandardInput.WriteLine($initNotification)

    # 4. Query tools list and verify exclusions
    Write-Host '[3/4] Querying tools/list and asserting tool exclusions...' -ForegroundColor Cyan
    $listToolsRequest = @{
        jsonrpc = '2.0'
        id = 2
        method = 'tools/list'
    } | ConvertTo-Json -Compress

    $process.StandardInput.WriteLine($listToolsRequest)
    $toolsLine = $process.StandardOutput.ReadLine()
    $toolsResponse = $toolsLine | ConvertFrom-Json

    $toolNames = $toolsResponse.result.tools | ForEach-Object { $_.name }
    Write-Host " -> Registered tools count: $($toolNames.Count)" -ForegroundColor Gray

    # Assertions
    $prohibitedTools = @('PowerShell', 'Registry', 'FileSystem', 'Process', 'Scrape')
    foreach ($tool in $prohibitedTools) {
        if ($toolNames -contains $tool) {
            throw "Security assertion failed: prohibited tool '$tool' is registered!"
        }
    }
    Write-Host ' -> Security assertion passed: All prohibited system tools are excluded.' -ForegroundColor Green

    # Verify expected UI automation tools exist
    $requiredTools = @('Click', 'Type', 'Snapshot', 'Screenshot', 'DisplayInventory')
    foreach ($tool in $requiredTools) {
        if ($toolNames -notcontains $tool) {
            throw "Functional assertion failed: required tool '$tool' is missing!"
        }
    }
    Write-Host ' -> Functional assertion passed: Required UI automation tools are present.' -ForegroundColor Green

} finally {
    Write-Host '[4/4] Tearing down test process...' -ForegroundColor Cyan
    if (-not $process.HasExited) {
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(3000)) {
            $process.Kill()
        }
    }
    Write-Host ' -> Process cleanly terminated.' -ForegroundColor Green
}
```

---

## 7. Installation & Operational Steps (If Adopted)

If the decision is made to adopt Windows-MCP under the conditional alternative:

1. **Verify Prerequisites:**
   - Confirm Astral `uv` is available on the machine (`uv --version`).
   - Do **not** install system-wide packages or persistent services.
2. **Package Registration:**
   - Create `packages/windows-ui-automation/` with `plugin.json` and `.mcp.json` referencing the hardened configuration.
   - Add the capability row to `registry/capabilities.json` and server row to `registry/mcps.json`.
3. **Execution Safety Protocol:**
   - Always run the server with `--no-control` to prevent indicator freezes and keyboard hook latching.
   - In any agent workflow that invokes desktop driving, check `Get-Process -Name python, uv` afterwards to verify no orphaned processes remain.
