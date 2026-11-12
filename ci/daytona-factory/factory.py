#!/usr/bin/env python3
"""Build and record trusted, synthetic app workflows on disposable Daytona workers."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, build_opener

HERE = Path(__file__).resolve().parent
BRANCHES = {"abacare": ("main", "dev"), "empowera": ("main",), "revolva": ("main",)}
ARTIFACTS = {"tests.log", "capture.webm", "demo.mp4"}
OPTIONAL_ARTIFACTS = {"claim.png", "preview.log", "render.log"}
API = "https://app.daytona.io/api"
WORK = "/tmp/factory"
BUILD_SNAPSHOT = "factory-node-build-v1"
RENDER_SNAPSHOT = "rexa-remotion-4-0-517"


def validate_request(app, revision):
    if app not in BRANCHES or not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Use an allowlisted app and a full lowercase Git commit SHA.")
    return revision


def trusted_commit(repo, revision, branches):
    if subprocess.run(["git", "-C", str(repo), "cat-file", "-t", revision],
                      capture_output=True, text=True).stdout.strip() != "commit":
        return False
    return any(
        subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", revision,
                        f"refs/remotes/origin/{branch}"], capture_output=True).returncode == 0
        for branch in branches
    )


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def write_receipt(root, app, revision, preview, workers):
    files = ARTIFACTS | {name for name in OPTIONAL_ARTIFACTS
                         if (root / name).is_file() and (root / name).stat().st_size}
    if not all((root / name).is_file() and (root / name).stat().st_size for name in files):
        raise ValueError("Expected output is missing or empty.")
    receipt = {
        "app": app,
        "commit": revision,
        "factory_commit": os.getenv("GITHUB_SHA"),
        "run_url": os.getenv("GITHUB_SERVER_URL", "https://github.com") + "/"
        + os.getenv("GITHUB_REPOSITORY", "shmindmaster/agenthub") + "/actions/runs/"
        + os.getenv("GITHUB_RUN_ID", "local"),
        "preview": preview,
        "workers_deleted": workers,
        "files": {
            name: {"sha256": digest(root / name), "bytes": (root / name).stat().st_size}
            for name in sorted(files)
        },
    }
    (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    return receipt


def verify_receipt(root, app, revision):
    try:
        receipt = json.loads((root / "receipt.json").read_text(encoding="utf-8"))
        files = receipt["files"]
        return (
            receipt["app"] == app and receipt["commit"] == revision
            and receipt["factory_commit"] == os.getenv("GITHUB_SHA")
            and receipt["preview"]["status"] == "verified and revoked"
            and receipt["workers_deleted"].keys() == {"build", "render"}
            and all(receipt["workers_deleted"].values())
            and ARTIFACTS <= files.keys() <= ARTIFACTS | OPTIONAL_ARTIFACTS
            and all((root / name).stat().st_size == info["bytes"] > 0
                    and digest(root / name) == info["sha256"] for name, info in files.items())
        )
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        return False


def remote(box, command, seconds):
    result = box.process.exec(command, timeout=seconds)
    if result.exit_code != 0:
        raise RuntimeError(f"Worker command exited {result.exit_code}")
    return result.result or ""


@contextmanager
def worker(client, snapshot, app, run, role, workers):
    from daytona import CreateSandboxFromSnapshotParams, ListSandboxesQuery

    # A prior attempt may have lost its runner before the finally block ran.
    labels = {"owner": app, "purpose": "daytona-factory", "run": run, "role": role}
    for previous in client.list(ListSandboxesQuery(labels=labels)):
        if all((previous.labels or {}).get(key) == value for key, value in labels.items()):
            previous.delete(wait=True)

    name = f"factory-{app}-{run}-{role}"
    box = client.create(CreateSandboxFromSnapshotParams(
        snapshot=snapshot, name=name, labels=labels, public=False,
        auto_stop_interval=35, auto_delete_interval=5, ttl_minutes=40,
    ), timeout=180)
    print(f"{role} worker {box.id} started", flush=True)
    try:
        yield box
    finally:
        box.delete(wait=True)
        workers[role] = box.id
        print(f"{role} worker {box.id} deleted", flush=True)


def upload_script(box, name, destination):
    box.fs.upload_file((HERE / name).read_text(encoding="utf-8").encode(), destination)


def download(box, source, destination):
    expected = remote(box, f"sha256sum {shlex.quote(source)}", 30).split()[0]
    box.fs.download_file(source, str(destination))
    if digest(destination) != expected:
        raise RuntimeError(f"Download integrity check failed for {destination.name}")


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def preview(box, app):
    ttl = 120
    port = 4173
    opener = build_opener(NoRedirect())
    link = box.create_signed_preview_url(port, expires_in_seconds=ttl)
    try:
        parsed = urlsplit(link.url)
        if parsed.scheme != "https" or parsed.hostname is None:
            raise RuntimeError("Daytona returned an invalid HTTPS preview URL.")
        with opener.open(link.url, timeout=20) as response:
            if response.status != 200 or app.encode() not in response.read(200_000).lower():
                raise RuntimeError("The signed preview did not return the app shell.")
    except HTTPError as error:
        raise RuntimeError(f"Signed preview returned HTTP {error.code}.") from None
    finally:
        box.expire_signed_preview_url(port, link.token)

    try:
        with opener.open(link.url, timeout=15):
            raise RuntimeError("The revoked preview still returned content.")
    except HTTPError as error:
        if error.code not in {302, 401, 403, 404, 410}:
            raise RuntimeError(f"Revoked preview returned HTTP {error.code}.") from None
    return {
        "status": "verified and revoked",
        "ttl_seconds": ttl,
        "revoked_at": datetime.now(timezone.utc).isoformat(),
    }


def build(client, args, run, workers):
    with worker(client, BUILD_SNAPSHOT, args.app, run, "build", workers) as box:
        with tempfile.TemporaryDirectory() as temporary:
            archive = Path(temporary) / "source.tar.gz"
            subprocess.run(["git", "-C", str(args.repo), "archive", "--format=tar.gz",
                            "-o", str(archive), args.sha], check=True)
            remote(box, f"mkdir -p {WORK}/source {WORK}/out", 20)
            box.fs.upload_file(str(archive), f"{WORK}/source.tar.gz")
        upload_script(box, "build.sh", f"{WORK}/build.sh")
        try:
            remote(box, f"bash {WORK}/build.sh {args.app} {args.sha} >{WORK}/out/tests.log 2>&1", 1500)
        finally:
            download(box, f"{WORK}/out/tests.log", args.output / "tests.log")

        try:
            preview_result = preview(box, args.app)
        finally:
            download(box, f"{WORK}/out/preview.log", args.output / "preview.log")
        download(box, f"{WORK}/out/capture.webm", args.output / "capture.webm")
        if args.app == "abacare":
            download(box, f"{WORK}/out/claim.png", args.output / "claim.png")
        return preview_result


def render(client, args, run, workers):
    with worker(client, RENDER_SNAPSHOT, args.app, run, "render", workers) as box:
        remote(box, f"mkdir -p {WORK}/public && ln -s /opt/base/node_modules {WORK}/node_modules", 30)
        box.fs.upload_file(str(args.output / "capture.webm"), f"{WORK}/public/capture.webm")
        box.fs.upload_file(str(HERE / "render.tsx"), f"{WORK}/index.tsx")
        upload_script(box, "render.sh", f"{WORK}/render.sh")
        try:
            remote(box, f"cd {WORK} && bash render.sh >render.log 2>&1", 360)
        finally:
            download(box, f"{WORK}/render.log", args.output / "render.log")
        download(box, f"{WORK}/demo.mp4", args.output / "demo.mp4")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "run", "verify"))
    parser.add_argument("--app", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    validate_request(args.app, args.sha)

    if args.command == "verify":
        if not verify_receipt(args.output, args.app, args.sha):
            raise ValueError("Artifact receipt does not match the requested revision and files.")
        return
    if not trusted_commit(args.repo, args.sha, BRANCHES[args.app]):
        raise ValueError("Commit is outside the approved source branch history.")
    if args.command == "check":
        return

    from daytona import Daytona, DaytonaConfig

    run_id = os.environ["GITHUB_RUN_ID"]
    if not re.fullmatch(r"[0-9]+", run_id):
        raise ValueError("Invalid workflow run ID.")
    client = Daytona(DaytonaConfig(api_url=API, api_key=os.environ["DAYTONA_FACTORY_API_KEY"]))
    args.output.mkdir(parents=True, exist_ok=True)
    workers = {}
    result = build(client, args, run_id, workers)
    render(client, args, run_id, workers)
    write_receipt(args.output, args.app, args.sha, result, workers)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Keep transport exceptions from revealing auth headers or signed URLs.
        detail = f": {error}" if type(error) in {ValueError, RuntimeError} else ""
        raise SystemExit(f"Factory failed ({type(error).__name__}){detail}") from None
