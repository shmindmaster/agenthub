#!/usr/bin/env python3
"""Build and record trusted, synthetic app workflows on disposable, budgeted workers."""

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, build_opener

HERE = Path(__file__).resolve().parent
POLICY_FILE = HERE / "budget.json"
BRANCHES = {"abacare": ("main", "dev"), "empowera": ("main",), "revolva": ("main",)}
LOCKFILES = {
    "abacare": ("pnpm-lock.yaml", "apps/api/uv.lock"),
    "empowera": ("pnpm-lock.yaml", "apps/api/requirements-readiness-dev.txt"),
    "revolva": ("package-lock.json",),
}
REQUIRED = {"demo": {"tests.log", "capture.webm", "demo.mp4"}, "journey": {"tests.log", "journeys.tar.gz"}}
OPTIONAL = {"claim.png", "preview.log", "render.log", "toolchain.json", "evidence.tar.gz"}
EXPORTS = ("tests.log", "toolchain.json", "evidence.tar.gz", "journeys.tar.gz")
SUITES = tuple(REQUIRED)
JOURNEY_APPS = {"empowera", "revolva"}
PROBES = ("none", "fail", "hang")
WORK = "/tmp/factory"
BUILD_SNAPSHOT = "factory-node-build-v1"
RENDER_SNAPSHOT = "rexa-remotion-4-0-517"
# Daytona v2 images built from the Dockerfiles beside this file (see README).
BUILD_IMAGE = "factory-node-build-v2"
RENDER_IMAGE = "rexa-remotion-4-0-517-v2"
LOCAL_IMAGE = "factory-local-worker"
PURPOSE = "daytona-factory"
GONE = {"destroyed", "destroying"}
V2_LIVE = ("queued", "creating", "starting", "started", "pausing", "paused", "stopping",
           "stopped", "error")


class Cancelled(RuntimeError):
    pass


# Set by the signal handler: the Daytona v0 SDK re-raises a Cancelled raised inside a blocking
# request as DaytonaError, so the exception type alone cannot identify a cancelled run.
CANCEL_SIGNAL = []


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load_policy(path=POLICY_FILE, provider="daytona"):
    """Daytona v2 rates and limits are the default; the v0 fallback overlays its own block."""
    policy = json.loads(Path(path).read_text(encoding="utf-8"))
    if provider == "daytona-v0":
        policy = {**policy, **policy["v0"]}
    if policy["gpu"] != 0 or policy["max_concurrent_workers"] != 1:
        raise ValueError("Budget policy must keep zero GPU and one concurrent worker.")
    if not 0 < policy["max_job_minutes"] <= 30 or policy["transient_retries"] > 1:
        raise ValueError("Budget policy exceeds the 30-minute, one-retry pilot limits.")
    if not 0 < policy["teardown_reserve_seconds"] < policy["export_reserve_seconds"]:
        raise ValueError("Budget policy must keep a teardown tail inside the export reserve.")
    return policy


def hourly_usd(policy, cpu, memory_gib, disk_gib):
    rates = policy["rates_usd_per_hour"]
    billable_disk = max(0.0, (disk_gib or 0) - policy["free_disk_gib"])
    return cpu * rates["cpu"] + memory_gib * rates["memory_gib"] + billable_disk * rates["disk_gib"]


def worst_case_usd(policy):
    """Workers run one at a time inside the job deadline, so one attempt is bounded by the
    largest allowed worker for the whole job lifetime; every retry reserves another attempt."""
    limits = policy["worker_limits"]
    attempt = hourly_usd(policy, limits["cpu"], limits["memory_gib"], limits["disk_gib"])
    return round(attempt * policy["max_job_minutes"] / 60 * (1 + policy["transient_retries"]), 4)


CASH_FALLBACK = {"true": "disabled",
                 "unreachable-under-cap": "unverified; unreachable under the pilot cap"}


def preflight(policy, credits_usd, cash_fallback, prior_runs):
    """Fail closed unless funding is attested and the reservation fits the pilot cap.

    cash_fallback is "true" when the owner attests auto top-up is off, or
    "unreachable-under-cap" when it is unverified but the cap is below the attested credits."""
    if cash_fallback not in CASH_FALLBACK:
        raise ValueError("Cash fallback is not attested as disabled or unreachable; metered launch refused.")
    if credits_usd is None or credits_usd <= 0:
        raise ValueError("No attested eligible credit balance; metered launch refused.")
    if prior_runs < 0:
        raise ValueError("Prior run count must be known.")
    cap = round(min(policy["pilot_cap_usd"], policy["pilot_cap_credit_fraction"] * credits_usd), 4)
    per_run = worst_case_usd(policy)
    reserved = round(per_run * (prior_runs + 1), 4)
    if reserved > cap:
        raise ValueError(f"Reserving ${reserved} would exceed the ${cap} pilot cap.")
    if cash_fallback == "unreachable-under-cap" and cap >= credits_usd:
        raise ValueError("The pilot cap does not stay below the attested credits.")
    return {"funding": "daytona free credits", "credits_usd": credits_usd, "cap_usd": cap,
            "worst_case_usd_per_run": per_run, "prior_runs": prior_runs, "reserved_usd": reserved,
            "cash_fallback": CASH_FALLBACK[cash_fallback]}


