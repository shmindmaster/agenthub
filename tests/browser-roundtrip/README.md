# Browser workflow round-trip

This opt-in test runs a synthetic file-intake site on loopback. Use Python 3, Tencent BrowserSkill on the controlling host, a connected Chrome profile, and PyAV and Pillow for media verification. The scripts use normal Python with assertions enabled. Start a fresh evidence directory for each acceptance campaign. No real accounts, form data, or uploads are required.

In PowerShell, from the AgentHub checkout:

```powershell
$env:AGENTHUB_BROWSER_TEST_DIR = Join-Path ([IO.Path]::GetTempPath()) ("agenthub-browser-" + [guid]::NewGuid())
bsk browsers --json
$env:BSK_TEST_BROWSER = '<selected instance ID>'
python tests/browser-roundtrip/server.py
```

Run the server in its own terminal. Give each target agent the same evidence directory, browser instance, and checkout path. Ask that agent to execute `python tests/browser-roundtrip/workflow.py HOST` through its shell and report the resulting record ID. Run hosts sequentially. A controller running the script repeatedly under different labels does not establish host execution. Keep the host transcripts as evidence. The optional AGENTHUB_BROWSER_TEST_PORT setting must match on both sides.

The driver owns one background tab and one recording. Each invocation creates a fresh synthetic case. It fills and submits the form, uploads a unique file, reloads the list, opens the row matching its run ID, downloads the attachment and exports an MP4. If an action is uncertain, inspect the saved case before starting a new run.

```powershell
uv run --with av --with pillow python tests/browser-roundtrip/verify.py --host codex
uv run --with av --with pillow python tests/browser-roundtrip/verify.py
```

The second command requires all twelve host labels. It checks one database row per case, matching fields and bytes, and a decodable H.264 video with changing frames. Results are written to verification.json in the evidence directory. A missing host or failed proof exits nonzero. Stop the server after the campaign.
