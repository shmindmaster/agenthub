import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
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
                   "workers": {"build": dict(worker), "render": dict(worker)}}
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
        hourly = 4 * 0.0504 + 8 * 0.0162 + 5 * 0.000108
        self.assertAlmostEqual(factory.worst_case_usd(self.policy), round(hourly * 0.5 * 2, 4))

    def test_preflight_fails_closed(self):
        for credits, fallback in ((None, True), (0, True), (200, False), (200, None)):
            with self.subTest(credits=credits, fallback=fallback), self.assertRaises(ValueError):
                factory.preflight(self.policy, credits, fallback, 0)
        with self.assertRaises(ValueError):
            factory.preflight(self.policy, 200, True, -1)

    def test_cap_is_the_smaller_of_ten_dollars_and_ten_percent(self):
        self.assertEqual(factory.preflight(self.policy, 200, True, 0)["cap_usd"], 10)
        self.assertEqual(factory.preflight(self.policy, 20, True, 0)["cap_usd"], 2)
        per_run = factory.worst_case_usd(self.policy)
        allowed = int(2 // per_run)
        self.assertEqual(factory.preflight(self.policy, 20, True, allowed - 1)["reserved_usd"],
                         round(per_run * allowed, 4))
        with self.assertRaises(ValueError):
            factory.preflight(self.policy, 20, True, allowed)

    def test_gpu_or_oversized_workers_are_rejected(self):
        factory.check_resources(self.policy, {"cpu": 2, "gpu": 0, "memory_gib": 4, "disk_gib": None})
        for res in ({"cpu": 2, "gpu": 1}, {"cpu": 8}, {"memory_gib": 16}, {"disk_gib": 50}):
            with self.subTest(res=res), self.assertRaises(RuntimeError):
                factory.check_resources(self.policy, res)

    def test_deadline_reserves_export_time(self):
        clock = [0.0]
        deadline = factory.Deadline(30, 180, clock=lambda: clock[0])
        self.assertEqual(deadline.bound(5000), 1620)
        self.assertEqual(deadline.ttl_minutes(), 31)
        clock[0] = 1700
        with self.assertRaises(RuntimeError):
            deadline.bound(10)
        self.assertEqual(deadline.bound(500, export=True), 100)

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

    def download(self, source, destination):
        self.provider.log.append(("download", Path(source).name))
        Path(destination).write_bytes(self.provider.outputs[Path(source).name])

    def delete(self):
        self.provider.log.append(("delete", self.id))
        self.provider.live.discard(self.id)


class FakeProvider:
    name = "fake"
    metered = False

    def __init__(self, build_exit=0, create_errors=(), outputs=None, gpu=0, on_build=None):
        self.build_exit, self.gpu, self.on_build = build_exit, gpu, on_build
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
    def job(self, provider, root):
        args = SimpleNamespace(app="revolva", run="local-1", sha="a" * 40, repo=Path("."),
                               suite="journey", probe="none", output=root)
        return factory.Job(args, provider, factory.load_policy(), factory.Deadline(30, 180))

    def build(self, provider):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        job = self.job(provider, Path(tmp.name))
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

    def test_a_corrupt_download_is_removed_and_not_reported_exported(self):
        provider = FakeProvider()
        real = FakeBox.download
        def corrupt(box, source, destination):
            real(box, source, destination)
            if Path(source).name == "journeys.tar.gz":
                Path(destination).write_bytes(b"tampered")
        with mock.patch.object(FakeBox, "download", corrupt):
            job, _, _ = self.build(provider)
        self.assertNotIn("journeys.tar.gz", job.workers["build"]["exported"])
        self.assertFalse((job.args.output / "journeys.tar.gz").exists())

    def test_cancellation_during_export_is_not_swallowed(self):
        provider = FakeProvider()
        real = FakeBox.download
        def cancel_on_archive(box, source, destination):
            if Path(source).name == "journeys.tar.gz":
                raise factory.Cancelled("Cancelled by signal 15")
            real(box, source, destination)
        with mock.patch.object(FakeBox, "download", cancel_on_archive):
            job, _, error = self.build(provider)
        self.assertIsInstance(error, factory.Cancelled)
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