def parse_time(value):
    """An ISO date (midnight UTC) or date-time, as GitHub and the batch variable write them."""
    parsed = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def batch_attempts(runs, current, run_attempt, batch_start):
    """Started run attempts in the batch before this one; refuse a rerun of a pre-batch run.

    GitHub keeps a run's original id and created_at across reruns, so the batch's run list never
    includes a run created before the batch even when it is rerun after it. Such a rerun would
    reserve one attempt and escape the cap, so it is refused; dispatch a fresh run instead."""
    start = parse_time(batch_start)
    if parse_time(current["created_at"]) < start:
        raise ValueError("This run was created before DAYTONA_PILOT_BATCH_START; reruns of pre-batch "
                         "runs are refused. Dispatch a fresh run.")
    if run_attempt < 1:
        raise ValueError("Run attempt must be known.")
    total = 0
    for run in runs:
        if parse_time(run["created_at"]) < start:
            continue
        if run["id"] == current["id"]:
            total += run_attempt - 1
        elif run["status"] in {"queued", "waiting", "pending", "requested"}:
            total += run["run_attempt"] - 1
        else:
            total += run["run_attempt"]
    if not any(run["id"] == current["id"] for run in runs):
        total += run_attempt - 1
    return total


def json_stream(text):
    """Concatenated JSON values, as `gh api --paginate --jq` prints them."""
    decoder, values, index = json.JSONDecoder(), [], 0
    while True:
        while index < len(text) and text[index].isspace():
            index += 1
        if index == len(text):
            return values
        value, index = decoder.raw_decode(text, index)
        values.append(value)


def check_resources(policy, resources):
    limits = policy["worker_limits"]
    if resources.get("gpu"):
        raise RuntimeError("Worker has a GPU; zero GPU is allowed.")
    for key in ("cpu", "memory_gib", "disk_gib"):
        value = resources.get(key)
        if value is not None and value > limits[key]:
            raise RuntimeError(f"Worker {key} {value} exceeds the {limits[key]} limit.")


class Deadline:
    """One wall-clock budget for setup, tests and export; export keeps a reserved tail."""

    def __init__(self, minutes, reserve_seconds, clock=time.monotonic, teardown_seconds=0):
        self.clock = clock
        self.end = clock() + minutes * 60
        self.reserve = reserve_seconds
        self.teardown = teardown_seconds

    def left(self, export=False):
        return self.end - self.clock() - (0 if export else self.reserve)

    def bound(self, seconds, export=False):
        left = int(self.left(export))
        if left <= 0:
            raise RuntimeError("Job deadline reached")
        return max(1, min(seconds, left))

    def export_bound(self, seconds):
        """Each evidence operation ends before the tail kept for deletion and the receipt."""
        left = int(self.end - self.clock() - self.teardown)
        if left <= 0:
            raise RuntimeError("Export window closed; keeping the rest for deletion and the receipt")
        return max(1, min(seconds, left))

    def ttl_minutes(self):
        minutes = int(self.left(export=True) // 60)
        if minutes < 1:
            raise RuntimeError("Job deadline reached before a worker could start")
        return minutes


def validate_request(app, revision):
    if app not in BRANCHES or not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Use an allowlisted app and a full lowercase Git commit SHA.")
    return revision


def validate_run(run):
    if not re.fullmatch(r"[0-9]+|local-[0-9]+", run or ""):
        raise ValueError("Invalid run ID.")
    return run


def trusted_commit(repo, revision, branches):
    if subprocess.run(["git", "-C", str(repo), "cat-file", "-t", revision],
                      capture_output=True, text=True).stdout.strip() != "commit":
        return False
    return any(
        subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", revision,
                        f"refs/remotes/origin/{branch}"], capture_output=True).returncode == 0
        for branch in branches
    )


def lockfile_hashes(repo, app, revision):
    hashes = {}
    for path in LOCKFILES[app]:
        shown = subprocess.run(["git", "-C", str(repo), "show", f"{revision}:{path}"],
                               capture_output=True)
        hashes[path] = hashlib.sha256(shown.stdout).hexdigest() if shown.returncode == 0 else None
    return hashes


def digest(path):
    with path.open("rb") as file:
        return hashlib.file_digest(file, "sha256").hexdigest()


def run_url():
    return (os.getenv("GITHUB_SERVER_URL", "https://github.com") + "/"
            + os.getenv("GITHUB_REPOSITORY", "shmindmaster/agenthub") + "/actions/runs/"
            + os.getenv("GITHUB_RUN_ID", "local"))


