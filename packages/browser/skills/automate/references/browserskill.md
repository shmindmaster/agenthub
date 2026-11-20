# Tencent BrowserSkill workflows

Install the vendor CLI and browser extension from the [official setup guide](https://github.com/Tencent/BrowserSkill/blob/main/AGENT_INSTALL.md) and [extension manual](https://browserskill.weixin.qq.com/manual.en.html). Check that the installed CLI, running daemon and connected extension support the requested command. The commands below are available in version 0.5.0. Check the live connection before using an existing profile.

Use only the user's selected profile and start a scoped Agent Window with no focus. Follow [the session setup](hosts.md#existing-chrome-and-edge-profiles), then use these routes:

- Name browser instances in the extension and choose the exact instance ID when starting a task. Keep the task window visible in the browser's window list. Let the user select it. Use group-based isolation only in providers that document it. BrowserSkill removed automatic native tab groups in 0.4.1 and uses its Agent Window and tab control indicators. [Releases](https://github.com/Tencent/BrowserSkill/releases)
- Other tools and the user can work in other tabs or browser instances. Use a single writer per tab. If the user edits the controlled tab, yield, synchronize again, then review the new state before acting. Borrow an existing tab only after the user gives it to the task. Moving a controlled tab out of its Agent Window ends the task and preserves the tabs. [Manual](https://browserskill.weixin.qq.com/manual.en.html) · [Cooperation](https://github.com/Tencent/BrowserSkill)
- A site can transiently activate a native popup. Use a dedicated profile if a workflow is likely to open authentication, payment or permission dialogs. Let the user choose when to complete those steps.

| Task | Route |
| --- | --- |
| Form and app flows | Observe, fill a fresh field ref, and read the result. Submit only when authorized. Use plans for already decided actions and reviewed recipes for repeats. If a write has an unknown outcome, inspect the settled page before retrying. |
| Structured data | Use `bsk extract discover --session <id> --json` then `bsk extract table --session <id> --target <target-id> --format json --out <file>`. Use `list` with explicit fields for lists. Check pagination, virtualized results, row limits and the exported completeness metadata. For CSV use `--csv-safe` when spreadsheet import is expected. |
| Debugging | On a synthetic or otherwise authorized page, use `bsk debug start --session <id>`, inspect the minimum console/request/performance evidence needed, and run `bsk debug stop --session <id>`. Debug history can hold field values and response bodies. Export only approved evidence and review it before sharing. |
| Task video | Start with `bsk video start --session <id> --duration 60s --quality clear --json`, read the ID from recording.recording_id, then use `bsk video stop --recording <id> --browser <instance-id> --out <file.mp4>`. Use a new destination outside the repo. Inspect recording.completeness and stop_reason, verify playback and inspect visible data before handing off. This is a silent tab recording. |

BrowserSkill also has a stdio MCP command. Keep it on demand when a shell-capable host can use the CLI directly. Prefer the host's native browser first when it provides the profile, isolation and evidence the task needs. A remote research MCP such as Parallel works on public web content and cannot drive an authenticated tab.

For Media Studio, label an exported BrowserSkill MP4 as supplemental footage and carry its browser lane, app revision, viewport, role, and verified action/result evidence with it. For product footage requiring pointer evidence, use the isolated AH Browser recorder and Media Studio's `browser-take.mjs` or the governed scene recorder. A BrowserSkill MP4 does not create that timed pointer receipt.
