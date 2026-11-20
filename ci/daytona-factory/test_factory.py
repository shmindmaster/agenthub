import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest import mock

import factory


class FactoryTests(unittest.TestCase):
    def test_only_allowlisted_apps_and_full_lowercase_commit(self):
        self.assertEqual(factory.validate_request("abacare", "a" * 40), "a" * 40)
        for app, revision in [("anything", "a" * 40), ("abacare", "main"), ("revolva", "A" * 40),
                              ("empowera", "a" * 40 + "\n"), ("abacare", "--all")]:
            with self.subTest(app=app, revision=revision), self.assertRaises(ValueError):
                factory.validate_request(app, revision)

    def test_only_commits_reachable_from_trusted_refs_are_accepted(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            def git(*args):
                return subprocess.check_output(["git", "-C", str(repo), *args], text=True).strip()
            git("init", "-q")
            git("config", "user.email", "test@example.test")
            git("config", "user.name", "Factory Test")
            git("commit", "--allow-empty", "-qm", "base")
            first = git("rev-parse", "HEAD")
            git("commit", "--allow-empty", "-qm", "trusted")
            git("update-ref", "refs/remotes/origin/main", git("rev-parse", "HEAD"))
            git("checkout", "--detach", "-q", first)
            git("commit", "--allow-empty", "-qm", "foreign branch")
            self.assertTrue(factory.trusted_commit(repo, first, ("main",)))
            self.assertFalse(factory.trusted_commit(repo, git("rev-parse", "HEAD"), ("main",)))

    def receipt(self, **changes):
        worker = {"deleted": True, "exported_before_delete": True}
        receipt = {"schema": 2, "status": "passed", "probe": "none", "app": "abacare",
                   "commit": "a" * 40, "suite": "demo", "factory_commit": "f" * 40,
                   "preview": {"status": "verified and revoked"},
                   "workers": {"build": {**worker, "exported": ["capture.webm", "journeys.tar.gz",
                                                               "tests.log"]},
                               "render": {**worker, "exported": ["demo.mp4"]}}}
        receipt.update(changes)
        return receipt

    def test_receipt_requires_complete_artifacts_and_verifies_hashes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("tests.log", "capture.webm", "demo.mp4"):
                (root / name).write_text(name, encoding="utf-8")
            verify = lambda sha="a" * 40: factory.verify_receipt(root, "abacare", sha, "demo", "f" * 40)
            receipt = factory.write_receipt(root, self.receipt())
            self.assertEqual(json.loads((root / "receipt.json").read_text()), receipt)
            self.assertTrue(verify())
            self.assertFalse(verify("b" * 40))
            with self.assertRaises(ValueError):
                factory.write_receipt(root, self.receipt(workers={}))
            self.assertFalse(verify())
            not_exported = self.receipt()
            not_exported["workers"]["build"]["exported_before_delete"] = False
            factory.write_receipt(root, not_exported)
            self.assertFalse(verify())
            factory.write_receipt(root, self.receipt(probe="fail"))
            self.assertFalse(verify())
            factory.write_receipt(root, self.receipt())
            (root / "demo.mp4").write_text("wrong", encoding="utf-8")
            self.assertFalse(verify())
            (root / "demo.mp4").unlink()
            with self.assertRaises(ValueError):
                factory.write_receipt(root, self.receipt())
            written = json.loads((root / "receipt.json").read_text(encoding="utf-8"))
            self.assertEqual(written["status"], "failed")
            self.assertFalse(verify())

    def test_failed_receipts_keep_partial_evidence_and_never_verify(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "tests.log").write_text("boom", encoding="utf-8")
            receipt = factory.write_receipt(root, self.receipt(status="failed", suite="journey"))
            self.assertEqual(set(receipt["files"]), {"tests.log"})
            self.assertFalse(factory.verify_receipt(root, "abacare", "a" * 40, "journey", "f" * 40))

    def test_files_this_attempt_did_not_export_are_never_hashed_or_verified(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("tests.log", "journeys.tar.gz"):
                (root / name).write_text(name, encoding="utf-8")
            stale = self.receipt(suite="journey")
            stale["workers"] = {"build": {"deleted": True, "exported_before_delete": True,
                                          "exported": ["tests.log"]}}
            with self.assertRaises(ValueError):
                factory.write_receipt(root, stale)
            written = json.loads((root / "receipt.json").read_text(encoding="utf-8"))
            self.assertEqual((written["status"], set(written["files"])), ("failed", {"tests.log"}))
            # A hand-edited receipt that hashes an unexported file still does not verify.
            written.update(status="passed", files={
                name: {"sha256": factory.digest(root / name), "bytes": (root / name).stat().st_size}
                for name in ("tests.log", "journeys.tar.gz")})
            (root / "receipt.json").write_text(json.dumps(written), encoding="utf-8")
            self.assertFalse(factory.verify_receipt(root, "abacare", "a" * 40, "journey", "f" * 40))


class BudgetTests(unittest.TestCase):
    def setUp(self):
        self.policy = factory.load_policy()

    def test_policy_holds_the_section_3_defaults(self):
        self.assertEqual(self.policy["gpu"], 0)
        self.assertEqual(self.policy["max_concurrent_workers"], 1)
        self.assertEqual(self.policy["max_job_minutes"], 30)
        self.assertEqual(self.policy["transient_retries"], 1)
        self.assertEqual(self.policy["pilot_cap_usd"], 10)
        self.assertEqual(self.policy["pilot_cap_credit_fraction"], 0.1)
        for change in ({"gpu": 1}, {"max_concurrent_workers": 2}, {"max_job_minutes": 45},
                       {"transient_retries": 2}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "budget.json"
                path.write_text(json.dumps({**self.policy, **change}))
                with self.assertRaises(ValueError):
                    factory.load_policy(path)

    def test_worst_case_reserves_the_retry(self):
        # Daytona v2: 2 cores at the top on-demand core rate, 8 GiB, free ephemeral disk.
        hourly = 2 * 0.164 + 8 * 0.0113
        self.assertAlmostEqual(factory.worst_case_usd(self.policy), round(hourly * 0.5 * 2, 4))
        v0 = factory.load_policy(provider="daytona-v0")
        hourly = 4 * 0.0504 + 8 * 0.0162 + 5 * 0.000108
        self.assertAlmostEqual(factory.worst_case_usd(v0), round(hourly * 0.5 * 2, 4))
        self.assertEqual((v0["max_job_minutes"], v0["max_concurrent_workers"], v0["gpu"]), (30, 1, 0))
        self.assertIn("daytona.com/pricing", self.policy["rates_source"])
        # A batch can mix platforms, so either platform reserves the dearer worst case.
        for provider in ("daytona", "daytona-v0"):
            reserve = factory.reservation_policy(provider, factory.load_policy(provider=provider))
            self.assertEqual(factory.worst_case_usd(reserve), factory.worst_case_usd(self.policy))

    def test_preflight_fails_closed(self):
        for credits, fallback in ((None, "true"), (0, "true"), (200, "false"), (200, None),
                                  (200, True), (200, "")):
            with self.subTest(credits=credits, fallback=fallback), self.assertRaises(ValueError):
                factory.preflight(self.policy, credits, fallback, 0)
        with self.assertRaises(ValueError):
            factory.preflight(self.policy, 200, "true", -1)

    def test_cap_is_the_smaller_of_ten_dollars_and_ten_percent(self):
        self.assertEqual(factory.preflight(self.policy, 200, "true", 0)["cap_usd"], 10)
        self.assertEqual(factory.preflight(self.policy, 20, "true", 0)["cap_usd"], 2)
        per_run = factory.worst_case_usd(self.policy)
        allowed = int(2 // per_run)
        self.assertEqual(factory.preflight(self.policy, 20, "true", allowed - 1)["reserved_usd"],
                         round(per_run * allowed, 4))
        with self.assertRaises(ValueError):
            factory.preflight(self.policy, 20, "true", allowed)

    def test_unverified_fallback_is_recorded_as_unreachable_under_cap(self):
        reservation = factory.preflight(self.policy, 900, "unreachable-under-cap", 0)
        self.assertEqual(reservation["cap_usd"], 10)
        self.assertEqual(reservation["cash_fallback"], "unverified; unreachable under the pilot cap")
        self.assertEqual(factory.preflight(self.policy, 900, "true", 0)["cash_fallback"], "disabled")

    def test_gpu_or_oversized_workers_are_rejected(self):
        factory.check_resources(self.policy, {"cpu": 2, "gpu": 0, "memory_gib": 4, "disk_gib": None})
        for res in ({"cpu": 2, "gpu": 1}, {"cpu": 8}, {"memory_gib": 16}, {"disk_gib": 50}):
            with self.subTest(res=res), self.assertRaises(RuntimeError):
                factory.check_resources(self.policy, res)

    def test_deadline_reserves_export_time(self):
        clock = [0.0]
        deadline = factory.Deadline(30, 180, clock=lambda: clock[0])
        self.assertEqual(deadline.bound(5000), 1620)
        self.assertEqual(deadline.ttl_minutes(), 30)
        clock[0] = 1745
        with self.assertRaises(RuntimeError):
            deadline.ttl_minutes()
        clock[0] = 0
        clock[0] = 1700
        with self.assertRaises(RuntimeError):
            deadline.bound(10)
        self.assertEqual(deadline.bound(500, export=True), 100)

    def test_teardown_tail_must_sit_inside_the_export_reserve(self):
        for value in (0, 180, 400):
            with self.subTest(value=value), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "budget.json"
                path.write_text(json.dumps({**self.policy, "teardown_reserve_seconds": value}))
                with self.assertRaises(ValueError):
                    factory.load_policy(path)

    def test_export_operations_end_before_the_teardown_tail(self):
        clock = [0.0]
        deadline = factory.Deadline(30, 180, clock=lambda: clock[0], teardown_seconds=60)
        clock[0] = 1800 - 100
        self.assertEqual(deadline.export_bound(300), 40)
        clock[0] = 1800 - 60
        with self.assertRaises(RuntimeError):
            deadline.export_bound(300)

    def run_record(self, id, attempt, status="completed", created="2026-11-21T10:00:00Z"):
        return {"id": id, "status": status, "run_attempt": attempt, "created_at": created}

    def test_batch_counts_every_started_attempt(self):
        current = self.run_record(30, 3, "in_progress")
        runs = [self.run_record(10, 2), self.run_record(20, 1), current,
                self.run_record(40, 2, "queued")]
        self.assertEqual(factory.batch_attempts(runs, current, 3, "2026-11-21"), 2 + 1 + 2 + 1)
        stream = "".join(json.dumps(r, indent=2) + "\n" for r in runs)
        self.assertEqual(factory.json_stream(stream), runs)

    def test_reruns_of_pre_batch_runs_are_refused_every_time(self):
        old = self.run_record(111, 1, "in_progress", created="2026-11-20T09:00:00Z")
        # The batch moves forward; the old run is absent from the batch list on every rerun.
        for attempt in range(2, 6):
            with self.subTest(attempt=attempt), self.assertRaisesRegex(ValueError, "before DAYTONA"):
                factory.batch_attempts([], dict(old, run_attempt=attempt), attempt, "2026-11-21")
        with self.assertRaisesRegex(ValueError, "before DAYTONA"):
            factory.batch_attempts([], old, 2, "2026-11-20T09:00:01Z")
        self.assertEqual(factory.batch_attempts([old], old, 2, "2026-11-20T09:00:00Z"), 1)

    def test_preflight_cli_refuses_a_pre_batch_rerun(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "runs.jsonl").write_text("")
            (root / "current.json").write_text(json.dumps(
                self.run_record(111, 4, "in_progress", created="2026-11-20T09:00:00Z")))
            done = subprocess.run(
                ["python3", str(Path(factory.__file__)), "preflight", "--credits-usd", "200",
                 "--cash-fallback-disabled", "true", "--runs", str(root / "runs.jsonl"),
                 "--current-run", str(root / "current.json"), "--run-attempt", "4",
                 "--batch-start", "2026-11-21", "--output", str(root / "budget.json")],
                capture_output=True, text=True)
            self.assertNotEqual(done.returncode, 0)
            self.assertIn("pre-batch", done.stderr)
            self.assertFalse((root / "budget.json").exists())

    def test_upload_paths_never_depend_on_a_step_set_variable(self):
        workflow = (factory.HERE.parent.parent / ".github/workflows/daytona-factory.yml").read_text()
        paths = [line.split("path:", 1)[1].strip() for line in workflow.splitlines()
                 if line.strip().startswith("path:")]
        self.assertTrue(paths)
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue(path.startswith("${{ runner.temp }}/"))

    def test_local_worker_image_carries_what_the_abacare_setup_starts(self):
        dockerfile = (factory.HERE / "local-worker.Dockerfile").read_text()
        build = (factory.HERE / "build.sh").read_text()
        for service, package in (("postgresql", "postgresql"), ("redis-server", "redis-server")):
            with self.subTest(service=service):
                self.assertIn(f"service {service} start", build)
                self.assertRegex(dockerfile, rf"apt-get install[^\n]*(\n[^\n]*\\?)*\b{package}\b")
        self.assertIn("pnpm install", build)
        self.assertIn("corepack enable pnpm", dockerfile)

    def test_daytona_provider_uses_v2_search_images_and_a_delete_lifecycle(self):
        client = mock.MagicMock()
        root = SimpleNamespace(Daytona=mock.Mock(return_value=client),
                               DaytonaConfig=mock.Mock(side_effect=lambda **kw: kw))
        v2 = SimpleNamespace(Resources=lambda **kw: kw)
        errors = SimpleNamespace(NotFoundError=LookupError)
        live = SimpleNamespace(id="a", labels={"run": "1"}, state="started", refresh_data=mock.Mock())
        gone = SimpleNamespace(id="b", labels={"run": "1"}, state="destroyed", refresh_data=mock.Mock())
        missing = SimpleNamespace(id="c", labels={"run": "1"}, state="started",
                                  refresh_data=mock.Mock(side_effect=LookupError))
        client.v2.create.return_value.state = "started"
        client.v2.search.side_effect = [SimpleNamespace(items=[live, gone], next_cursor="c"),
                                        SimpleNamespace(items=[missing], next_cursor=None)]
        modules = {"daytona": root, "daytona.v2": v2, "daytona.v2.errors": errors}
        with mock.patch.dict(sys.modules, modules), \
                mock.patch.dict(factory.os.environ, {"DAYTONA_FACTORY_API_KEY": "test"}):
            provider = factory.make_provider("daytona", factory.load_policy())
            self.assertEqual(provider.find({"run": "1"}), [live])
            _, detail = provider.create("render", "w", {"run": "1"}, 10, None)
        root.DaytonaConfig.assert_called_once_with(api_key="test")
        self.assertEqual(client.v2.search.call_args_list[1].kwargs["cursor"], "c")
        client.v2.list.assert_not_called()
        client.v0.create.assert_not_called()
        (image,), kwargs = client.v2.create.call_args
        self.assertEqual((image, detail["image"]), (factory.RENDER_IMAGE, factory.RENDER_IMAGE))
        self.assertEqual(kwargs["lifecycle_policy"], {"timeout_seconds": 600, "on_timeout": "delete"})
        self.assertEqual(kwargs["resources"]["cpu_max"], 2)
        self.assertFalse(kwargs["spot"])

    def test_v2_workers_are_found_before_indexing_and_unstarted_ones_are_retried(self):
        client = mock.MagicMock()
        sdk_errors = {name: type(name, (Exception,), {}) for name in (
            "DaytonaConnectionError", "DaytonaRateLimitError", "DaytonaServiceUnavailableError",
            "DaytonaTimeoutError")}
        root = SimpleNamespace(Daytona=mock.Mock(return_value=client),
                               DaytonaConfig=mock.Mock(side_effect=lambda **kw: kw), **sdk_errors)
        v2 = SimpleNamespace(Resources=lambda **kw: kw)
        errors = SimpleNamespace(NotFoundError=LookupError)
        box = SimpleNamespace(id="sbx_1", labels={"run": "1"}, state="started",
                              refresh_data=mock.Mock(), delete=mock.Mock())
        client.v2.create.return_value = box
        client.v2.search.return_value = SimpleNamespace(items=[], next_cursor=None)
        modules = {"daytona": root, "daytona.v2": v2, "daytona.v2.errors": errors}
        with mock.patch.dict(sys.modules, modules), \
                mock.patch.dict(factory.os.environ, {"DAYTONA_FACTORY_API_KEY": "test"}):
            provider = factory.make_provider("daytona", factory.load_policy())
            provider.create("build", "w", {"run": "1"}, 10, None)
            self.assertEqual(provider.find({"run": "1"}), [box])
            box.state = "starting"
            with self.assertRaises(TimeoutError) as raised:
                provider.create("build", "w", {"run": "1"}, 10, None)
            self.assertTrue(provider.transient(raised.exception))
            box.delete.assert_called_once()

    def test_daytona_v2_worker_maps_timeouts_bytes_and_bounded_downloads(self):
        box = mock.MagicMock()
        worker = factory.DaytonaWorker(box)
        box.exec.return_value = SimpleNamespace(exit_code=3, reason="exited", output="log")
        errors = SimpleNamespace(ProcessExecutionTimeoutError=TimeoutError)
        with mock.patch.dict(sys.modules, {"daytona.v2.errors": errors}):
            self.assertEqual(worker.exec("x", 10), (3, "log"))
            self.assertEqual(box.exec.call_args.kwargs["execution_timeout"], 10)
            box.exec.return_value = SimpleNamespace(exit_code=None, reason="timed_out", output="")
            self.assertEqual(worker.exec("x", 10)[0], 124)
            box.exec.side_effect = TimeoutError
            self.assertEqual(worker.exec("x", 10)[0], 124)
        worker.upload(b"data", "/w/a")
        box.fs.write_bytes.assert_called_once_with("/w/a", b"data")
        worker.download("/w/a", Path("a"), 0)
        signal = box.fs.download_file.call_args.kwargs["cancel"]
        time.sleep(1.05)
        self.assertTrue(signal.is_set())

    def test_daytona_v0_fallback_calls_v0_without_an_api_url(self):
        client = mock.MagicMock()
        root = SimpleNamespace(Daytona=mock.Mock(return_value=client),
                               DaytonaConfig=mock.Mock(side_effect=lambda **kw: kw))
        v0 = SimpleNamespace(ListSandboxesQuery=lambda labels: labels,
                             CreateSandboxFromSnapshotParams=lambda **kw: kw)
        client.v0.list.return_value = []
        modules = {"daytona": root, "daytona.v0": v0}
        with mock.patch.dict(sys.modules, modules), \
                mock.patch.dict(factory.os.environ, {"DAYTONA_FACTORY_API_KEY": "test"}):
            provider = factory.make_provider("daytona-v0", factory.load_policy(provider="daytona-v0"))
            provider.find({"run": "1"})
            provider.create("build", "w", {"run": "1"}, 10, None)
        root.DaytonaConfig.assert_called_once_with(api_key="test")
        client.v0.list.assert_called_once()
        client.v0.create.assert_called_once()
        workflow = (factory.HERE.parent.parent / ".github/workflows/daytona-factory.yml").read_text()
        self.assertIn('pip install "daytona[v0-sdk]==2.', workflow)

    def test_run_ids_are_numeric_or_local(self):
        for run in ("123", "local-1"):
            self.assertEqual(factory.validate_run(run), run)
        for run in ("", None, "1;rm", "local-x"):
            with self.subTest(run=run), self.assertRaises(ValueError):
                factory.validate_run(run)


class FakeBox:
    def __init__(self, name, provider, gpu=0):
        self.id = name
        self.provider = provider
        self.gpu = gpu
        self.files = {}

    def resources(self):
        return {"cpu": 2, "gpu": self.gpu, "memory_gib": 4, "disk_gib": 10}

    def exec(self, command, seconds):
        self.provider.log.append(("exec", command))
        if command.startswith("test -s"):
            return (0, "") if command.split()[-1].rsplit("/", 1)[-1] in self.provider.outputs else (1, "")
        if command.startswith("sha256sum"):
            name = command.split()[-1].rsplit("/", 1)[-1]
            return 0, hashlib.sha256(self.provider.outputs[name]).hexdigest()
        if "build.sh" in command:
            if self.provider.on_build:
                self.provider.on_build()
            return self.provider.build_exit, ""
        return 0, ""

    def upload(self, source, destination):
        pass

    def download(self, source, destination, seconds):
        self.provider.log.append(("download", Path(source).name, seconds))
        if self.provider.on_download:
            self.provider.on_download(Path(source).name, seconds)
        Path(destination).write_bytes(self.provider.outputs[Path(source).name])

    def delete(self):
        self.provider.log.append(("delete", self.id))
        self.provider.live.discard(self.id)


class FakeProvider:
    name = "fake"
    metered = False

    def __init__(self, build_exit=0, create_errors=(), outputs=None, gpu=0, on_build=None):
        self.build_exit, self.gpu, self.on_build = build_exit, gpu, on_build
        self.on_download = None
        self.create_errors = list(create_errors)
        self.outputs = outputs if outputs is not None else {"tests.log": b"ok", "journeys.tar.gz": b"v"}
        self.live, self.log = set(), []

    def find(self, labels):
        return sorted(name for name in self.live
                      if f"-{labels.get('run', '')}-" in name or "run" not in labels
                      if name.endswith(labels.get("role", "")))

    def remove(self, item):
        self.live.discard(item)

    def create(self, role, name, labels, ttl_minutes, cache_key):
        if self.create_errors:
            raise self.create_errors.pop(0)
        self.live.add(name)
        self.log.append(("create", name, ttl_minutes))
        return FakeBox(name, self, self.gpu), {"cache": {"key": cache_key, "hit": False}}

    @staticmethod
    def transient(error):
        return isinstance(error, ConnectionError)


class JobTests(unittest.TestCase):
    def job(self, provider, root, deadline=None):
        args = SimpleNamespace(app="revolva", run="local-1", sha="a" * 40, repo=Path("."),
                               suite="journey", probe="none", output=root)
        return factory.Job(args, provider, factory.load_policy(),
                           deadline or factory.Deadline(30, 180, teardown_seconds=60))

    def build(self, provider, deadline=None, root=None):
        if root is None:
            tmp = tempfile.TemporaryDirectory()
            self.addCleanup(tmp.cleanup)
            root = Path(tmp.name)
        job = self.job(provider, root, deadline)
        with mock.patch.object(factory.subprocess, "run"):
            try:
                return job, job.build("key"), None
            except Exception as error:
                return job, None, error

    def test_evidence_is_exported_before_the_worker_is_deleted(self):
        provider = FakeProvider()
        job, result, error = self.build(provider)
        self.assertIsNone(error)
        events = [e[0] + ":" + str(e[1]) for e in provider.log if e[0] in {"download", "delete"}]
        self.assertEqual(events[-1], "delete:factory-revolva-local-1-build")
        self.assertIn("download:journeys.tar.gz", events)
        self.assertTrue(job.workers["build"]["exported_before_delete"])
        self.assertTrue(job.workers["build"]["deleted"])
        self.assertEqual(provider.live, set())

    def test_test_failures_stay_failures_and_still_export_and_delete(self):
        provider = FakeProvider(build_exit=1, outputs={"tests.log": b"failed"})
        job, _, error = self.build(provider)
        self.assertIsInstance(error, RuntimeError)
        self.assertEqual(job.workers["build"]["test_exit"], 1)
        self.assertEqual(job.workers["build"]["exported"], ["tests.log"])
        self.assertEqual(provider.live, set())

    def test_cancellation_exports_the_log_then_deletes(self):
        provider = FakeProvider()
        def cancel():
            raise factory.Cancelled("Cancelled by signal 2")
        provider.on_build = cancel
        job, _, error = self.build(provider)
        self.assertIsInstance(error, factory.Cancelled)
        self.assertEqual(job.workers["build"]["exported"], ["tests.log"])
        self.assertEqual(provider.live, set())

    def test_cancellation_wrapped_by_the_sdk_still_exports_only_the_log(self):
        provider = FakeProvider()
        def cancel():
            factory.CANCEL_SIGNAL.append(15)
            raise RuntimeError("DaytonaError")
        provider.on_build = cancel
        try:
            job, _, error = self.build(provider)
        finally:
            factory.CANCEL_SIGNAL.clear()
        self.assertIsInstance(error, RuntimeError)
        self.assertEqual(job.workers["build"]["exported"], ["tests.log"])
        self.assertEqual(provider.live, set())

    def test_a_corrupt_download_is_removed_and_not_reported_exported(self):
        provider = FakeProvider()
        real = FakeBox.download
        def corrupt(box, source, destination, seconds):
            real(box, source, destination, seconds)
            if Path(source).name == "journeys.tar.gz":
                Path(destination).write_bytes(b"tampered")
        with mock.patch.object(FakeBox, "download", corrupt), \
                mock.patch("builtins.print") as printed:
            job, _, _ = self.build(provider)
        self.assertIn(("download", "journeys.tar.gz", 300), provider.log)
        printed.assert_any_call("Export of journeys.tar.gz failed (RuntimeError)", flush=True)
        self.assertNotIn("journeys.tar.gz", job.workers["build"]["exported"])
        self.assertFalse((job.args.output / "journeys.tar.gz").exists())

    def test_cancellation_during_export_is_not_swallowed(self):
        provider = FakeProvider()
        real = FakeBox.download
        def cancel_on_archive(box, source, destination, seconds):
            if Path(source).name == "journeys.tar.gz":
                raise factory.Cancelled("Cancelled by signal 15")
            real(box, source, destination, seconds)
        with mock.patch.object(FakeBox, "download", cancel_on_archive):
            job, _, error = self.build(provider)
        self.assertIsInstance(error, factory.Cancelled)
        self.assertTrue(job.workers["build"]["deleted"])
        self.assertEqual(provider.live, set())

    def test_a_failed_export_never_keeps_an_earlier_runs_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "journeys.tar.gz").write_bytes(b"revision A")
            provider = FakeProvider()
            real = FakeBox.exec
            def flaky(box, command, seconds):
                if command.startswith("test -s") and command.endswith("journeys.tar.gz"):
                    raise ConnectionError("worker unreachable")
                return real(box, command, seconds)
            with mock.patch.object(FakeBox, "exec", flaky):
                job, _, error = self.build(provider, root=root)
            self.assertIsNone(error)
            self.assertFalse((root / "journeys.tar.gz").exists())
            self.assertNotIn("journeys.tar.gz", job.workers["build"]["exported"])
            receipt = {"schema": 2, "status": "passed", "probe": "none", "app": "revolva",
                       "commit": "a" * 40, "suite": "journey", "factory_commit": "f" * 40,
                       "preview": None, "workers": job.workers}
            with self.assertRaises(ValueError):
                factory.write_receipt(root, receipt)
            self.assertFalse(factory.verify_receipt(root, "revolva", "a" * 40, "journey", "f" * 40))

    def test_run_clears_earlier_evidence_before_starting(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("journeys.tar.gz", "tests.log", "receipt.json", "notes.txt"):
                (root / name).write_text("revision A")
            args = SimpleNamespace(run="local-1", suite="journey", app="revolva", output=root,
                                   deadline_epoch=None, budget=None, provider="fake", repo=Path("."),
                                   sha="a" * 40, probe="none", factory_commit="f" * 40)
            with mock.patch.object(factory, "make_provider", side_effect=RuntimeError("stop")), \
                    mock.patch.object(factory, "install_cancellation"), self.assertRaises(RuntimeError):
                factory.run(args, factory.load_policy())
            self.assertEqual(sorted(p.name for p in root.iterdir()), ["notes.txt"])

    def test_downloads_are_bounded_by_the_export_window(self):
        clock = [0.0]
        deadline = factory.Deadline(30, 180, clock=lambda: clock[0], teardown_seconds=60)
        provider = FakeProvider()
        def build_until_late():
            clock[0] = 1800 - 150
        provider.on_build = build_until_late
        def stalled(name, seconds):
            # Every transfer stalls for 70 s; the provider gives up at the timeout it was handed.
            clock[0] += min(70, seconds)
            if seconds < 70:
                raise TimeoutError(name)
        provider.on_download = stalled
        job, _, error = self.build(provider, deadline)
        self.assertIsInstance(error, RuntimeError)  # build ended past the test deadline
        timeouts = [e[2] for e in provider.log if e[0] == "download"]
        self.assertEqual(timeouts, [90, 20])
        self.assertLessEqual(clock[0], 1800 - 60)
        self.assertEqual(job.workers["build"]["exported"], ["tests.log"])
        self.assertTrue(job.workers["build"]["deleted"])
        self.assertEqual(provider.live, set())

    def test_journey_suite_is_refused_for_apps_without_journeys(self):
        args = SimpleNamespace(run="local-1", suite="journey", app="abacare")
        with self.assertRaisesRegex(ValueError, "No journey suite"):
            factory.run(args, factory.load_policy())

    def test_one_retry_for_transient_creation_errors_only(self):
        job, _, error = self.build(FakeProvider(create_errors=[ConnectionError()]))
        self.assertIsNone(error)
        self.assertEqual(job.workers["build"]["attempts"], 2)
        _, _, error = self.build(FakeProvider(create_errors=[ConnectionError(), ConnectionError()]))
        self.assertIsInstance(error, ConnectionError)
        _, _, error = self.build(FakeProvider(create_errors=[ValueError("quota")]))
        self.assertIsInstance(error, ValueError)

    def test_a_second_concurrent_worker_is_refused(self):
        provider = FakeProvider()
        provider.live.add("factory-empowera-99-build")
        _, _, error = self.build(provider)
        self.assertIn("one concurrent worker", str(error))
        self.assertFalse(any(e[0] == "create" for e in provider.log))

    def test_gpu_workers_are_deleted_and_refused(self):
        provider = FakeProvider(gpu=1)
        _, _, error = self.build(provider)
        self.assertIn("GPU", str(error))
        self.assertEqual(provider.live, set())

    def test_worker_ttl_never_outlives_the_job(self):
        provider = FakeProvider()
        self.build(provider)
        ttl = [e[2] for e in provider.log if e[0] == "create"][0]
        self.assertLessEqual(ttl, 31)

    def test_cleanup_sweep_reports_and_fails_on_leftovers(self):
        provider = FakeProvider()
        with tempfile.TemporaryDirectory() as tmp, \
                mock.patch.object(factory, "make_provider", return_value=provider):
            args = SimpleNamespace(run="local-1", provider="fake", output=Path(tmp))
            factory.cleanup(args, factory.load_policy())
            report = json.loads((Path(tmp) / "cleanup.json").read_text())
            self.assertEqual(report["found_before_sweep"], 0)
            provider.live.add("factory-revolva-local-1-build")
            with self.assertRaises(RuntimeError):
                factory.cleanup(args, factory.load_policy())
            report = json.loads((Path(tmp) / "cleanup.json").read_text())
            self.assertEqual((report["found_before_sweep"], report["remaining_after_sweep"]), (1, 0))


if __name__ == "__main__":
    unittest.main()