def write_receipt(root, receipt):
    """Hash the files this attempt exported; a passed receipt must also hold the suite's required set.

    Files left in the output directory by an earlier run are never hashed, even when an export
    failed and left them in place."""
    present = {p.name for p in root.iterdir() if p.is_file() and p.stat().st_size
               and p.name in (REQUIRED[receipt["suite"]] | OPTIONAL) & exported_names(receipt)}
    missing = receipt["status"] == "passed" and not REQUIRED[receipt["suite"]] <= present
    if missing:
        receipt.update(status="failed", error="Expected output is missing or empty.")
    receipt["files"] = {name: {"sha256": digest(root / name), "bytes": (root / name).stat().st_size}
                        for name in sorted(present)}
    (root / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    if missing:
        raise ValueError(receipt["error"])
    return receipt


def exported_names(receipt):
    return {name for worker in (receipt.get("workers") or {}).values()
            for name in worker.get("exported", [])}


def verify_receipt(root, app, revision, suite="demo", factory_commit=None):
    factory_commit = factory_commit or os.getenv("GITHUB_SHA")
    try:
        receipt = json.loads((root / "receipt.json").read_text(encoding="utf-8"))
        files = receipt["files"]
        workers = receipt["workers"]
        return (
            receipt["schema"] == 2 and receipt["status"] == "passed" and receipt["probe"] == "none"
            and receipt["app"] == app and receipt["commit"] == revision
            and receipt["suite"] == suite and receipt["factory_commit"] == factory_commit
            and (suite != "demo" or receipt["preview"]["status"] in {"verified and revoked",
                                                                     "verified in worker"})
            and workers and all(w["deleted"] and w["exported_before_delete"] for w in workers.values())
            and REQUIRED[suite] <= files.keys() <= (REQUIRED[suite] | OPTIONAL) & exported_names(receipt)
            and all((root / name).stat().st_size == info["bytes"] > 0
                    and digest(root / name) == info["sha256"] for name, info in files.items())
        )
    except (OSError, ValueError, TypeError, KeyError, AttributeError):
        return False


class DeadlineSignal:
    """A transfer cancel signal (``is_set``) that fires once a deadline passes."""

    def __init__(self, seconds):
        self.end = time.monotonic() + seconds

    def is_set(self):
        return time.monotonic() >= self.end


def daytona_client():
    from daytona import Daytona, DaytonaConfig
    return Daytona(DaytonaConfig(api_key=os.environ["DAYTONA_FACTORY_API_KEY"]))


def daytona_transient(error):
    # SDK 2.x shares these bases between the v0 and v2 namespaces.
    from daytona import (DaytonaConnectionError, DaytonaRateLimitError,
                         DaytonaServiceUnavailableError, DaytonaTimeoutError)
    return isinstance(error, (DaytonaRateLimitError, DaytonaTimeoutError, DaytonaConnectionError,
                              DaytonaServiceUnavailableError, ConnectionError))


class DaytonaWorker:
    """A Daytona v2 sandbox."""

    def __init__(self, box):
        self.box = box
        self.id = box.id

    def resources(self):
        box = self.box
        return {"cpu": box.cpu_max or box.cpu, "gpu": getattr(box, "gpu", None) or 0,
                "memory_gib": box.memory_max or box.memory, "disk_gib": box.disk_max or box.disk}

    def exec(self, command, seconds):
        from daytona.v2.errors import ProcessExecutionTimeoutError
        try:
            # execution_timeout makes the sandbox kill the process tree; timeout bounds the wait.
            result = self.box.exec(command, timeout=seconds + 30, execution_timeout=max(1, int(seconds)))
        except ProcessExecutionTimeoutError:
            return 124, ""
        if result.exit_code is None or result.reason == "timed_out":
            return 124, result.output or ""
        return result.exit_code, result.output or ""

    def upload(self, source, destination):
        if isinstance(source, bytes):
            self.box.fs.write_bytes(destination, source)
        else:
            self.box.fs.upload_file(str(source), destination)

    def download(self, source, destination, seconds):
        cancel = DeadlineSignal(max(1, seconds))
        if not source.endswith(".log"):
            self.box.fs.download_file(source, str(destination), cancel=cancel)
            return
        # The v2 sandbox file proxy answers 403 for any path ending in ".log"; read a hard link.
        staged = f"{source}.export"
        code, _ = self.exec(f"ln -f {shlex.quote(source)} {shlex.quote(staged)}", 15)
        if code != 0:
            raise RuntimeError(f"Could not stage {Path(source).name} for download")
        try:
            self.box.fs.download_file(staged, str(destination), cancel=cancel)
        finally:
            self.exec(f"rm -f {shlex.quote(staged)}", 15)

    def signed_preview(self, port, ttl):
        link = self.box.ports.signed_preview_link(port, expires_in_seconds=ttl)
        return link.url, self.box.ports.expire_signed_preview_links

    def delete(self):
        self.box.delete(timeout=180)


class DaytonaProvider:
    """Daytona v2 (``client.v2``): images, lifecycle-policy deletion and indexed search."""
    name = "daytona"
    platform = "v2"
    metered = True
    image = BUILD_IMAGE

    def __init__(self, policy):
        self.client = daytona_client()
        self.limits = policy["worker_limits"]

    def find(self, labels):
        # Search is eventually consistent, so every hit is re-read before it counts as live.
        from daytona.v2.errors import NotFoundError
        hits, cursor = [], None
        while True:
            page = self.client.v2.search(labels=labels, states=V2_LIVE, limit=100, cursor=cursor)
            hits += page.items
            cursor = page.next_cursor
            if not cursor:
                break
        live = []
        for box in hits:
            try:
                box.refresh_data()
            except NotFoundError:
                continue
            if all((box.labels or {}).get(k) == v for k, v in labels.items()) \
                    and str(box.state).lower() not in GONE:
                live.append(box)
        return live

    def remove(self, box):
        from daytona.v2.errors import NotFoundError
        try:
            box.delete(timeout=180)
        except NotFoundError:
            pass

    def create(self, role, name, labels, ttl_minutes, cache_key):
        from daytona.v2 import Resources
        image = RENDER_IMAGE if role == "render" else BUILD_IMAGE
        size = self.limits
        box = self.client.v2.create(
            image, name=name, labels=labels, user="root", spot=False,
            resources=Resources(cpu=size["cpu"], cpu_max=size["cpu"], memory=size["memory_gib"],
                                memory_max=size["memory_gib"], disk=size["disk_gib"],
                                disk_max=size["disk_gib"]),
            # The platform deletes the sandbox at the job deadline even if this runner dies.
            lifecycle_policy={"timeout_seconds": ttl_minutes * 60, "on_timeout": "delete"},
            wait_seconds=180)
        box.refresh_data()  # the create response omits the allocated resources
        return DaytonaWorker(box), {"image": image, "cache": None}

    transient = staticmethod(daytona_transient)


class DaytonaV0Worker:
    def __init__(self, box):
        self.box = box
        self.id = box.id

    def resources(self):
        return {"cpu": self.box.cpu, "gpu": self.box.gpu or 0,
                "memory_gib": self.box.memory, "disk_gib": self.box.disk}

    def exec(self, command, seconds):
        from daytona.v0 import DaytonaProcessExecutionTimeoutError
        try:
            result = self.box.process.exec(command, timeout=seconds)
        except DaytonaProcessExecutionTimeoutError:
            return 124, ""
        return result.exit_code, result.result or ""

    def upload(self, source, destination):
        self.box.fs.upload_file(source if isinstance(source, bytes) else str(source), destination)

    def download(self, source, destination, seconds):
        # The pinned SDK reads the timeout positionally; 0 would mean no timeout.
        self.box.fs.download_file(source, str(destination), max(1, int(seconds)))

    def signed_preview(self, port, ttl):
        link = self.box.create_signed_preview_url(port, expires_in_seconds=ttl)
        return link.url, lambda: self.box.expire_signed_preview_url(port, link.token)

    def delete(self):
        self.box.delete(wait=True)


class DaytonaV0Provider:
    """Fallback to Daytona v0 (``client.v0``) snapshots: ``--provider daytona-v0``."""
    name = "daytona-v0"
    platform = "v0"
    metered = True
    image = BUILD_SNAPSHOT

    def __init__(self, policy):
        self.client = daytona_client()

    def find(self, labels):
        # Deleted sandboxes stay listed while Daytona destroys them; they no longer run.
        from daytona.v0 import ListSandboxesQuery
        return [box for box in self.client.v0.list(ListSandboxesQuery(labels=labels))
                if all((box.labels or {}).get(k) == v for k, v in labels.items())
                and str(getattr(box.state, "value", box.state)).lower() not in GONE]

    def remove(self, box):
        from daytona.v0 import DaytonaNotFoundError
        try:
            box.delete(wait=True)
        except DaytonaNotFoundError:
            pass

    def create(self, role, name, labels, ttl_minutes, cache_key):
        from daytona.v0 import CreateSandboxFromSnapshotParams
        snapshot = RENDER_SNAPSHOT if role == "render" else BUILD_SNAPSHOT
        box = self.client.v0.create(CreateSandboxFromSnapshotParams(
            snapshot=snapshot, name=name, labels=labels, public=False,
            auto_stop_interval=ttl_minutes, auto_delete_interval=0, ttl_minutes=ttl_minutes,
        ), timeout=180)
        return DaytonaV0Worker(box), {"snapshot": snapshot, "cache": None}

    transient = staticmethod(daytona_transient)


def docker(*args, check=True, timeout=120):
    return subprocess.run(["docker", *args], capture_output=True, text=True, check=check,
                          timeout=timeout)


class LocalWorker:
    def __init__(self, name, cache_dir):
        self.name = self.id = name
        self.cache_dir = cache_dir

    def resources(self):
        info = json.loads(docker("inspect", self.name).stdout)[0]["HostConfig"]
        return {"cpu": info["NanoCpus"] / 1e9, "gpu": len(info.get("DeviceRequests") or []),
                "memory_gib": info["Memory"] / 2**30, "disk_gib": None}

    def exec(self, command, seconds):
        env = ["-e", f"FACTORY_CACHE_DIR={self.cache_dir}"] if self.cache_dir else []
        try:
            done = subprocess.run(["docker", "exec", *env, self.name, "bash", "-c", command],
                                  capture_output=True, text=True, timeout=seconds)
        except subprocess.TimeoutExpired:
            docker("exec", self.name, "pkill", "-f", "bash /tmp/factory/build.sh", check=False)
            return 124, ""
        return done.returncode, done.stdout

    def upload(self, source, destination):
        with tempfile.TemporaryDirectory() as temporary:
            if isinstance(source, bytes):
                path = Path(temporary) / "upload"
                path.write_bytes(source)
                source = path
            docker("cp", str(source), f"{self.name}:{destination}", timeout=300)

    def download(self, source, destination, seconds):
        docker("cp", f"{self.name}:{source}", str(destination), timeout=max(1, int(seconds)))

    def delete(self):
        docker("rm", "--force", self.name)


class LocalProvider:
    """Self-hosted Docker stand-in: same scripts, limits, labels and deadline; unmetered."""
    name = "local"
    platform = "docker"
    metered = False

    def __init__(self, policy):
        self.limits = policy["worker_limits"]
        tag = hashlib.sha256((HERE / "local-worker.Dockerfile").read_bytes()).hexdigest()[:12]
        self.image = f"{LOCAL_IMAGE}:{tag}"
        if docker("image", "inspect", self.image, check=False).returncode:
            docker("build", "-q", "-t", self.image, "-f", str(HERE / "local-worker.Dockerfile"),
                   str(HERE), timeout=1200)

    def find(self, labels):
        filters = [arg for k, v in labels.items() for arg in ("--filter", f"label={k}={v}")]
        return docker("ps", "--all", "--quiet", *filters).stdout.split()

    def remove(self, container):
        docker("rm", "--force", container)

    def create(self, role, name, labels, ttl_minutes, cache_key):
        volume = f"factory-cache-{cache_key}"
        hit = docker("volume", "inspect", volume, check=False).returncode == 0
        label_args = [arg for k, v in labels.items() for arg in ("--label", f"{k}={v}")]
        # The container's only process sleeps for the TTL, so it removes itself at expiry.
        docker("run", "--detach", "--rm", "--name", name, *label_args,
               "--cpus", str(self.limits["cpu"]), "--memory", f"{self.limits['memory_gib']}g",
               "--volume", f"{volume}:/cache", self.image, "sleep", str(ttl_minutes * 60))
        return LocalWorker(name, "/cache"), {"image": self.image, "cache": {"key": cache_key,
                                                                          "volume": volume, "hit": hit}}

    @staticmethod
    def transient(error):
        return False


PROVIDERS = {"daytona": DaytonaProvider, "daytona-v0": DaytonaV0Provider, "local": LocalProvider}


def make_provider(name, policy):
    return PROVIDERS[name](policy)


def remote(box, command, seconds):
    code, output = box.exec(command, seconds)
    if code != 0:
        raise RuntimeError(f"Worker command exited {code}")
    return output


def exists(box, path, deadline):
    return box.exec(f"test -s {shlex.quote(path)}", deadline.export_bound(15))[0] == 0


def download(box, source, destination, deadline):
    try:
        expected = remote(box, f"sha256sum {shlex.quote(source)}", deadline.export_bound(60)).split()[0]
        box.download(source, destination, deadline.export_bound(300))
        if digest(destination) != expected:
            raise RuntimeError(f"Download integrity check failed for {destination.name}")
    except BaseException:
        Path(destination).unlink(missing_ok=True)
        raise


class Job:
    def __init__(self, args, provider, policy, deadline):
        self.args, self.provider, self.policy, self.deadline = args, provider, policy, deadline
        self.workers = {}
        self.cancelled = False

    def labels(self, role):
        return {"owner": self.args.app, "purpose": PURPOSE, "run": self.args.run, "role": role}

    @contextmanager
    def worker(self, role, cache_key):
        labels = self.labels(role)
        # A prior attempt of this run may have lost its runner before its finally block ran.
        for previous in self.provider.find(labels):
            self.provider.remove(previous)
        others = [w for w in self.provider.find({"purpose": PURPOSE})]
        if len(others) >= self.policy["max_concurrent_workers"]:
            raise RuntimeError("Another factory worker is active; one concurrent worker is allowed.")
        record = {"role": role, "created_at": None, "deleted_at": None, "seconds": None,
                  "deleted": False, "exported_before_delete": False, "attempts": 0}
        self.workers[role] = record
        name = f"factory-{self.args.app}-{self.args.run}-{role}"
        box = None
        for attempt in range(1 + self.policy["transient_retries"]):
            record["attempts"] = attempt + 1
            try:
                box, detail = self.provider.create(role, name, labels, self.deadline.ttl_minutes(),
                                                   cache_key)
                break
            except Exception as error:
                for orphan in self.provider.find(labels):
                    self.provider.remove(orphan)
                if attempt >= self.policy["transient_retries"] or not self.provider.transient(error):
                    raise
                print(f"{role} worker creation hit a transient error; retrying once", flush=True)
        started = time.monotonic()
        record.update(id=box.id, created_at=now(), **detail)
        print(f"{role} worker {box.id} started", flush=True)
        try:
            record["resources"] = box.resources()
            check_resources(self.policy, record["resources"])
            yield box, record
        finally:
            box.delete()
            # Daytona can still list a deleted sandbox as live for a moment; wait until it does not.
            for _ in range(30):
                if not self.provider.find(labels):
                    break
                time.sleep(2)
            else:
                raise RuntimeError(f"{role} worker is still listed after deletion")
            record.update(deleted=True, deleted_at=now(), seconds=round(time.monotonic() - started, 1))
            print(f"{role} worker {box.id} deleted", flush=True)

    def export(self, box, record, names):
        """Copy evidence off the worker before deletion; never mask the original failure."""
        exported = []
        try:
            for name in names:
                try:
                    # Never leave an earlier run's copy in place when this export fails.
                    (self.args.output / name).unlink(missing_ok=True)
                    if exists(box, f"{WORK}/out/{name}", self.deadline):
                        download(box, f"{WORK}/out/{name}", self.args.output / name, self.deadline)
                        exported.append(name)
                except Cancelled:
                    raise
                except Exception as error:
                    print(f"Export of {name} failed ({type(error).__name__})", flush=True)
        finally:
            record["exported"] = sorted(set(record.get("exported", [])) | set(exported))
            record["exported_before_delete"] = "tests.log" in record["exported"]
        return exported

    def build(self, cache_key):
        args = self.args
        with self.worker("build", cache_key) as (box, record):
            with tempfile.TemporaryDirectory() as temporary:
                archive = Path(temporary) / "source.tar.gz"
                subprocess.run(["git", "-C", str(args.repo), "archive", "--format=tar.gz",
                                "-o", str(archive), args.sha], check=True)
                remote(box, f"mkdir -p {WORK}/source {WORK}/out", 30)
                box.upload(archive, f"{WORK}/source.tar.gz")
            box.upload((HERE / "build.sh").read_bytes(), f"{WORK}/build.sh")
            command = (f"SUITE={args.suite} PROBE={args.probe} bash {WORK}/build.sh {args.app} "
                       f"{args.sha} >{WORK}/out/tests.log 2>&1")
            started = time.monotonic()
            try:
                code, _ = box.exec(command, self.deadline.bound(1500))
                record["test_seconds"] = round(time.monotonic() - started, 1)
                record["test_exit"] = code
                if code == 124 or self.deadline.left() <= 0:
                    raise RuntimeError("Job deadline reached during build and tests")
                if code != 0:
                    raise RuntimeError(f"Build and tests exited {code}")
                if args.suite != "demo":
                    return {"status": "not applicable"}
                try:
                    return self.preview(box)
                finally:
                    self.export(box, record, ("preview.log", "capture.webm", "claim.png"))
            finally:
                # A cancelled runner is killed seconds later, so keep only the log before deletion.
                cancelled = isinstance(sys.exc_info()[1], Cancelled) or bool(CANCEL_SIGNAL)
                self.export(box, record, ("tests.log",) if cancelled else EXPORTS)

    def preview(self, box):
        if self.provider.metered:
            return preview(box, self.args.app)
        body = remote(box, "curl -fsS http://127.0.0.1:4173/", 30)
        if self.args.app not in body.lower():
            raise RuntimeError("The local preview did not return the app shell.")
        return {"status": "verified in worker", "signed_url": False, "checked_at": now()}

    def render(self):
        args = self.args
        with self.worker("render", "render") as (box, record):
            try:
                if self.provider.metered:
                    # The v2 image ships node_modules as one archive (see render.Dockerfile).
                    remote(box, f"mkdir -p {WORK}/public {WORK}/out && "
                                f"if [ -f /opt/base/node_modules.tar.gz ]; then "
                                f"tar -xzf /opt/base/node_modules.tar.gz -C /opt/base; fi && "
                                f"ln -s /opt/base/node_modules {WORK}/node_modules", 120)
                    box.upload(args.output / "capture.webm", f"{WORK}/public/capture.webm")
                    box.upload(HERE / "render.tsx", f"{WORK}/index.tsx")
                    box.upload((HERE / "render.sh").read_bytes(), f"{WORK}/render.sh")
                    remote(box, f"cd {WORK} && bash render.sh >out/render.log 2>&1 && "
                                f"cp demo.mp4 out/", self.deadline.bound(360))
                else:
                    remote(box, f"mkdir -p {WORK}/out", 30)
                    box.upload(args.output / "capture.webm", f"{WORK}/capture.webm")
                    remote(box, f"cd {WORK} && ffmpeg -nostdin -y -i capture.webm -c:v libx264 "
                                f"-pix_fmt yuv420p -movflags +faststart out/demo.mp4 "
                                f">out/render.log 2>&1", self.deadline.bound(360))
            finally:
                self.export(box, record, ("render.log", "demo.mp4"))
                record["exported_before_delete"] = "demo.mp4" in record["exported"]


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def preview(box, app):
    ttl = 120
    port = 4173
    opener = build_opener(NoRedirect())
    url, revoke = box.signed_preview(port, ttl)
    try:
        parsed = urlsplit(url)
        if parsed.scheme != "https" or parsed.hostname is None:
            raise RuntimeError("Daytona returned an invalid HTTPS preview URL.")
        with opener.open(url, timeout=20) as response:
            if response.status != 200 or app.encode() not in response.read(200_000).lower():
                raise RuntimeError("The signed preview did not return the app shell.")
    except HTTPError as error:
        raise RuntimeError(f"Signed preview returned HTTP {error.code}.") from None
    finally:
        revoke()

    try:
        with opener.open(url, timeout=15):
            raise RuntimeError("The revoked preview still returned content.")
    except HTTPError as error:
        if error.code not in {302, 401, 403, 404, 410}:
            raise RuntimeError(f"Revoked preview returned HTTP {error.code}.") from None
    return {"status": "verified and revoked", "ttl_seconds": ttl, "revoked_at": now()}


def estimate_usd(policy, workers):
    total = 0.0
    for record in workers.values():
        res = record.get("resources") or {}
        if record.get("seconds") and res.get("cpu"):
            total += hourly_usd(policy, res["cpu"], res["memory_gib"], res.get("disk_gib") or 0) \
                * record["seconds"] / 3600
    return round(total, 4)


def install_cancellation():
    def cancel(signum, frame):
        for sig in (signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, signal.SIG_IGN)
        CANCEL_SIGNAL.append(signum)
        raise Cancelled(f"Cancelled by signal {signum}")
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, cancel)


