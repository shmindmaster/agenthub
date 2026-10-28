# Host memory audit: SH-DESKTOP, 2026-10-28

Read-only investigation of why the coding-agent hosts use so much RAM and start
so many processes, and what it takes to run the macOS Tahoe VM
(`D:\VMs\macOS-Tahoe-AMD`, `memsize = "10240"`) next to one coding host.
Nothing was killed, stopped or reconfigured. The three running Claude sessions
and the VM were left alone. Command lines were redacted at capture time; no
secret value appears here.

Status of everything below: **measured and proposed**. No fix is applied.

## Summary

| | available RAM | committed |
|---|---|---|
| t00 11:26, VM just booted, 5 Claude sessions + Codex + Copilot | **6,445 MB** | 44,344 MB |
| 11:32, VM stopped (macOS session's boot loop) | 9,275 MB | 34,150 MB |
| t20 11:46, VM off | 5,367 MB | 39,759 MB |
| t40 12:06, VM off, Codex grown to 10.9 GB | **4,416 MB** | 44,027 MB |
| Projected from t40 after F1, F4, F7, F8, F13 (VM off, same Claude sessions) | ~18,000 MB | — |
| Projected also with F2 (2 Claude sessions) and F5 | ~20,000 MB | — |
| Needed to start the VM safely | ≥ 12,000 MB | — |

The VM needs about 10.2 GB (measured as the commit drop when it stopped).
Today there is no headroom for it beside three coding hosts: Claude desktop
with five sessions, the Codex desktop app and the Copilot CLI. One host plus
the fixes below leaves 6–8 GB to spare after the VM's 12 GB.

Top five fixes by memory: (1) quit the Codex app when Claude is the host,
5.3 GB at t00 and 10.9 GB at t40, because it keeps growing while it works; (2) cap Claude sessions at two and archive finished ones, ~0.45 GB
each, 1.35 GB for three; (3) close unused Claude desktop panes, ~1 GB;
(4) stop Codex's per-thread MCP copies (`aws-mcp` with a Duckie production
profile, data-analytics, computer-use), 1.1–2.8 GB while Codex is open; (5) close
the two leftover Playwright CLI daemons and their Chrome instances, ~1.6 GB. Then the
Copilot CLI (0.7–1.1 GB). Total ≈ **16 GB** coding-host related at t40.

Buy (verified live at 12:11): the only 64 GB path inside $400 is adding a matching
new Crucial Pro 2 × 16 GB `CP2K16G60C36U5B` at Micro Center for $399.99, in store.
It would run at about 4800–5200 with four DIMMs (§10). New 2 × 32 GB kits start at
$999.99 on Newegg. Enabling EXPO is free and gives the current pair its rated 6000 MT/s.
Paging, external drives, ReadyBoost and RAM disks do not add usable memory
here (§9).

## 1. Method

- Snapshot script: `Win32_Process` (PID, parent PID, command line, working
  set, private page count, creation time) joined with `Get-Process`, plus
  `Win32_PerfFormattedData_PerfOS_Memory` for available and committed memory.
  Taken at 11:26 (t00), 20 minutes later (t20) and 40 minutes later (t40).
- Attribution: each process is walked up its parent chain to a host root
  (Claude desktop `WindowsApps\Claude_*`, Codex desktop `OpenAI.Codex_*\ChatGPT.exe`,
  Windows Terminal → Copilot CLI, Chrome, Slack, VMware). Claude Code CLI children
  are mapped to their session through `--resume=<id>` and the project folder that
  holds that transcript. Processes whose launcher has exited (detached on
  purpose) are listed as "Shared (detached)".
- Class: each process is matched on its command line to an MCP server or helper
  (RepoWise bridge, AWS MCP proxy, Codex data-analytics, and so on).
- Configs: the Claude desktop, Claude Code, Codex, Copilot CLI, VS Code
  Insiders, Cursor, OpenCode and Grok config files were read for enabled MCP
  servers and plugins. Startup entries: all Run/RunOnce keys and their
  StartupApproved state, both startup folders, all 204 scheduled tasks, all 305
  services.
- Delegation: two Haiku 5.5 subagents read the configs and listed the startup
  entries. One Sonnet 5.5 subagent researched board, CPU and SSD specs and RAM
  prices on the web. One Sonnet 5.5 explorer traced what re-creates the sprawl
  (§12). Snapshot capture, attribution, the duplicate tables, the fix ranking
  and this report were done by the Opus 5.5 main session with deterministic
  scripts. Sonnet did not draft the tables: they come straight from the scripts.
- **WS** is working set (resident RAM, includes shared pages, so sums
  overcount a little). **Priv** is private bytes (commit charge, may be partly
  paged out). Use WS when asking "how much RAM is freed by closing this".
  At 11:3x the sum of *private* working sets across all processes was
  14,436 MB, which is the floor that the per-host WS figures overcount from.

Scripts and raw snapshots (redacted) are in the session scratchpad, not in the
repository: `snap.ps1`, `analyze.py`, `compare.py`, `snap-t00.json`,
`snap-t20.json`, `snap-t40.json`.

## 2. Machine state

| | value |
|---|---|
| Physical RAM | 31,622 MB |
| Commit limit (RAM + page file) | 93,062 MB |
| Boot | 10:44 |
| Claude desktop (re)started | 11:10 |
| Codex desktop started | 11:23 |
| VM `vmware-vmx` started | 11:25:30 (36 s before t00), gone by 11:32 |

