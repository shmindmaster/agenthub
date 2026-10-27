"""Shared, on-demand content ledger. No provider calls, daemon or automatic resets.

Trusted adapters supply conservative integer reservations and verified receipts.
The database coordinates cooperating processes under ONE OS user on a local disk;
it is not an authorization boundary against that user's own programs.
"""
from __future__ import annotations

import contextlib
import ctypes
import hashlib
import hmac
import json
import os
import pathlib
import re
import sqlite3
import stat
import time
import uuid
from functools import lru_cache

# Owner direction 2026-10-27: "identity is advisory only; never fail, block or re-voice on speaker similarity".
# Speaker identity is no longer a required acceptance gate. A manifest may still carry an "identity" entry for
# information; it is never required, never inspected and cannot reject an acceptance.
ADVISORY_GATES = frozenset({"identity"})
VOICE_GATES = ("content", "pronunciation", "listening", "artifact")
MAX_INTEGER = 2 ** 53 - 1


def integer(value, allow_zero=False):
    if type(value) is not int or not (0 if allow_zero else 1) <= value <= MAX_INTEGER:
        raise ValueError("Cost/ceiling must be a bounded positive integer (zero may pause a budget)")
    return value


def request_key(request: dict) -> str:
    return hashlib.sha256(json.dumps(request, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=False, allow_nan=False).encode("utf-8")).hexdigest()


def running_on_windows() -> bool:
    return os.name == "nt"


def default_root() -> pathlib.Path:
    base = os.environ.get("LOCALAPPDATA") if running_on_windows() else str(pathlib.Path.home() / ".local/share")
    if not base:
        raise RuntimeError("Cannot resolve private local runtime directory")
    return canonical_default_root(pathlib.Path(base) / "AgentHub/runtime/content-controls")


def canonical_default_root(root: pathlib.Path) -> pathlib.Path:
    """Follow an OS runtime relocation only to an intact existing ledger.

    Explicit caller-supplied roots still reject links in secure_directory. A
    relocated default must never silently create a fresh accounting database or
    namespace salt when an operator moved only part of the runtime tree.
    """
    root = root.absolute()
    if not any(linked_path(path) for path in (root, *root.parents)):
        return root
    target = root.resolve()
    if (not (target / "ledger.sqlite3").is_file()
            or not (target / "namespace-salt").is_file()
            or (target / "namespace-salt").stat().st_size != 32):
        raise RuntimeError("Relocated content ledger is incomplete; restore the original "
                           "ledger.sqlite3 and namespace-salt together before paid submissions")
    # Check the resolved target with the normal local-disk and link safeguards.
    # Do not call secure_directory here: resolving a path must not create state.
    if any(linked_path(path) for path in (target, *target.parents)):
        raise RuntimeError("Content ledger refuses linked directories")
    return target