def run(args, policy):
    validate_run(args.run)
    if args.suite == "journey" and args.app not in JOURNEY_APPS:
        raise ValueError(f"No journey suite is defined for {args.app}.")
    args.output.mkdir(parents=True, exist_ok=True)
    for name in REQUIRED["demo"] | REQUIRED["journey"] | OPTIONAL | {"receipt.json"}:
        (args.output / name).unlink(missing_ok=True)
    started, clock = now(), time.monotonic()
    minutes = policy["max_job_minutes"]
    if args.deadline_epoch:
        minutes = min(minutes, (args.deadline_epoch - time.time()) / 60)
    deadline = Deadline(minutes, policy["export_reserve_seconds"],
                        teardown_seconds=policy["teardown_reserve_seconds"])
    install_cancellation()
    budget = json.loads(args.budget.read_text()) if args.budget else None
    provider = make_provider(args.provider, policy)
    if provider.metered and not budget:
        raise ValueError("A metered provider needs a preflight budget reservation.")
    locks = lockfile_hashes(args.repo, args.app, args.sha)
    image = getattr(provider, "image", BUILD_SNAPSHOT)
    cache_key = args.app + "-" + hashlib.sha256(
        json.dumps([image, locks], sort_keys=True).encode()).hexdigest()[:16]
    job = Job(args, provider, policy, deadline)
    receipt = {"schema": 2, "status": "running", "app": args.app, "suite": args.suite,
               "probe": args.probe, "commit": args.sha, "factory_commit": args.factory_commit,
               "run": args.run, "run_url": run_url(), "provider": provider.name,
               "platform": provider.platform,
               "lockfiles": locks, "policy": {k: policy[k] for k in (
                   "max_job_minutes", "transient_retries", "gpu", "worker_limits",
                   "max_concurrent_workers")},
               "budget": budget or {"funding": "self-hosted Docker; no metered credits"},
               "preview": None, "error": None, "started_at": started}
    failure = None
    try:
        receipt["preview"] = job.build(cache_key)
        if args.suite == "demo":
            job.render()
        if CANCEL_SIGNAL:
            raise Cancelled(f"Cancelled by signal {CANCEL_SIGNAL[0]}")
        receipt["status"] = "passed"
    except Cancelled as error:
        receipt["status"], failure = "cancelled", error
    except Exception as error:
        if CANCEL_SIGNAL:
            error = Cancelled(f"Cancelled by signal {CANCEL_SIGNAL[0]}")
        receipt["status"], failure = ("cancelled" if CANCEL_SIGNAL else "failed"), error
    finally:
        receipt["error"] = None if failure is None else (
            str(failure) if isinstance(failure, (ValueError, RuntimeError)) else type(failure).__name__)
        receipt.update(workers=job.workers, finished_at=now(),
                       total_seconds=round(time.monotonic() - clock, 1),
                       cache=job.workers.get("build", {}).get("cache"),
                       estimated_usd=estimate_usd(policy, job.workers) if provider.metered else 0.0,
                       estimate_basis=("allocated resources x wall time at list rates; the Daytona "
                                       "wallet is authoritative") if provider.metered else
                       "self-hosted; not metered")
        toolchain = args.output / "toolchain.json"
        if toolchain.is_file():
            receipt["toolchain"] = json.loads(toolchain.read_text())
        write_receipt(args.output, receipt)
        print(json.dumps({k: receipt[k] for k in ("status", "error", "total_seconds",
                                                  "estimated_usd")}), flush=True)
    if failure is not None:
        raise failure


