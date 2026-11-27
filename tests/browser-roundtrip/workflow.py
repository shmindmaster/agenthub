import hashlib
import json
import os
import re
import secrets
import subprocess
import sys
import time

from settings import HOSTS, PORT, ROOT

h = sys.argv[1]
if h not in HOSTS:
    raise SystemExit("Unknown host label")
folder = ROOT / h
folder.mkdir(exist_ok=True)
run = secrets.token_hex(4)
out = folder / run
out.mkdir()
src = out / "synthetic.txt"
src.write_text("Synthetic QA file " + h + " " + run)
title = "Portfolio QA " + h + " " + run


def cmd(*args):
    p = subprocess.run(["bsk", *args], capture_output=True, text=True, timeout=45)
    if p.returncode:
        raise RuntimeError(" ".join(args[:2]) + ": " + p.stderr + " " + p.stdout)
    return p.stdout


sid = json.loads(
    cmd(
        "session",
        "start",
        "--no-focus",
        "--browser",
        os.environ["BSK_TEST_BROWSER"],
        "--agent-name",
        "qa-" + h,
        "--json",
    )
)["session_id"]


def b(*args):
    return cmd(*args, "--session", sid)


def act(*args):
    for attempt in range(3):
        ob = json.loads(b("cooperate", "sync", "--json"))
        try:
            return b(
                *args,
                "--context",
                ob["context_id"],
                "--observation",
                ob["observation_id"],
            )
        except RuntimeError as err:
            if "native event was not sent" not in str(err) or attempt == 2:
                raise
            time.sleep(0.5)


def seen(value):
    for j in range(16):
        try:
            s = b("snapshot")
        except RuntimeError as e:
            s = str(e)
            time.sleep(0.25)
            continue
        if value in s:
            return s
        time.sleep(0.25)
    raise RuntimeError("missing " + value + ": " + s)


rec = None
try:
    b("navigate", f"http://127.0.0.1:{PORT}/" + h + "/form")
    seen("Synthetic file intake")
    for attempt in range(16):
        try:
            v = json.loads(
                b(
                    "video",
                    "start",
                    "--quality",
                    "clear",
                    "--duration",
                    "120s",
                    "--json",
                )
            )
            rec = v.get("recording_id") or v["recording"]["recording_id"]
            break
        except RuntimeError as err:
            if "already recording" not in str(err).lower() or attempt == 15:
                raise
            time.sleep(3)
    time.sleep(0.8)
    act("fill", "input[name=title]", "--value", title)
    act("upload", "input[type=file]", "--file", str(src))
    time.sleep(0.8)
    act("click", "button")
    seen("Saved records")
    act("reload")
    seen(title)
    act("click", "#r-" + run)
    s = seen("Download attachment")
    assert title in s and "synthetic.txt" in s
    rid = re.search(r"Record ([a-f0-9]{16})", s)[1]
    act("download", "a", "--out", str(out / "download.txt"))
    assert (out / "download.txt").read_bytes() == src.read_bytes()
    time.sleep(0.9)
finally:
    try:
        if rec:
            cmd("video", "stop", "--recording", rec, "--out", str(out / "flow.mp4"))
    finally:
        cmd("session", "stop", sid)
(out / "proof.json").write_text(
    json.dumps(
        dict(
            host=h,
            run=run,
            record=rid,
            title=title,
            sha256=hashlib.sha256(src.read_bytes()).hexdigest(),
        )
    ),
    encoding="utf8",
)
print("Completed browser workflow", h, rid)