def recovery_epoch_ledger(manifest_path, workspace, text, model_id):
    """Explicit bounded new accounting epoch; never reconstructs old spend.

    Operator authorization locks a small allowlist of demonstrably new/unsubmitted
    speech. All historical requests remain unavailable, including ambiguous ones.
    The normal lifetime ledger is neither created nor configured by this route.
    """
    manifest_path = pathlib.Path(manifest_path)
    raw = manifest_path.read_bytes()
    policy = json.loads(raw)
    ceiling = integer(policy.get("maximum_credits"))
    epoch = policy.get("epoch_id", "")
    if (not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", epoch)
            or ceiling > 1000 or policy.get("historical_accounting") != "UNKNOWN"
            or policy.get("historical_requests") != "FENCED"
            or not policy.get("owner_authorization")
            or policy.get("workspace") != workspace
            or model_id != "eleven_flash_v2_5"):
        raise RuntimeError("Recovery epoch requires explicit bounded authorization and fenced history")
    text_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
    allowed = policy.get("allowed_text_sha256", [])
    if (not allowed or len(allowed) > 20 or text_hash not in allowed
            or any(not re.fullmatch(r"[0-9a-f]{64}", item) for item in allowed)
            or text_hash in policy.get("ambiguous_text_sha256", [])):
        raise RuntimeError("Speech is outside this recovery epoch's new/unsubmitted allowlist")
    base = os.environ.get("LOCALAPPDATA") if running_on_windows() else str(pathlib.Path.home() / ".local/share")
    if not base:
        raise RuntimeError("Cannot resolve private local runtime directory")
    root = (pathlib.Path(base) / "AgentHub/runtime/content-recovery-epochs").resolve() / epoch
    secure_directory(root)
    lock = root / "authorization.json"
    batch = policy.get("additional_batch_id")
    if batch is not None:
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,63}", batch) or not lock.is_file() or linked_path(lock):
            raise RuntimeError("Additional batch requires an intact original epoch authorization")
        original_raw = lock.read_bytes()
        original = json.loads(original_raw)
        if (policy.get("parent_authorization_sha256") != hashlib.sha256(original_raw).hexdigest()
                or any(policy.get(k) != original.get(k) for k in
                       ("epoch_id", "maximum_credits", "workspace", "historical_accounting", "historical_requests"))
                or any(t in original.get("allowed_text_sha256", [])
                       or t in original.get("ambiguous_text_sha256", []) for t in allowed)):
            raise RuntimeError("Additional batch must preserve original cap/history and exclude prior requests")
        batches = root / "additional-batches"
        secure_directory(batches)
        lock = batches / (batch + ".json")
        registration = root / "batch-registration.lock"
        try:
            guard = registration.open("xb")
        except FileExistsError:
            raise RuntimeError("Additional batch registration busy or interrupted; inspect before retry") from None
        try:
            for prior_path in batches.glob("*.json"):
                if prior_path == lock:
                    continue
                if linked_path(prior_path):
                    raise RuntimeError("Linked additional batch refused")
                prior = json.loads(prior_path.read_bytes())
                if any(t in prior.get("allowed_text_sha256", [])
                       or t in prior.get("ambiguous_text_sha256", []) for t in allowed):
                    raise RuntimeError("Additional batch overlaps an existing batch; no repeat authorization")
            try:
                with lock.open("xb") as handle:
                    handle.write(raw)
                    handle.flush()
                    os.fsync(handle.fileno())
            except FileExistsError:
                if linked_path(lock) or lock.read_bytes() != raw:
                    raise RuntimeError("Recovery epoch authorization is immutable; no cap/allowlist reset")
        finally:
            guard.close()
            registration.unlink()
    if linked_path(lock):
        raise RuntimeError("Linked recovery authorization refused")
    try:
        with lock.open("xb") as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
    except FileExistsError:
        if lock.read_bytes() != raw:
            raise RuntimeError("Recovery epoch authorization is immutable; no cap/allowlist reset")
    ledger = Ledger(root)
    with ledger.connect() as con:
        budget = con.execute("SELECT ceiling FROM budgets WHERE bucket='elevenlabs/credits'").fetchone()
    if budget is None:
        ledger.configure("elevenlabs/credits", ceiling)
    elif budget[0] != ceiling:
        raise RuntimeError("Recovery epoch ceiling changed; inspect accounting before submission")
    ledger.recovery_epoch = epoch
    return ledger


@lru_cache(maxsize=1)
def windows_sid():
    from ctypes import wintypes
    token = wintypes.HANDLE()
    kernel, advapi = ctypes.windll.kernel32, ctypes.windll.advapi32
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    advapi.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
    advapi.GetTokenInformation.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    if not advapi.OpenProcessToken(kernel.GetCurrentProcess(), 8, ctypes.byref(token)):
        raise RuntimeError("Cannot establish runtime directory owner")
    try:
        size = wintypes.DWORD()
        advapi.GetTokenInformation(token, 1, None, 0, ctypes.byref(size))
        buffer = ctypes.create_string_buffer(size.value)
        if not advapi.GetTokenInformation(token, 1, buffer, size, ctypes.byref(size)):
            raise RuntimeError("Cannot establish runtime directory owner")
        sid = ctypes.cast(buffer, ctypes.POINTER(ctypes.c_void_p))[0]
        text = wintypes.LPWSTR()
        advapi.ConvertSidToStringSidW.argtypes = [ctypes.c_void_p, ctypes.POINTER(wintypes.LPWSTR)]
        if not advapi.ConvertSidToStringSidW(sid, ctypes.byref(text)):
            raise RuntimeError("Cannot establish runtime directory owner")
        try:
            return text.value
        finally:
            kernel.LocalFree(ctypes.cast(text, ctypes.c_void_p))
    finally:
        kernel.CloseHandle(token)