def cleanup(args, policy):
    """Independent sweep: count, delete and recount every worker labeled with this run."""
    validate_run(args.run)
    provider = make_provider(args.provider, policy)
    labels = {"purpose": PURPOSE, "run": args.run}
    found = provider.find(labels)
    # Record states before deletion: a v2 sandbox object reflects its state after delete().
    seen = [{"id": getattr(item, "id", item),
             "state": str(getattr(getattr(item, "state", None), "value", getattr(item, "state", None)))}
            for item in found]
    for item in found:
        provider.remove(item)
    remaining = provider.find(labels)
    report = {"run": args.run, "provider": provider.name, "checked_at": now(),
              "found_before_sweep": len(found), "remaining_after_sweep": len(remaining),
              "found": seen,
              "active_factory_workers": len(provider.find({"purpose": PURPOSE}))}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "cleanup.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report), flush=True)
    if found or remaining:
        raise RuntimeError("Workers outlived their job; the sweep found leftovers.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("check", "preflight", "run", "verify", "cleanup"))
    parser.add_argument("--app")
    parser.add_argument("--sha")
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--suite", choices=SUITES, default="demo")
    parser.add_argument("--probe", choices=PROBES, default="none")
    parser.add_argument("--provider", choices=tuple(PROVIDERS), default="daytona",
                        help="daytona = Daytona v2; daytona-v0 = the v0 fallback; local = Docker")
    parser.add_argument("--run", default=os.getenv("GITHUB_RUN_ID"))
    parser.add_argument("--budget", type=Path, help="Preflight reservation written by 'preflight'.")
    parser.add_argument("--credits-usd", type=float)
    parser.add_argument("--cash-fallback-disabled", default="")
    parser.add_argument("--prior-runs", type=int)
    parser.add_argument("--runs", type=Path, help="JSON lines of this workflow's runs since the batch start.")
    parser.add_argument("--current-run", type=Path, help="JSON of this workflow run.")
    parser.add_argument("--run-attempt", type=int, default=int(os.getenv("GITHUB_RUN_ATTEMPT", "0")))
    parser.add_argument("--batch-start", default=os.getenv("BATCH_START"))
    parser.add_argument("--deadline-epoch", type=int, help="Job-level deadline (Unix seconds).")
    parser.add_argument("--factory-commit", default=os.getenv("GITHUB_SHA"))
    args = parser.parse_args()
    policy = load_policy(provider=args.provider)

    if args.command == "cleanup":
        return cleanup(args, policy)
    if args.command == "preflight":
        prior = -1 if args.prior_runs is None else args.prior_runs
        if args.runs:
            runs = json_stream(args.runs.read_text())
            current = json.loads(args.current_run.read_text())
            prior = batch_attempts(runs, current, args.run_attempt, args.batch_start)
        reservation = preflight(policy, args.credits_usd, args.cash_fallback_disabled, prior)
        args.output.write_text(json.dumps(reservation, indent=2) + "\n")
        print(json.dumps(reservation), flush=True)
        return
    validate_request(args.app, args.sha)
    if args.command == "verify":
        if not verify_receipt(args.output, args.app, args.sha, args.suite, args.factory_commit):
            raise ValueError("Artifact receipt does not match the requested revision and files.")
        return
    if not trusted_commit(args.repo, args.sha, BRANCHES[args.app]):
        raise ValueError("Commit is outside the approved source branch history.")
    if args.command == "run":
        run(args, policy)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Keep transport exceptions from revealing auth headers or signed URLs.
        detail = f": {error}" if type(error) in {ValueError, RuntimeError, Cancelled} else ""
        raise SystemExit(f"Factory failed ({type(error).__name__}){detail}") from None
