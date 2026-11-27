import os
from pathlib import Path

HOSTS = frozenset(
    "amp antigravity claude cline codex copilot cursor devin factory grok kilo opencode".split()
)
ROOT = Path(os.environ["AGENTHUB_BROWSER_TEST_DIR"]).resolve()
ROOT.mkdir(parents=True, exist_ok=True)
PORT = int(os.environ.get("AGENTHUB_BROWSER_TEST_PORT", "48767"))

if not __debug__:
    raise RuntimeError("Run the acceptance suite with Python assertions enabled.")