def linked_path(path: pathlib.Path):
    """Reject all Windows reparse points, including junctions on Python 3.11, and symlinks.

    A POSIX symlink owned by root in a root-owned directory nobody else can write is part of
    the OS layout (macOS's /var -> private/var and /tmp -> private/tmp), not a redirection a
    user could plant, so it does not count.
    """
    try:
        info = path.lstat()
    except FileNotFoundError:
        return False
    if getattr(info, "st_file_attributes", 0) & 0x400:
        return True
    return stat.S_ISLNK(info.st_mode) and not system_owned_link(path, info)


def system_owned_link(path: pathlib.Path, info) -> bool:
    if os.name == "nt" or getattr(info, "st_uid", None) != 0:
        return False
    try:
        parent = path.parent.lstat()
    except OSError:
        return False
    return (parent.st_uid == 0 and not stat.S_ISLNK(parent.st_mode)
            and not parent.st_mode & (stat.S_IWGRP | stat.S_IWOTH))


def secure_directory(root: pathlib.Path):
    root = root.absolute()
    if str(root).startswith(("\\\\", "//")):
        raise RuntimeError("Content ledger requires a local disk")
    if any(linked_path(path) for path in (root, *root.parents)):
        raise RuntimeError("Content ledger refuses linked directories")
    if os.name == "nt":
        if ctypes.windll.kernel32.GetDriveTypeW(root.anchor) != 3:
            raise RuntimeError("Content ledger requires a fixed local disk")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if os.name == "nt":
        # Replace the DACL, rather than retaining unexpected explicit grants.
        from ctypes import wintypes
        descriptor = ctypes.c_void_p()
        advapi = ctypes.windll.advapi32
        advapi.ConvertStringSecurityDescriptorToSecurityDescriptorW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p]
        sddl = f"D:P(A;OICI;FA;;;{windows_sid()})(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)"
        # Reapplying an inherited DACL propagates to every cached asset. Read
        # and compare it first, keeping repeat lookup independent of cache size.
        size = wintypes.DWORD()
        advapi.GetFileSecurityW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
        advapi.GetFileSecurityW(str(root), 4, None, 0, ctypes.byref(size))
        if size.value:
            current = ctypes.create_string_buffer(size.value)
            if advapi.GetFileSecurityW(str(root), 4, current, size, ctypes.byref(size)):
                current_text = wintypes.LPWSTR()
                advapi.ConvertSecurityDescriptorToStringSecurityDescriptorW.argtypes = [ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(wintypes.LPWSTR), ctypes.c_void_p]
                if advapi.ConvertSecurityDescriptorToStringSecurityDescriptorW(current, 1, 4, ctypes.byref(current_text), None):
                    try:
                        if current_text.value == sddl:
                            return
                    finally:
                        ctypes.windll.kernel32.LocalFree(ctypes.cast(current_text, ctypes.c_void_p))
        if not advapi.ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl, 1, ctypes.byref(descriptor), None):
            raise RuntimeError("Cannot build private runtime permissions")
        try:
            advapi.SetFileSecurityW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.c_void_p]
            if not advapi.SetFileSecurityW(str(root), 0x80000004, descriptor):
                raise RuntimeError("Cannot restrict runtime directory permissions")
        finally:
            ctypes.windll.kernel32.LocalFree(descriptor)
    else:
        root.chmod(0o700)