**VM cost, measured.** Between t00 (VM running, just booted) and 11:32 (VM
stopped by the macOS-VM session's boot loop) committed memory fell from
44,344 MB to 34,150 MB (−10.2 GB) and available rose from 6,445 MB to
9,275 MB. At t00 `vmware-vmx` held only 3.2 GB WS because the guest had touched
little of its RAM; `mainMem.useNamedFile = "FALSE"` means the 10 GB guest is
backed by the page file and becomes resident as the guest touches it. So a
running macOS guest will claim close to the full 10 GB of RAM within minutes.

## 3. Three snapshots (t00 11:26, t20 11:46, t40 12:06)

| metric | t00 | t20 | t40 |
|---|---|---|---|
| available MB | 6,445 | 5,367 | **4,416** |
| committed MB | 44,344 | 39,759 | 44,027 |
| processes | 444 | 549 | **613** |
| VM | running (just booted) | off | off |

Per host, `n / WS MB / priv MB`:

| host | t00 | t20 | t40 |
|---|---|---|---|
| Codex desktop (ChatGPT.exe tree) | 93 / 5,305 / 4,316 | 182 / 8,777 / 8,243 | **240 / 10,904 / 10,631** |
| Chrome (user + Playwright-driven) | 37 / 3,616 / 3,359 | 60 / 6,737 / 5,751 | 71 / 8,579 / 7,403 |
| Claude desktop (app + sessions) | 71 / 6,293 / 6,616 | 65 / 5,705 / 6,102 | 59 / 5,685 / 6,168 |
| Windows and everything else | 224 / 3,868 / 4,898 | 224 / 4,967 / 5,207 | 221 / 4,750 / 5,254 |
| Shared detached (Local-AI retrieve + RepoWise) | 4 / 2,195 / 5,428 | 4 / 1,093 / 4,218 | 4 / 618 / 4,221 |
| Copilot CLI (Windows Terminal) | 6 / 692 / 1,352 | 6 / 730 / 1,390 | 10 / 1,115 / 1,590 |
| Slack | 7 / 428 / 680 | 7 / 363 / 679 | 7 / 376 / 678 |
| VMware | 2 / 3,178 / 78 | 1 / 7 / 4 | 1 / 7 / 4 |

Per class (WS MB, process count in brackets):

| class | t00 | t20 | t40 |
|---|---|---|---|
| Codex app-server(s) | 753 (1) | 2,223 (3) | 2,408 (3) |
| Claude Code CLI sessions | 1,705 (5) | 1,404 (4) | 1,401 (4) |
| Codex `aws-mcp` proxy | 585 (15) | 864 (30) | **1,374 (45)** |
| Codex computer-use | 257 (12) | 660 (29) | 949 (41) |
| Codex app-tools MCP | 224 (8) | 440 (16) | 548 (20) |
| Codex data-analytics MCP | 259 (8) | 408 (14) | 517 (18) |
| RepoWise bridges (all hosts) | 334 (18) | 352 (22) | 385 (26) |
| Claude Terminal-panel shells | 325 (4) | 362 (4) | 337 (4) |
| Desktop Commander | 185 (6) | 134 (6) | 126 (6) |
| Local-AI retrieve | 1,940 | 928 | 531 (priv stays 3,508: Windows trims it while idle) |
| RepoWise shared server | 254 | 166 | 87 (priv 712) |
| Playwright CLI daemons (leftover) | — | 225 (2) + ~1,400 Chrome | 220 (2) + Chrome |

What the trend says:

- **Codex is the growth.** It doubled in 40 minutes (5.3 → 10.9 GB WS) while it
  ran abacare work. It added two nested app-servers, started from
  `node_repl.exe`, and every new thread or app-server started a fresh
  `aws-mcp` + computer-use + app-tools + data-analytics + RepoWise bridge set.
  Nothing is shared and nothing is released while the app stays open.
- **Claude is flat.** About 5.7 GB across 40 minutes. The orchestrator's CLI
  (`f1d2d7da`) was gone by t20, so the app does release some idle CLIs, but the
  other three idle sessions stayed resident throughout.
- **Leftovers accumulate.** Two `playwright-core … cliDaemon.js` processes
  (`abacare-prod-review` 11:32, `abacare-prod-release` 11:40) outlived their
  launchers and keep their Chrome instances up. Still present at t40.
- **Zombies cleared on their own:** the DO KB `ssh … until …` wait loops and the
  macOS-VM watchdog `pwsh` from t00 had exited by t20. A new DO KB wait loop
  (`ssh kb-server "… until …"`, 11:55) was present at t40, which is live work.
- Available memory fell 2 GB over the window with the VM **off**. At t40 the
  machine had 4.4 GB free, against the ~12 GB the VM needs.

## 4. Attribution at t00 (per host, session and class)

| host | session | class | n | WS MB | priv MB |
|---|---|---|---|---|---|
| Claude desktop | app (Electron main, GPU, renderers, utility) | claude.exe | 14 | 3,417 | 2,619 |
| Claude desktop | Duckie handoffs (`34739bb7`, duckie-app) | Claude Code CLI | 1 | 378 | 699 |
| Claude desktop | macOS VM (`ebc2bfcb`, D:\, Fable 5.1) | Claude Code CLI | 1 | 348 | 687 |
| Claude desktop | DO KB repo-sync (`9d4d41d4`, local-ai-platform) | Claude Code CLI | 1 | 341 | 644 |
| Claude desktop | orchestrator (`f1d2d7da`, D:\) | Claude Code CLI | 1 | 322 | 609 |
| Claude desktop | this audit session | Claude Code CLI | 1 | 316 | 582 |
| Claude desktop | Terminal panel shells (`pwsh -NoExit`, one per session pane) | pwsh | 4 | 325 | 159 |
| Claude desktop | app | Desktop Commander (npx → mise → cmd → node chain) | 6 | 185 | 305 |
| Claude desktop | each of the 5 sessions | RepoWise stdio bridge (`pyw` + `pythonw`) | 10 | 177 | 117 |
| Claude desktop | macOS VM | `whp-off-*.ps1` watchdog (hidden pwsh, parent exited) + `ssh macvm` | 2 | 142 | 63 |
| Claude desktop | DO KB, audit, orchestrator | tool shells, git, ssh | ~20 | ~250 | ~100 |
| Codex desktop | app (ChatGPT.exe Electron) | chatgpt.exe | 16 | 2,715 | 2,156 |
| Codex desktop | app-server | codex.exe | 1 | 753 | 708 |
| Codex desktop | 4 loaded threads | `aws-mcp` (uvx → uv → mcp-proxy-for-aws → python ×2) | 15 | 585 | 644 |
| Codex desktop | 4 loaded threads | data-analytics plugin MCP (`./mcp/launch.mjs`) | 8 | 259 | 300 |
| Codex desktop | 3–4 loaded threads | computer-use plugin (node + 3 `node_repl` each, swift helper) | 12 | 257 | 119 |
| Codex desktop | 4 loaded threads | codex-app-tools MCP (`./server.mjs`) | 8 | 224 | 136 |
| Codex desktop | 4 loaded threads | RepoWise stdio bridge | 8 | 157 | 85 |
| Codex desktop | app | primary-runtime node, exec-server, conhosts | 25 | 355 | 167 |
| Copilot CLI | `copilot --yolo` in Windows Terminal, `C:\Repos\shmindmaster\rexa`, since 10:55, 380 s CPU (active) | copilot.exe + loader | 6 | 692 | 1,352 |
| Shared (detached) | Local-AI retrieve, `127.0.0.1:8790` (Jina v5 text, reranker, omni; CUDA) | python uvicorn | 2 | 1,940 | 4,727 |
| Shared (detached) | RepoWise shared server, `127.0.0.1:7339` | python | 2 | 254 | 701 |
| VMware | macOS guest | vmware-vmx | 1 | 3,171 | 73 |
| Chrome | user browser | chrome.exe | 28 | 3,595 | 3,329 |
| Slack | login item | slack.exe | 7 | 428 | 680 |

Totals at t00 by host (WS / priv MB): Claude desktop 6,293 / 6,616 · Codex
desktop 5,305 / 4,316 · Chrome 3,616 / 3,359 · VMware 3,178 / 78 · Shared
detached 2,195 / 5,428 · Copilot CLI 692 / 1,352 · Slack 428 / 680 · everything
else (Windows, Defender, OneDrive, PowerToys, drivers) 3,868 / 4,898.

How the shared processes started: the Codex threads' RepoWise bridges found
7339 down at 11:23:21, ran `Start-RepoWiseShared.ps1` hidden, which started the
Local-AI retrieve service first (11:23:32) because RepoWise fails closed
without its embedder, then the shared server (11:23:46). Both launchers exited,
so both servers have a dead parent by design. This is the capability-invoked
start the policy asks for.

## 5. Duplicates against `registry/mcps.json` `activationPolicy`

Policy (2026-08-04): prefer shared remote; one local process shared across
agents; start a local server from the capability that needs it, not eagerly at
session start.

| duplicate class | copies at t00 | WS MB | one copy | duplicate waste | verdict |
|---|---|---|---|---|---|
| Codex per-thread local MCP set (aws-mcp, data-analytics, computer-use, app-tools, RepoWise bridge) | 4 sets | 1,482 | ~370 | ~1,110 | **Violates** rules 2 and 3: every loaded Codex thread starts its own copy of every stdio server, eagerly, whether the thread uses it or not |
| Codex nested app-servers: at t20, `node_repl.exe` (computer-use / code-mode) had started two more `codex.exe app-server --listen stdio://`, and each started its own full MCP set | t00: 1 app-server, 4 sets · t20: 3 app-servers, ~6 sets | t20: aws 864, computer-use 660, app-tools 440, data-analytics 408, app-servers 2,223 | — | Codex grew 5,305 → 8,777 MB WS in 20 min | **Violates** rules 2 and 3, compounding: sprawl grows with Codex activity |
| `aws-mcp` (`mcp-proxy-for-aws@latest`, `--profile duckie-production`) | 3 (t00), 6 (t20) | 585 (t00), 864 (t20) | 195 | 390–670 | **Violates** rule 2; also a Duckie production AWS profile in the personal global Codex config (client boundary, see §8) |
| Claude Code CLI sessions | 5 | 1,705 | — | per extra session ≈ 450 MB incl. bridge and Terminal shell | Not an MCP duplicate; it is concurrency. See fix F3 |
| RepoWise stdio bridge (Claude 5, Codex 4) | 9 bridges / 18 processes | 334 | 37 | ~300 | **Compliant by design**: thin stdlib proxy per session, one heavy shared server. Not worth changing (the bridge is what starts the server on demand) |
| Desktop Commander | 1 chain of 6 processes | 185 | — | 185 | **Violates** rule 3: started eagerly by the Claude desktop app at launch through `npx -y @wonderwhy-er/desktop-commander@latest`; not in `registry/mcps.json` at all |
| Terminal-panel `pwsh -NoExit` | 4 | 325 | — | ~80 per session | Desktop app behaviour, one per session that opened a Terminal pane |
| Remote MCPs (context7, exa, firecrawl, notion, linear, railway, descript) configured in 7 hosts | 0 local processes | 0 | — | 0 | **Compliant**: remote HTTP, no local RAM. The Claude CLI log cache shows 32 connects each today, which costs network, not memory |
| `windows-mcp` default-on in Cursor | 0 now | 0 | — | starts once per Cursor session | Latent; Cursor not running |

## 6. Zombies, leftovers and forbidden auto-starts

Processes with a dead parent (t40 list in §3 confirms or clears each):

| process | owner | WS MB | assessment |
|---|---|---|---|
| Local-AI retrieve (8790), RepoWise shared (7339) | shared | 2,194 | Detached on purpose; owner policy says leave running |
| `pwsh -WindowStyle Hidden -File D:\VMs\macOS-Tahoe-AMD\outputs\whp-off-*.ps1` + `ssh macvm` | macOS VM session | 142 | Live work of a running session (VM boot loop). Leave until that session ends, then confirm it exited |
| `ssh kb-server "until … systemctl show kb-repo-sync … do sleep"` ×2 | DO KB session | 14 | Wait loops whose bash parent exited. They end when the remote condition flips; recheck after that session ends |
| `WindowsTerminal.exe` → Copilot CLI | owner | 692 | Not a zombie: an interactive host the owner opened at 10:55 |

Auto-start entries, checked against the owner's policy:

| entry | where | state | policy |
|---|---|---|---|
| GoogleDriveFS `--startup_mode` | HKCU Run, StartupApproved enabled | running (35 MB) | **Conflicts**: "do not turn Google Drive back on at login" |
| Gemini (GeminiAppLauncher), `openAtLogin = true` | HKCU Run + app setting | not running at t00 | Conflicts with no-auto-start intent for agent hosts |
| Codex automation "Daily career and business opportunity review" | `~\.codex\automations\…\automation.toml`, `kind = "heartbeat"`, `FREQ=DAILY;BYHOUR=9`, `status = "ACTIVE"` | fires when Codex is open | **Conflicts**: no repeating scheduled agent jobs |
| CodexSandboxService (OpenAI.Codex) | service, Auto, running | small | Host's own sandbox service; vendor mechanism, report only |
| CoworkVMService (Claude, `cowork-svc.exe`) | service, Auto, running | 13 MB | Host's own service; vendor mechanism, report only. `vm_bundles` holds 9.8 GB on disk, no VM running |
| Apple Mobile Device Service | service, Auto, running | 5 MB | iTunes family; iTunesHelper itself has no Run value |
| VMAuthd, VMUSBArb, VMnetDHCP, VMware NAT | services, Auto, running | ~25 MB | Needed for the VM. vmware-tray has no Run value (compliant) |
| Docker Desktop | HKCU Run, StartupApproved **disabled**; service Manual, stopped | — | Compliant |
| WingetUI `--daemon` (UniGetUI) | HKCU Run, enabled | 78 WS / 379 priv | Not agent-related; candidate to disable |
| Slack, Teams, Cluely, IDM, Chrome auto-launch, OneDrive, Outlook reminders | Run / startup folder | Slack 428 WS running; others small or not running | Not agent-related; OneDrive stays by policy |
| MSIAfterburner, PowerToys, OneDrive startup | scheduled tasks, at logon | small | Not agent-related |
| Zoom (hourly), Google Updater (hourly), OneDrive (daily) | scheduled tasks | — | Vendor update mechanisms: out of scope, untouched |
| node, python, Ollama, RepoWise, Local-AI, AgentHub | Run, folders, tasks, services | checked-absent | Compliant |

## 7. Enabled MCP servers per host (local processes only matter for RAM)

| host | local stdio servers enabled | remote / loopback HTTP | candidates to move |
|---|---|---|---|
| Claude desktop app | Desktop Commander (local desktop MCP; toggles file lists `local:desktop-commander:*` and `local:deskcmd:*`). Source config not found in `claude_desktop_config.json` (no `mcpServers`), `Roaming\Claude` (marker only) or a Claude Extensions folder. 13 local tool groups listed in `mcp-user-tool-toggles.json` (azure, Kubernetes, playwright, shadcn, ElevenLabs…), enabled state not recorded in that file | ~35 claude.ai connectors | Remove Desktop Commander or make it on-demand |
| Claude Code | 1: `repowise-workspace` (bridge) | context7, exa, firecrawl (user), notion (plugin); supabase and descript plugins on but server denied | None. Claude Code is already lean |
| Codex desktop / CLI | `aws-mcp` (global `[mcp_servers]`), `node_repl` (global), plugin stdio: `codex_app`, `cua_repl` (computer-use), `data` (data-analytics), `repowise-workspace` | context7, exa, firecrawl, railway, n8n (Pendoah tenant), open-connector (loopback 3400), ~15 remote plugin servers | `aws-mcp` out of the global config; data-analytics and computer-use off unless used |
| Copilot CLI | 0 | 7 remote | None |
| VS Code Insiders | 0 | 7 remote | None |
| Cursor | `windows-mcp` (default-on) | 8, incl. n8n Pendoah tenant | `windows-mcp` to on-demand |
| OpenCode | 0 enabled (5 stdio disabled) | 7 remote + RepoWise HTTP 7339 | None |
| Grok | 0 in config.toml (plugin servers not parsed) | 8 | Not established |

## 8. Boundary flags found on the way (not memory, owner decision)

- Codex global `[mcp_servers.aws-mcp]` runs `mcp-proxy-for-aws@latest … --profile duckie-production`
  in every Codex thread, including personal ones. That is a Duckie client
  production identity in a personal host's global config, and `@latest` is an
  unpinned package fetched at start. Move it to the Duckie repo's project config
  or disable it (fix F3).
- Codex and Cursor both carry `n8n` → `pendoah.app.n8n.cloud` globally (Pendoah
  tenant).

## 9. Fixes, ordered by memory recovered

WS figures are from t00. "Owner" means a UI action or a decision only he can
make; "script" means a ready-to-run block below. **Nothing here has been
applied.** The orchestrator relayed a request to apply them, but this session
does not change host or system configuration on a peer session's request. The
owner can authorise it directly in this session.

| # | fix | recovers (WS) | who | reboot / admin |
|---|---|---|---|---|
| F1 | Run one coding host at a time: quit the Codex desktop app while Claude is the working host | **5,305 MB at t00, 10,904 MB at t40** (it grows while it works) | owner | no |
| F2 | Archive finished Claude sessions and cap concurrent sessions at 2 while the VM runs. Idle sessions keep their CLI resident: at 11:35 all four other sessions were idle (`isRunning: false`) yet each still held ~350 MB WS / ~650 MB priv, a RepoWise bridge and a Terminal-panel shell. The desktop app restarted all four CLIs within 20 s of its own launch at 11:10 | **~450 MB per session**; 3 sessions ≈ 1,350 MB | owner / orchestrator | no |
| F3 | Codex: disable `aws-mcp` globally (re-enable per Duckie project), turn off the data-analytics and unified-computer-use plugins unless used. Removes the per-thread copies | ~1,100 MB at t00, **~2,800 MB at t40** (aws 1,374 + computer-use 949 + data-analytics 517) while Codex is open (0 if F1) | script + owner (Codex Plugins UI) | no |
| F4 | Close the Copilot CLI (`copilot --yolo`, open since 10:55) when its task is done | 692 MB (1,352 priv) | owner | no |
| F5 | Claude desktop: close panes you are not using (Browser pane, previews, side-session views). There is one top-level window, but three extra renderers were created at 11:11, 11:14 and 11:23 | ~1,000 MB (likely, attribution by creation time) | owner | no |
| F6 | Chrome: Memory Saver set to Maximum (`chrome://settings/performance`), close idle tabs before starting the VM | part of 3,595 MB | owner | no |
| F7 | Claude desktop: disable Desktop Commander (Settings → Extensions/Connectors → local). It starts eagerly at app launch through `npx …@latest` (6 processes) and duplicates Claude Code's own file and shell tools | 185 MB (305 priv) | owner (its config source was not found on disk) | no |
| F8 | Login items: disable GoogleDriveFS (policy), Gemini (and its `openAtLogin`), WingetUI daemon; optionally Slack | ~110 MB now (Drive 35, UniGetUI 78); Slack +428 | script | no (next logon) |
| F9 | Pause the Codex "Daily career and business opportunity review" heartbeat automation | 0 MB now; removes a scheduled agent job | owner (Codex Automations UI) | no |
| F10 | VMware: "fit all VM memory into reserved host RAM" plus no guest page trimming, so a low-memory host refuses to power the VM on instead of paging it to a hard lock; optionally `memsize` 10240 → 8192 | 2,048 MB if memsize is lowered; otherwise stability, not MB | script (VM must be off) | no |
| F11 | Page file: **keep the placement, fix the link.** It is already fixed 4 GB on C: plus system-managed on G: (Samsung 970 EVO Plus, TLC with DRAM, the best of the three for small random writes). But G: links at **PCIe gen 3 x1**, so swap it into M.2_2 (§11). Commit limit is 93 GB against an observed peak of 44 GB, and paging was 3 hard reads/s at 11:36, so the size is fine | 0 MB (faster paging only) | owner (hardware) | power off |
| F13 | Close leftover Playwright CLI daemons when their task is done: `cliDaemon.js abacare-prod-review` (11:32) and `abacare-prod-release` (11:40). Their launchers have exited, but each keeps a Chrome instance running (likely from the Codex abacare work) | **~1,600 MB** (225 node + 1,398 Chrome WS at t20) | owner / the host that opened them (`playwright-cli` session close) | no |
| F12 | Local-AI retrieve holds 1,940 MB WS / 4,727 MB priv with three models (text, reranker, omni) on CUDA. Protected by policy (leave running). Follow-up in `local-ai-platform`: lazy-load the omni model on first multimodal request | est. several hundred MB, not measured | follow-up | no |

**Recoverable without touching protected processes or the running sessions:**
F1 + F4 + F7 + F8 (Drive, UniGetUI) ≈ **6.3 GB WS at t00, 12.3 GB at t40**
(Codex 10.9 + Copilot 1.1 + Desktop Commander 0.13 + login items 0.11). F2 adds
~1.35 GB once the current sessions finish, F5 ~1 GB and F13 ~1.6 GB. Total
coding-host related ≈ **16 GB at t40**, plus Chrome and Slack at the owner's
discretion.

### F2 detail: the policy change

Add to the orchestration guidance (AgentHub `global-agent-policy.md` → Engineering
behavior, next to the one-host rule): "While the macOS VM runs, keep at most two
Claude Code sessions open (one working, one idle). Archive a side session as soon
as its report is in." Whether archiving ends the session's CLI process was not
verified here; check `Get-Process claude` before and after the first archive.

### F3 script: Codex config (user scope, reversible)

```powershell
$cfg = "$env:USERPROFILE\.codex\config.toml"
Copy-Item $cfg "$cfg.bak-20261028-memaudit"
$t = Get-Content $cfg -Raw
# Before: [mcp_servers.aws-mcp] has no enabled key (default on)
$t = $t -replace '(\[mcp_servers\.aws-mcp\]\r?\n)', "`$1enabled = false`r`n"
# Before: enabled = true
$t = $t -replace '(\[plugins\."unified-computer-use@openai-bundled"\]\r?\n)enabled = true', "`$1enabled = false"
Set-Content $cfg $t -NoNewline
# Rollback: Copy-Item "$cfg.bak-20261028-memaudit" $cfg -Force
```

The data-analytics MCP (`openai-curated-remote\data-analytics`) has no
`[plugins]` entry in `config.toml`, so turn it off in the Codex app's Plugins
page. To keep AWS for Duckie, put the same `[mcp_servers.aws-mcp]` block in
`C:\Repos\musa-dev-team\duckie-app\.codex\config.toml` (project-scoped config;
confirm that your Codex build loads project config) and pin the version instead of `@latest`.

### F8 script: login items (HKCU only, takes effect next logon)

```powershell
$k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
# Before (2026-10-28): GoogleDriveFS = 02 (enabled), WingetUI = 02, Gemini = no value (enabled by default)
$off = [byte[]](3,0,0,0,0,0,0,0,0,0,0,0)
foreach ($n in 'GoogleDriveFS','WingetUI','Gemini') {
  New-ItemProperty -Path $k -Name $n -PropertyType Binary -Value $off -Force | Out-Null
}
# Rollback: set the first byte back to 2, e.g.
# New-ItemProperty -Path $k -Name GoogleDriveFS -PropertyType Binary -Value ([byte[]](2,0,0,0,0,0,0,0,0,0,0,0)) -Force
```

Gemini also has `openAtLogin = true` in `%APPDATA%\gemini\settings.json`; turn it
off in the app's settings so it does not re-add itself.

### F10 script: VMware, only when the VM is off

```powershell
$vmrun = 'C:\Program Files\VMware\VMware Workstation\vmrun.exe'
$vmx   = 'D:\VMs\macOS-Tahoe-AMD\macos.vmx'
if ((& $vmrun list) -match [regex]::Escape($vmx)) { throw 'macOS VM is running: stop it first' }
Copy-Item $vmx "$vmx.bak-20261028-memaudit"
$keep  = Get-Content $vmx | Where-Object { $_ -notmatch '^(MemTrimRate|sched\.mem\.pshare\.enable)\s*=' }
# Before: neither key present (VMware defaults: trimming on, page sharing on)
$keep + 'MemTrimRate = "0"' + 'sched.mem.pshare.enable = "FALSE"' | Set-Content $vmx -Encoding ascii
# Optional, owner's call (Xcode builds are slower with less RAM):
# (Get-Content $vmx) -replace '^memsize = "10240"','memsize = "8192"' | Set-Content $vmx -Encoding ascii
# Host preference "Fit all virtual machine memory into reserved host RAM":
$pref = "$env:APPDATA\VMware\preferences.ini"
Copy-Item $pref "$pref.bak-20261028-memaudit"
(Get-Content $pref | Where-Object { $_ -notmatch '^prefvmx\.minVmMemPct' }) + 'prefvmx.minVmMemPct = "100"' | Set-Content $pref -Encoding ascii
# Rollback: copy both .bak-20261028-memaudit files back
```

Trade-off: with `minVmMemPct = 100` VMware will not let the host page the guest
out, so the guest runs at full speed and stays stable. The cost is that it refuses
to power on when 10 GB plus overhead is not free. On a 32 GB host that refusal
is the guard against the hard lock. `MemTrimRate = 0` stops VMware reclaiming
idle guest pages, so the full guest size stays resident while the VM runs.
`sched.mem.pshare.enable = FALSE` stops page-sharing scans (CPU, not RAM, with
one VM). `mainMem.useNamedFile = "FALSE"` is already set, which keeps guest RAM
off a `.vmem` file on D:.

### What does not help, said plainly

- **RAM disk:** takes RAM away. The opposite of what is needed.
- **ReadyBoost:** Windows does not offer it when the system drive is an SSD, and
  it only ever cached reads. Irrelevant here.
- **More page file:** commit is not the limit (44 GB used of 93 GB). Physical RAM
  is. A page file only holds pages nobody is touching. Once the VM guest plus
  the active host working sets exceed 32 GB, the machine thrashes regardless of
  drive speed. Guest RAM under VMware is touched constantly, so paging it out is
  exactly the stall that precedes the hard lock.
- **External drive for paging:** this machine has no USB4 or Thunderbolt
  controller (AMD USB 3.10 and ASMedia USB 3.1 host controllers only). A USB 3.2
  Gen 2 SSD is about 1 GB/s sequential with far worse small-random latency than
  internal NVMe, and a USB disconnect with live pages on it crashes processes or
  bugchecks the system. No external option beats the internal G: drive that
  already holds the page file.
- **Memory compression:** already on (the Memory Compression process held
  726 MB at 11:36). That is Windows' real "extra RAM" and it is working. Leave it.
- **SysMain, visual effects, background-app toggles:** single-digit MB on this
  machine. Not worth the side effects.
- **Electron `--max-old-space-size` style flags:** they cap the JS heap and turn
  memory pressure into renderer crashes. Not recommended.

## 10. Hardware baseline and upgrade options

### Baseline (measured with CIM; board and CPU limits from vendor pages)

| item | value | source |
|---|---|---|
| Board | MSI PRO B850M-VC WIFI6E (MS-7E71), AMD B850, AM5 | `Win32_BaseBoard` |
| CPU | AMD Ryzen 7 7700X | `Win32_Processor` |
| GPU | NVIDIA GeForce RTX 5060 Ti (Local-AI retrieve runs on it) + Radeon iGPU | `Win32_VideoController` |
| RAM | 2 × 16 GB Micron/Crucial Pro DDR5 `CP16G60C36U5B.M8D3` (DDR5-6000 CL36 kit, single-rank), in DIMMA2 and DIMMB2 | `Win32_PhysicalMemory` |
| RAM speed now | **5200 MT/s**: EXPO is off, so the kit runs below its rated 6000 | `ConfiguredClockSpeed` |
| Free DIMM slots | 2 (DIMMA1, DIMMB1) | 4 slots in `Win32_PhysicalMemoryArray` |
| Board max | 256 GB; Ryzen 7700X max **128 GB** | [MSI spec](https://us.msi.com/Motherboard/PRO-B850M-VC-WIFI6E/Specification), [AMD 7700X](https://www.amd.com/en/products/processors/desktops/ryzen/7000-series/amd-ryzen-7-7700x.html) |
| AMD rated speed | 2 DIMMs (1R or 2R): DDR5-5200. 4 DIMMs (1R or 2R): **DDR5-3600** | AMD product page |
| M.2 | 3 slots, all occupied: M.2_1 CPU PCIe 5.0 x4, M.2_2 CPU PCIe 4.0 x4, M.2_3 chipset PCIe 4.0 x2 | MSI spec + 3 NVMe present |
| NVMe drives | C: T-FORCE Z44A7 1 TB (PCIe 4.0, DRAM-less) · D: Sabrent Rocket Q4 2 TB (QLC, writes fall under 100 MB/s after cache) · G: Samsung 970 EVO Plus 2 TB (PCIe 3.0, TLC, 2 GB DRAM, 19K/62K QD1 IOPS) | `Get-PhysicalDisk`, vendor pages |
| USB | Rear: 1 × 10 Gbps A, 1 × 10 Gbps C, 2 × 5 Gbps A, 4 × USB 2.0. Front headers: 4 × 5 Gbps, 1 × USB-C 10 Gbps. **No USB4, no Thunderbolt, no 20 Gbps** | MSI spec; only AMD USB 3.10 + ASMedia USB 3.1 controllers present |
| PCIe | 1 × PCIe 5.0 x16 (GPU), 3 × PCIe 3.0 x1 | MSI spec |
| External SSDs | Crucial X8 2 TB (H:), NVMe in Realtek USB 3.2 enclosure (E:) | `Get-PhysicalDisk` |
| Page file | C: fixed 4,096 MB; G: system-managed, 57,344 MB allocated; peak use 1.7 GB each | `Win32_PageFileUsage` |
| Hypervisor / VBS | Off (VMware needs WHP off for this guest) | `Win32_DeviceGuard`, `HypervisorPresent` |

Free performance win: **enable EXPO in the BIOS** (owner, reboot). It takes the
current pair from 5200 to its rated 6000 MT/s. It adds bandwidth, not
capacity, and AMD rates 6000 as overclocked, so a failed memory training falls
back to defaults.

### RAM shortlist: re-verified by live page fetch, 2026-10-28 12:10–12:12 CDT

The first version of this table came from a research subagent, and two rows were
wrong: one condition and shipping, and one 96 GB listing described as a single
stick. Every row below was re-fetched live from its own product page
(Firecrawl `maxAge: 0` or the retailer's structured live-price provider). Each one
shows the exact part number and the price quoted. Market context from the same
fetches: the **cheapest new 64 GB (2 × 32 GB) DDR5-6000 kit on Newegg is
$999.99**, and the matching 2 × 16 GB kit is $399.99–$569 new.

| option | exact kit (part number) | total after install | speed on this board | condition | price on page | seller | URL |
|---|---|---|---|---|---|---|---|
| **A1. Add a matching pair, new** (keep current 2 × 16) | Crucial Pro 2 × 16 GB DDR5-6000 CL36 `CP2K16G60C36U5B` | 64 GB (4 DIMMs) | AMD-rated 3600 for 4 DIMMs; 4800–5200 usually trains; 6000 often fails | new | **$399.99**, in store only | Micro Center | https://www.microcenter.com/product/677126/crucial-pro-overclocking-32gb-(2-x-16gb)-ddr5-6000-pc5-48000-cl36-dual-channel-desktop-memory-kit-cp2k16g60c36u5b-black |
| A2. same, used | Crucial Pro 2 × 16 GB DDR5-6000 CL36 `CP16G60C36U5B.M8D3` (exact die match) | 64 GB | same | open box ("brand new, opened to look") | $400.00, free shipping, **no returns** | eBay seller ktsandersss | https://www.ebay.com/itm/257821991267 |
| A3. same, new online | `CP2K16G60C36U5B` | 64 GB | same | new | $569.00, free delivery (third-party; 8 offers from $569) | Amazon, sold by Skoodooh | https://www.amazon.com/dp/B0CTHXMYL8 |
| B1. Replace with 2 × 32 GB | G.Skill Trident Z5 Neo `F5-6000J3636F32GX2-TZ5NRW` | 64 GB (2 DIMMs) | 6000 with EXPO | refurbished | $825.00 | Newegg marketplace, 2DaySale | https://www.newegg.com/g-skill-trident-z5-neo-series-64gb-2-x-32gb-ddr5-6000-pc5-48000-cas-latency-cl36-memory-desktop-memory-white/p/0RN-001W-009Y8 |
| B2. Replace with 2 × 32 GB | Crucial Pro `CT64G6000UD5` ("Tested", CL40) | 64 GB | 6000 with EXPO | new (per listing) | $834.36, no returns | eBay seller e_fixdublin | https://www.ebay.com/itm/407220350187 |
| B3. Replace with 2 × 32 GB | Corsair Vengeance RGB `CMH64GX5M2N6000Z40` | 64 GB | 6000 with EXPO | new | $999.99 | Newegg | https://www.newegg.com/corsair-vengeance-rgb-64gb-2-x-32gb-ddr5-6000-pc5-48000-cas-latency-cl40-desktop-memory-gray/p/N82E16820982338 |
| C. Replace with 2 × 48 GB | Crucial `CP48G56C46U5` ×2, DDR5-5600 | 96 GB | 5200 rated / 5600 | used | $1,299.97, 30-day returns | eBay seller L Theory Inc | https://www.ebay.com/itm/117489311599 |
| D. Replace with 2 × 64 GB | G.Skill Ripjaws S5 `F5-6000J3444F64GX2-RS5K` | 128 GB | 5200 rated / 6000 EXPO | new | $3,799.99 | Newegg | https://www.newegg.com/g-skill-ripjaws-s5-series-128gb-2-x-64gb-ddr5-6000-pc5-48000-cas-latency-cl34-desktop-memory-black/p/N82E16820374761 |

Dropped after verification: Newegg `N82E16820156394` (the same `CP2K16G60C36U5B`
kit, $429.99) is **out of stock**. Best Buy `JX8PSKC864` is **no longer
available**. Crucial.com shows the kit but no price, so it is not verified.

**Buy recommendation, ranked by usable memory per dollar:**

1. **A1: Micro Center, $399.99 new, in store** for `CP2K16G60C36U5B`. It is the
   same kit you already have, it is inside the budget and it can be returned.
   **Re-checked 12:2x CDT: SOLD OUT for pickup at both Texas stores** (Dallas,
   `?storeid=131`, and Houston, `?storeid=155`). Watch the product page, or use A2/A3.
   Total 64 GB. Expect DDR5-4800 to 5200 with four DIMMs; set it manually if
   EXPO training fails. Capacity doubles while bandwidth drops a little, and for
   agent hosts plus a 10 GB VM capacity is the constraint.
2. A2 (eBay open box, $400) is the exact die revision, but it has **no returns**.
   Choose it only if no Micro Center store is near.
3. B1–B3: two DIMMs keep 6000 and leave two slots for 128 GB later. They cost
   2–2.5× the budget today.
4. C and D are 3–9× over budget.

### Wider sweep for used, refurbished and open-box options (live, 2026-10-28 12:2x–12:3x CDT)

Searched eBay (Buy It Now, US, sorted by lowest price), Newegg new, refurbished and
open-box, and the Micro Center web store. Each row was opened individually. Amazon
search and the eBay item API both returned provider errors, so those rows come
from fetched item pages only; Amazon Renewed and Warehouse are **not verified**.
B&H used, Best Buy open box and r/hardwareswap were **not checked**.

**Every requested price band came back empty:** no DDR5 2 × 16 GB add-on under
$250 (eBay's cheapest used is $384.99, Newegg's cheapest new $459.99), no
2 × 32 GB kit under $400 (cheapest refurbished $825, cheapest new $999.99), no
2 × 24 GB kit under $300 (cheapest new $709.99). eBay's 64 GB results under $400 were
single 32 GB sticks or DDR4.

Add-on pairs that would run beside the current Crucial pair (all 64 GB total, four DIMMs):

| rank | kit (part number) | condition | price on page | returns | seller (rating) | URL | risk |
|---|---|---|---|---|---|---|---|
| 1 | Corsair Vengeance RGB 2×16 DDR5-6000 CL36 `CMH32GX5M2E6000Z36` | used, "tested and working" | $389.99 + $6.56 | 30 days, buyer pays return shipping | mitchtrub12 (100 %, 452) | https://www.ebay.com/itm/960126351952 | mixed kit: likely SK hynix vs your Micron dies, so expect 4800 or lower and manual tuning; may not train at all |
| 2 | G.Skill Flare X5 2×16 DDR5-6000 CL36 `F5-6000J3636F16GX2-FX5` (AMD EXPO line) | used | $399.99, free shipping | 30 days, seller pays return shipping | PayMore Southfield (99.6 %) | https://www.ebay.com/itm/820288514567 | same mixed-kit risk; seller-paid returns make a failed training cheap to undo |
| 3 | G.Skill Trident Z5 2×16 DDR5-6000 CL36 `F5-6000J3636F16GX2-TZ5K` | used | $399.99, free shipping | 30 days, seller pays return shipping | computer-hq (99.5 %) | https://www.ebay.com/itm/128150802337 | same mixed-kit risk |
| ref | Crucial Pro 2×16 `CP16G60C36U5B.M8D3` (your exact part) | open box | $400.00, free shipping | **none** | ktsandersss | https://www.ebay.com/itm/257821991267 | lowest training risk, no way back |

Micro Center web store (`storeid=029`) for the Crucial pair: $399.99, "In-Store
Pickup Only", shipping not available, no open-box offer, no restock date. Dallas
and Houston are both sold out.

Mixed-kit note: four DIMMs of different brands and dies on AM5 run at the
slowest stick's settings at best. AMD's 4-DIMM rating is 3600, and mixed kits
often settle at 4400–4800 with EXPO off. Same-part-number pairs (the Crucial rows)
train most reliably. Capacity, not speed, is what fixes the VM problem.

### Spec match instead of brand, Best Buy, and the MSI memory list (live, 12:25–12:31 CDT)

Brand matters less than the spec. Two different kits in four slots are less
reliable than one matched kit, though. Safest first: (1) one 2 × 32 GB kit
replacing the current pair, (2) a second identical Crucial pair, (3) a
different-brand pair with the same spec, ideally on the board's memory list.

Target spec: DDR5 UDIMM, non-ECC, 2 × 16 GB, 6000 MT/s, EXPO or XMP, CL36 or better,
1.35 V or lower. "On QVL" means listed on MSI's memory support list for the PRO
B850M-VC WIFI6E (https://www.msi.com/Motherboard/PRO-B850M-VC-WIFI6E/support#mem),
read in full. **Every 6000 MT/s kit on that list is validated for 1 and 2 DIMMs
only, not 4.** Four-DIMM validation appears only on 3600 MT/s JEDEC parts. Your
current `CP16G60C36U5B` is **not** on the list (Crucial appears only with 6400 Pro
kits and JEDEC parts), and it runs fine anyway.

| kit (part number) | spec | on MSI QVL (die) | condition | price on page | returns | seller | URL |
|---|---|---|---|---|---|---|---|
| Corsair Vengeance RGB `CMH32GX5M2E6000Z36` | 2×16, 6000, CL36, 1.35 V | **yes**, 2 DIMMs (Spectek D, Micron's own brand, the same family as your Micron D) | used, tested | $389.99 + $6.56 | 30 days, buyer pays | eBay mitchtrub12 (100 %, 452) | https://www.ebay.com/itm/960126351952 |
| G.Skill Trident Z5 `F5-6000J3636F16GX2-TZ5K` | 2×16, 6000, CL36, 1.35 V | **yes**, 2 DIMMs (Samsung) | used | $399.99, free shipping | 30 days, seller pays | eBay computer-hq (99.5 %) | https://www.ebay.com/itm/128150802337 |
| G.Skill Flare X5 `F5-6000J3636F16GX2-FX5` | 2×16, 6000, CL36, 1.35 V | not listed (sister parts TZ5N/RS5K/TZ5S/TZ5K are) | used | $399.99, free shipping | 30 days, seller pays | eBay PayMore Southfield (99.6 %) | https://www.ebay.com/itm/820288514567 |
| Crucial Pro `CP16G60C36U5B.M8D3` (your part) | 2×16, 6000, CL36 | not listed | open box | $400.00, free shipping | none | eBay ktsandersss | https://www.ebay.com/itm/257821991267 |
| Corsair Vengeance `CMK32GX5M2E6000C36` | 2×16, 6000, CL36 | not listed | **new**, in stock for pickup **today** at Best Buy Park Lane (Dallas, store 58) and ~20 DFW stores | $499.99 (reg. $533.99) | Best Buy standard | Best Buy | https://www.bestbuy.com/product/corsair-vengeance-32gb-2x16gb-ddr5-6000mhz-c36-udimm-desktop-memory-black/J39QHTJQZH |
| Corsair Vengeance `CMK32GX5M2E6000C36` (cheapest new at Newegg) | same | not listed | new | $499.99 | 30 days | Newegg | https://www.newegg.com/corsair-vengeance-32gb-ddr5-6000-cas-latency-cl36-desktop-memory-black/p/N82E16820236994 |

Best Buy notes: the pricing API showed no open-box offer on SKU 6562317. Best Buy's
cheapest 2 × 32 GB is $993.99 (Corsair Vengeance 5200 CL40, SKU 6496083), and its
cheapest 6000 MT/s 2 × 32 GB is $1,059.99. A first Best Buy search scrape landed on
Best Buy's country-selection page, and its extracted "$139–$299" prices were
fabricated by the extractor, so they are not in this table. That is likely how
implausible prices got into earlier drafts.

Until then, the free levers are F1–F8 (about 6–8 GB) and EXPO.

## 11. Is the hardware running at its rated speed?

Measured read-only at 11:5x. Overclocking beyond the vendor's rated profile is
**not recommended** on a machine that already hard-locks under combined load.
Every fix below stays inside a rated profile.

| part | rated | actual | gap | the one change | who | risk |
|---|---|---|---|---|---|---|
| RAM (2 × 16 GB Crucial Pro CP16G60C36U5B) | DDR5-6000 CL36 (EXPO profile) | **5200 MT/s** on both DIMMs (`Speed` and `ConfiguredClockSpeed` both 5200, which is the JEDEC fallback) | −13 % bandwidth | BIOS → OC → **A-XMP/EXPO Profile → "EXPO Profile 1"** (MSI Click BIOS X naming; MSI shows it as "AMD EXPO" on the main screen) | owner (BIOS) | Low. AMD rates 6000 as beyond spec. If training fails, the board falls back to 5200 after a few POST attempts. Turn it off again if the hard locks increase. If four DIMMs are fitted later, leave EXPO off or set 4800 manually |
| CPU (Ryzen 7 7700X) | base 4.5 GHz, boost up to 5.4 GHz | 30 s sample: `% Processor Performance` avg 113 % (≈ 5.1 GHz effective at 32 % load), plan **Ultimate Performance** | none | none | — | — |
| CPU PBO / Eco mode | — | Ryzen Master installed (`C:\Program Files\AMD\RyzenMaster`) but no saved profile file found; HWiNFO64 is installed with no CSV logs, so thermal headroom is **not established** | unknown | Leave PBO at BIOS default. To see headroom, log one HWiNFO session during a build | owner | — |
| GPU (RTX 5060 Ti 16 GB, driver 617.42) | PCIe 5.0 x8, 180 W | PCIe gen 5 x8, power limit 180 W = default = max, P5 idle at 705 MHz, 35 °C. No MSI Afterburner profile folder; an MSIAfterburner logon task exists | none | Optionally remove the MSIAfterburner logon task if no profile is used | owner | — |
| GPU use by Local-AI retrieve | models on CUDA (health reports `text`, `reranker`, `omni` = `cuda`, bf16) | VRAM in use 174 MiB of 16,311, while the retrieve process holds 1–1.9 GB WS / 3.5–4.7 GB private | models may be staged in host RAM, or loaded lazily. **Not established** | Follow-up in `local-ai-platform`: confirm where the weights live after first use and release host-side copies | follow-up | — |
| NVMe C: T-FORCE Z44A7 1 TB | PCIe 4.0 x4 | gen 4 x4 | none | — | — | — |
| NVMe D: Sabrent Rocket Q4 2 TB | PCIe 4.0 x4 | gen 4 x4 | none | — | — | — |
| NVMe G: Samsung 970 EVO Plus 2 TB (**holds the 56 GB page file**) | PCIe 3.0 x4 (3,500 MB/s) | **gen 3 x1** (≈ 985 MB/s) | **−72 % bandwidth** | It is on M.2_3 (chipset, PCIe 4.0 x2), which runs x1 here, so check the board manual for lane sharing with the PCIe x1 slots. Best fix: swap it with the Sabrent, putting the 970 in M.2_2 (CPU 4.0 x4, it runs gen 3 x4) and the QLC Sabrent in M.2_3 (data disk, x2 is fine). Alternative without a screwdriver: move the page file to C: (gen 4 x4, but DRAM-less) | owner (hardware) | Low; same drive letters after a swap. QD1 4K latency, which matters most for paging, is mostly unaffected by lane count, so the page-file gain is modest. The bigger win is large sequential reads and writes on G: |

## 11a. TMPDIR dependency (input for the orchestrator's investigation, nothing changed)

Resolved by the orchestrator session on 2026-10-28. The junction's old entry
had an empty print name, which broke nested directory creation through it. The
junction was recreated and `mktemp` works again. The list below is kept as a
dependency map.

- User-level `TMPDIR = C:\Users\SaroshHussain\AppData\Local\AgentHub\tmp`. Machine
  level is unset. User `TEMP = D:\Local-AI\cache\temp`.
- `%LOCALAPPDATA%\AgentHub` is a junction to `D:\AgentHub` (created 2026-10-23).
  The orchestrator reports that directory creation two levels below it returns
  "File exists" for new names. That is the junction path, not `D:\AgentHub` itself.
- Inherits it: every process started from the user environment that honours
  `TMPDIR`, which in practice means MSYS/Git Bash `mktemp`, Git's own shell helpers and
  OpenSSH under Git Bash. Native Windows tools use `TEMP`/`TMP` instead. Claude
  Code's tool shells export `TEMP`/`TMP` to `D:\Local-AI\cache\temp` but do not
  override `TMPDIR`, so their `mktemp` also lands on the junction.
- Hooks that call `mktemp -d` and so break on push: the fleet pre-push gate in
  `agenthub`, `contact-email-relay`, `lawli`, `local-ai-platform` and `shtrial`
  (`.git/hooks/pre-push`, line `tmpdir="$(mktemp -d)"` in agenthub). No global
  `core.hooksPath` is set.
- Other references: `C:\Users\SaroshHussain\bin\droid.exe` (Factory Droid) and
  Git's `ssh-copy-id`.

## 11b. Checking it yourself

`pwsh -NoProfile -File scripts\Get-HostMemoryReport.ps1` (new, read-only,
on demand) prints RAM per host and per helper class. It flags duplicate
stdio MCP instances, extra coding hosts, Codex nested app-servers, Claude
sessions above two, leftovers whose launcher exited, and how far available
memory is from what the VM needs. `-Json` gives the same data for tooling. At
12:04 it reported: Codex 10.3 GB WS, 3 coding hosts, `aws-mcp` × 8,
2 leftover Playwright daemons, VM short by 5.7 GB.

## 12. Why it comes back

Traced through `scripts/Sync-AgentHub.ps1`, `scripts/Sync-Capabilities.ps1`,
`scripts/lib/*`, `registry/*.json` and `overlays/personal` (Sonnet 5.5 explorer
subagent, read-only), then checked against the live host configs.

| what comes back | mechanism | file:line | does an AgentHub sync re-add it? | durable fix at the source |
|---|---|---|---|---|
| Codex `aws-mcp` (Duckie production profile) | Written outside AgentHub; `--metadata INSTALL_SOURCE=aws-cli` suggests an AWS tool installer. Present in `~/.codex/config.toml:89` **and** `~/.codex/claude.config.toml` (a profile, so switching profiles brings it back), OpenCode (off) and Gemini | not in repo or overlay | No. `Sync-AgentHub.ps1 -Prune` would *remove* it (lines 1352–1377) | Disable it in both Codex profiles (apply script). Durable: record it in `registry/native-connectors.json` as a denied host-configured id so `-Audit` flags it if it reappears (proposed below) |
| Codex per-thread and nested-app-server MCP copies | Codex architecture: every loaded thread and every `app-server` that `node_repl` starts launches every enabled stdio server | Codex internals | No | Fewer enabled stdio servers. Codex has no shared-process mode for stdio MCP |
| Codex computer-use / unified-computer-use / data-analytics | `openai-bundled` and `openai-curated-remote` marketplaces; Codex updates add bundled plugins | `config.toml:77`, `[plugins]` at 148, 211 | No; `Sync-Capabilities.ps1:349-352` skips native-plugin hosts | Codex Plugins UI. Re-check after each Codex update |
| `n8n` (Pendoah tenant) in Codex and Cursor | Hand-added (present in Codex backups dated 10-23 and 10-25) | not in repo | No (`-Prune` would remove it) | Owner decision; boundary issue |
| Cursor `windows-mcp` | Persisted always-on by owner decision 2026-10-28 | `registry/native-connectors.json:40-43`, `registry/mcps.json:486`, written at `Sync-AgentHub.ps1:2279` | **Yes**, every `-Apply` rewrites the whole Cursor entry | Recorded owner decision. Change it only in the registry, never in `~/.cursor/mcp.json` |
| Claude Code remote MCPs (context7, exa, firecrawl) | Merged into `~/.claude.json` | `Sync-AgentHub.ps1:1118-1185` | Yes, by design | None needed: remote, 0 MB |
| RepoWise bridge per session | `packages/repowise/.mcp.json`, started while `repowise@agenthub` is enabled | — | Yes, by design | Keep: thin proxy (~37 MB per session). The heavy server stays single |
| `repowise-augment.exe` hooks (PostToolUse, SessionStart, PostToolUseFailure) | Installed by the `repowise` CLI, not AgentHub | `~/.claude/settings.json` | No | Short-lived per tool call; not a resident cost |
| Desktop Commander in Claude desktop | Account-level desktop local MCP; not in `claude_desktop_config.json` (no `mcpServers`), not in the repo | not found on disk | No | Claude desktop Settings (owner). Source not established |
| Idle Claude Code CLIs | Claude desktop restarts every open session's CLI at app launch (all four within 20 s of 11:10) and keeps idle ones resident | desktop app behaviour | No | Archive finished sessions; cap open sessions (policy F2) |
| Playwright CLI daemons | `playwright-cli` session daemons survive the command that opened them | `D:\Local-AI\cache\npm\_npx\…\cliDaemon.js` | No | Skill guidance: close the session at the end of the task (follow-up in the owning skill `use-playwright-cli`) |
| Login items (Google Drive, Gemini, WingetUI) | The apps re-register themselves on update or first run; Gemini also has `openAtLogin = true` | HKCU Run + app settings | No. No AgentHub script writes Run, StartupApproved, tasks or services (checked-absent across scripts, packages, tests, overlays; `Update-RepoWise.ps1:144-166` only deletes) | StartupApproved = 03 plus the app's own setting off. **Known to be undone** by app updates (Google Drive, Gemini). Re-check after updates with `Get-HostMemoryReport.ps1` and the startup list |
| Windows settings | — | — | — | None applied. Memory compression and the page file are already right. Windows feature updates can re-enable SysMain, reset the page file to system-managed, and reset StartupApproved for Store apps |

Validation effects:

- `tests/Test-DeclaredVsDeployedMcp.ps1:180-186` fails when a registry-declared
  persisted server is missing from a host's live config. A hand trim of a
  registry server therefore turns a test red unless the registry `hosts`
  list is narrowed first. That is the correct place to record a lean default.
- `Validate-AgentHub.ps1:350` checks only that `activationMode` is a valid
  value, so nothing statically catches an *unregistered* local stdio server
  appearing in a host config. That gap is how `aws-mcp` sat in Codex unnoticed.

Proposed durable change (repository, not applied): extend `Sync-AgentHub.ps1
-Audit` to list unregistered local stdio MCP entries per host config (Codex
`[mcp_servers.*]` with `command`, Cursor and OpenCode `command` entries), reported as
drift. Pair it with a `deniedHostConfiguredLocalMcpIds` list in
`registry/native-connectors.json` (initially `aws-mcp`, owner to confirm), so a
re-added entry shows up in the audit the owner already runs. That is a
behaviour change to the sync engine and needs its own branch, tests
(`tests/Test-*.ps1`) and review, so it is left as a follow-up, not folded into
this report.

## 13. Say "apply the fixes" to run these

All are reversible and user-scope, with no admin, no reboot, and no process stopped.
One script does all of them:
`D:\Local-AI\cache\temp\claude\C--Repos-shmindmaster-agenthub\f71fd0ed-f42c-4d5c-baf5-40b33adcd507\scratchpad\Apply-MemoryFixes.ps1`
(backups `*.bak-20261028-memaudit`; rollback with `-Rollback`).

| fix | change | expected saving |
|---|---|---|
| F3a | Codex `config.toml` and `claude.config.toml`: `[mcp_servers.aws-mcp] enabled = false` | ~1,370 MB at t40 while Codex runs (all `aws-mcp` copies) |
| F3b | Codex `config.toml`: `[plugins."unified-computer-use@openai-bundled"] enabled = false` | up to ~950 MB at t40 (computer-use copies; part of that class is the separate `computer-use` plugin) |
| F8 | StartupApproved\Run = 03 for GoogleDriveFS, WingetUI, Gemini; Gemini `openAtLogin` → false | ~110 MB from next logon; ends a policy conflict |
| F10 | VMware: `MemTrimRate = "0"`, `sched.mem.pshare.enable = "FALSE"` in `macos.vmx`, `prefvmx.minVmMemPct = "100"` in preferences.ini. **Skipped automatically if the VM is running** | 0 MB; stops the host paging the guest, and VMware refuses to start the VM when RAM is short instead of hard-locking |

Takes effect when Codex is restarted (F3), at next logon (F8) and at next VM
power-on (F10).

Not in the script, because each needs the owner's hand or a UI with no stable config file:
F1 quit Codex when Claude is the host (up to 10.9 GB), F2 archive finished
Claude sessions (~450 MB each), F4 close Copilot CLI (0.7–1.1 GB), F5 close
unused Claude panes (~1 GB), F6 Chrome Memory Saver, F7 Desktop Commander off in
Claude desktop Settings (130–185 MB), F9 pause the Codex daily heartbeat
automation, F13 close the two Playwright CLI daemons (~1.6 GB), Codex
data-analytics plugin off in its Plugins UI, BIOS EXPO Profile 1, and the NVMe
slot swap.

## 14. Before starting the VM: checklist

1. **One coding host.** Quit the Codex desktop app and close the Copilot CLI tab
   unless that host *is* the one you are working in (F1, F4).
2. **Two Claude sessions at most.** Archive finished side sessions (F2). The DO KB
   session is done (PR 49 open).
3. **Close Claude desktop panes** you are not looking at, and close spare Chrome
   tabs or let Memory Saver discard them (F5, F6).
4. **Check headroom:** `(Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory).AvailableMBytes`
   must read **at least 12,000** (10,240 guest + VMware overhead + a 1 GB host
   floor). At t00 it was 6,445 with the VM just booted. At 11:32 it was 9,275
   with the VM off. Not enough either time.
5. **Leave alone:** Local-AI retrieve (8790) and RepoWise (7339): ~2.2 GB WS,
   budgeted. Docker stays off.
6. **After the VM is up**, re-read available memory after 5 minutes. If it is
   under 1,500 MB, shut the guest down cleanly before the host starts paging it.