class Ledger:
    @contextlib.contextmanager
    def session(self):
        # Keep the WAL open across a request's short transactions. Closing the
        # last connection after each state change forces repeated checkpoints;
        # this keeper avoids that cost without weakening FULL durability.
        keeper = sqlite3.connect(self.db, timeout=15, isolation_level=None)
        try:
            yield self
        finally:
            keeper.close()

    def __init__(self, root: pathlib.Path | None = None):
        self.root = (pathlib.Path(root) if root is not None else default_root()).absolute()
        secure_directory(self.root)
        self.db = self.root / "ledger.sqlite3"
        self.assets = self.root / "assets"
        self.assets.mkdir(exist_ok=True, mode=0o700)
        if linked_path(self.db) or linked_path(self.assets):
            raise RuntimeError("Linked ledger or asset directory refused")
        with self.connect() as con:
            con.execute("PRAGMA journal_mode=WAL")
            con.executescript("""
                CREATE TABLE IF NOT EXISTS budgets (
                    bucket TEXT PRIMARY KEY, ceiling INTEGER NOT NULL CHECK(ceiling>=0));
                CREATE TABLE IF NOT EXISTS requests (
                    namespace TEXT NOT NULL, key TEXT NOT NULL, bucket TEXT NOT NULL,
                    maximum INTEGER NOT NULL, actual INTEGER, state TEXT NOT NULL,
                    token TEXT NOT NULL, lease REAL NOT NULL, sha256 TEXT, content_type TEXT,
                    receipt TEXT, gates TEXT NOT NULL, acceptance TEXT,
                    PRIMARY KEY(namespace,key), FOREIGN KEY(bucket) REFERENCES budgets(bucket));
            """)

    @contextlib.contextmanager
    def connect(self, write=False):
        con = sqlite3.connect(self.db, timeout=15, isolation_level=None)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA synchronous=FULL")
        con.execute("PRAGMA foreign_keys=ON")
        try:
            if write:
                con.execute("BEGIN IMMEDIATE")
            yield con
            if write:
                con.commit()
        except BaseException:
            if con.in_transaction:
                con.rollback()
            raise
        finally:
            con.close()

    def namespace(self, credential: str, workspace: str) -> str:
        if not credential or not workspace:
            raise RuntimeError("Explicit credential and authorized cache workspace required")
        # Hash with a local random salt. Never store keys, raw prompts or account responses.
        salt_path = self.root / "namespace-salt"
        try:
            with salt_path.open("xb") as handle:
                handle.write(os.urandom(32))
                handle.flush()
                os.fsync(handle.fileno())
        except FileExistsError:
            pass
        salt = salt_path.read_bytes()
        if len(salt) != 32:
            raise RuntimeError("Namespace initialization incomplete; retry without provider submission")
        return hmac.new(salt, (credential + "\0" + workspace).encode(), hashlib.sha256).hexdigest()

    @staticmethod
    def committed(con, bucket):
        return con.execute("SELECT COALESCE(SUM(COALESCE(actual,maximum)),0) FROM requests WHERE bucket=?",
                           (bucket,)).fetchone()[0]

    def configure(self, bucket: str, ceiling: int):
        integer(ceiling, True)
        if not bucket or len(bucket) > 150:
            raise ValueError("Budget bucket required")
        with self.connect(True) as con:
            spent = self.committed(con, bucket)
            if ceiling < spent:
                raise RuntimeError("Budget ceiling cannot be lower than existing commitments")
            con.execute("INSERT INTO budgets VALUES(?,?) ON CONFLICT(bucket) DO UPDATE SET ceiling=excluded.ceiling",
                        (bucket, ceiling))

    def claim(self, namespace: str, key: str, bucket: str, maximum: int,
              lease_seconds: float = 600, required_gates=VOICE_GATES) -> dict:
        integer(maximum)
        if not namespace or not key or not 0 < lease_seconds <= 3600 or not required_gates:
            raise ValueError("Request identity, finite lease and required gates needed")
        gates = json.dumps(sorted(set(required_gates) - ADVISORY_GATES))
        now = time.time()
        with self.connect(True) as con:
            row = con.execute("SELECT * FROM requests WHERE namespace=? AND key=?", (namespace, key)).fetchone()
            if row:
                result = dict(row)
                # Rows written before identity became advisory still list it; compare without it.
                stored = json.dumps(sorted(set(json.loads(row["gates"])) - ADVISORY_GATES))
                if row["bucket"] != bucket or stored != gates:
                    raise RuntimeError("Request budget/gate policy changed; use a new request revision")
                if row["state"] == "prepared" and row["lease"] < now:
                    token = uuid.uuid4().hex
                    con.execute("UPDATE requests SET token=?,lease=? WHERE namespace=? AND key=?",
                                (token, now + lease_seconds, namespace, key))
                    return {**result, "state": "leader", "token": token}
                if row["state"] == "submitted" and row["lease"] < now:
                    con.execute("UPDATE requests SET state='unknown' WHERE namespace=? AND key=?", (namespace, key))
                    result["state"] = "unknown"
                if result["state"] in ("prepared", "submitted"):
                    result["state"] = "wait"
                result.pop("token", None)
                return result
            budget = con.execute("SELECT ceiling FROM budgets WHERE bucket=?", (bucket,)).fetchone()
            if not budget:
                raise RuntimeError("Shared budget unset; paid generation disabled")
            if self.committed(con, bucket) + maximum > budget[0]:
                raise RuntimeError("Shared budget ceiling would be exceeded")
            token = uuid.uuid4().hex
            con.execute("INSERT INTO requests(namespace,key,bucket,maximum,state,token,lease,gates) VALUES(?,?,?,?,'prepared',?,?,?)",
                        (namespace, key, bucket, maximum, token, now + lease_seconds, gates))
            return {"namespace": namespace, "key": key, "token": token, "state": "leader", "maximum": maximum}

    def submitted(self, claim: dict):
        with self.connect(True) as con:
            changed = con.execute("UPDATE requests SET state='submitted' WHERE namespace=? AND key=? AND token=? AND state='prepared' AND lease>=?",
                                  (claim["namespace"], claim["key"], claim["token"], time.time())).rowcount
            if changed != 1:
                raise RuntimeError("Submission lease lost; do not contact provider")

    def cancel_prepared(self, claim):
        """Only a fenced worker that has never submitted may release its reservation."""
        with self.connect(True) as con:
            con.execute("DELETE FROM requests WHERE namespace=? AND key=? AND token=? AND state='prepared'",
                        (claim["namespace"], claim["key"], claim["token"]))

    def release_prepared(self, namespace, key):
        """Owner-operated release; atomic with submission and lease takeover."""
        with self.connect(True) as con:
            changed = con.execute("DELETE FROM requests WHERE namespace=? AND key=? AND state='prepared' AND lease<?",
                                  (namespace, key, time.time())).rowcount
            if changed != 1:
                raise RuntimeError("Release requires an expired, never-submitted reservation")

    def reject(self, claim):
        """The provider refused this fenced submission before generating anything (for example HTTP 429).
        Releases its reservation so the exact request can be submitted again; any other outcome stays unknown."""
        with self.connect(True) as con:
            changed = con.execute("DELETE FROM requests WHERE namespace=? AND key=? AND token=? AND state='submitted'",
                                  (claim["namespace"], claim["key"], claim["token"])).rowcount
            if changed != 1:
                raise RuntimeError("Rejection requires this worker's own submitted request")

    def freeze(self, bucket):
        with self.connect(True) as con:
            changed = con.execute("UPDATE budgets SET ceiling=? WHERE bucket=?",
                                  (self.committed(con, bucket), bucket)).rowcount
            if changed != 1:
                raise RuntimeError("Cannot freeze an unset budget bucket")

    def bind_receipt(self, claim, receipt):
        if not receipt or len(receipt) > 250:
            raise RuntimeError("Invalid provider receipt")
        with self.connect(True) as con:
            changed = con.execute("UPDATE requests SET receipt=? WHERE namespace=? AND key=? AND token=? AND state IN ('submitted','unknown') AND (receipt IS NULL OR receipt=?)",
                                  (receipt, claim["namespace"], claim["key"], claim["token"], receipt)).rowcount
            if changed != 1:
                raise RuntimeError("Provider receipt does not match this submission")

    def lookup(self, namespace, key):
        with self.connect() as con:
            row = con.execute("SELECT * FROM requests WHERE namespace=? AND key=?", (namespace, key)).fetchone()
            return dict(row) if row else None

    def unknown(self, claim: dict, receipt: str | None = None):
        with self.connect(True) as con:
            return con.execute("UPDATE requests SET state='unknown', receipt=COALESCE(receipt,?) WHERE namespace=? AND key=? AND token=? AND state='submitted' AND (receipt IS NULL OR ? IS NULL OR receipt=?)",
                               (receipt, claim["namespace"], claim["key"], claim["token"], receipt, receipt)).rowcount == 1

    def save_asset(self, raw: bytes) -> str:
        if not raw:
            raise RuntimeError("Empty content is not an asset")
        digest = hashlib.sha256(raw).hexdigest()
        temporary = self.assets / (uuid.uuid4().hex + ".tmp")
        try:
            with temporary.open("xb") as handle:
                handle.write(raw)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.assets / digest)
        finally:
            temporary.unlink(missing_ok=True)
        return digest

    def complete(self, claim, raw, content_type, receipt, actual=None, *, recovery=False):
        if not receipt or len(receipt) > 250:
            raise RuntimeError("Completion requires a valid provider receipt")
        if actual is not None:
            integer(actual, True)
        with self.connect(True) as con:
            # Check under the same write lock as the transition. Recovery cannot
            # race a live submission, and invalid completions leave no orphan.
            current = con.execute("SELECT * FROM requests WHERE namespace=? AND key=?",
                                  (claim["namespace"], claim["key"])).fetchone()
            if recovery and current and current["state"] == "submitted" and current["lease"] >= time.time():
                raise RuntimeError("Recovery refused while submission lease is active")
            if (not current or current["token"] != claim["token"] or current["state"] not in ("submitted", "unknown")
                    or (current["receipt"] is not None and current["receipt"] != receipt)):
                raise RuntimeError("Completion state changed; recover the existing provider receipt")
            digest = self.save_asset(raw)
            changed = con.execute("UPDATE requests SET state='pending',sha256=?,content_type=?,receipt=COALESCE(?,receipt),actual=? WHERE namespace=? AND key=? AND token=? AND state IN ('submitted','unknown') AND (receipt IS NULL OR receipt=?)",
                                  (digest, content_type, receipt, actual, claim["namespace"], claim["key"], claim["token"], receipt)).rowcount
            if changed != 1:
                raise RuntimeError("Completion state changed; recover the existing provider receipt")
            return dict(con.execute("SELECT * FROM requests WHERE namespace=? AND key=?", (claim["namespace"], claim["key"])).fetchone())

    def recover(self, namespace, key, raw, content_type, receipt, actual=None):
        """Trusted adapter must verify receipt and request correspondence before calling."""
        with self.connect() as con:
            row = con.execute("SELECT * FROM requests WHERE namespace=? AND key=?", (namespace, key)).fetchone()
        if not row or row["state"] not in ("unknown", "submitted") or not receipt:
            raise RuntimeError("Recovery requires an unresolved submission and verified provider receipt")
        if row["receipt"] and row["receipt"] != receipt:
            raise RuntimeError("Recovery receipt mismatch")
        return self.complete(dict(row), raw, content_type, receipt, actual, recovery=True)

    def settle(self, namespace, key, actual, receipt):
        integer(actual, True)
        with self.connect(True) as con:
            row = con.execute("SELECT * FROM requests WHERE namespace=? AND key=?", (namespace, key)).fetchone()
            if not row or not receipt or row["receipt"] != receipt:
                raise RuntimeError("Settlement requires the bound provider receipt")
            if row["actual"] is not None and row["actual"] != actual:
                raise RuntimeError("Request already settled at a different amount")
            con.execute("UPDATE requests SET actual=? WHERE namespace=? AND key=?", (actual, namespace, key))

    def read_asset(self, row):
        if row["state"] not in ("accepted", "pending") or not row.get("sha256"):
            raise RuntimeError("Request has no reusable generated asset")
        digest = row["sha256"]
        if not re.fullmatch("[0-9a-f]{64}", digest):
            raise RuntimeError("Invalid asset hash")
        raw = (self.assets / digest).read_bytes()
        if hashlib.sha256(raw).hexdigest() != digest:
            raise RuntimeError("Cached asset hash mismatch; no regeneration was requested")
        return raw

    def accept(self, namespace, key, gates):
        with self.connect(True) as con:
            row = con.execute("SELECT * FROM requests WHERE namespace=? AND key=?", (namespace, key)).fetchone()
            if not row or row["state"] not in ("pending", "accepted"):
                raise RuntimeError("Only generated pending content can pass acceptance gates")
            for name in json.loads(row["gates"]):
                if name in ADVISORY_GATES:
                    continue
                gate = gates.get(name, {})
                if gate.get("pass") is not True or gate.get("output_sha256") != row["sha256"] or not re.fullmatch("[0-9a-f]{64}", str(gate.get("evidence_sha256", ""))):
                    raise RuntimeError("Missing passing, hash-bound acceptance gate: " + name)
            self.read_asset(dict(row))
            con.execute("UPDATE requests SET state='accepted',acceptance=? WHERE namespace=? AND key=?",
                        (json.dumps(gates, sort_keys=True), namespace, key))
            return {**dict(row), "state": "accepted", "acceptance": json.dumps(gates, sort_keys=True)}

    def status(self):
        with self.connect() as con:
            budgets = [{**dict(row), "committed": self.committed(con, row["bucket"])}
                       for row in con.execute("SELECT * FROM budgets ORDER BY bucket")]
            states = {row[0]: row[1] for row in con.execute("SELECT state,COUNT(*) FROM requests GROUP BY state")}
        return {"budgets": budgets, "request_states": states, "scope": "cooperating processes; one OS user and local disk"}
