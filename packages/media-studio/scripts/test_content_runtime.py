"""Offline, independent-process tests. Fixtures never contact a provider."""
import contextlib
import hashlib
import json
import os
import pathlib
import sqlite3
import stat
import subprocess
import sys
import tempfile
import time
import unittest

from content_runtime import Ledger, request_key
from content_control import accept_manifest
from unittest.mock import patch
from types import SimpleNamespace
from content_runtime import linked_path, canonical_default_root, recovery_epoch_ledger

# The content ledger refuses linked directories by design. Resolve the temp root once so
# fixtures stay valid when TMPDIR sits under a junction (e.g. %LOCALAPPDATA%\AgentHub).
tempfile.tempdir = os.path.realpath(tempfile.gettempdir())


class LedgerTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = pathlib.Path(self.folder.name)
        self.ledger = Ledger(self.root)
        self.ledger.configure("fixture/credits", 10)

    def claim(self, key="same", maximum=4, namespace="account-a", lease=1):
        return self.ledger.claim(namespace, key, "fixture/credits", maximum, lease)

    def finish(self, claim, cost=None):
        self.ledger.submitted(claim)
        return self.ledger.complete(claim, b"exact fixture bytes", "audio/fixture", "receipt-1", cost)

    def test_disabled_by_default_and_invalid_costs(self):
        for value in (0, -1, 1.5, True, float("nan")):
            with self.assertRaises(ValueError):
                self.claim(maximum=value)
        with self.assertRaisesRegex(RuntimeError, "budget"):
            self.ledger.claim("account", "key", "unset", 1)

    def test_nonleader_cannot_obtain_worker_token(self):
        leader = self.claim()
        waiter = self.claim()
        self.assertNotIn("token", waiter)
        self.assertEqual(self.ledger.lookup("account-a", "same")["token"], leader["token"])

    def test_recovery_refuses_active_submission_and_accepts_expired_submission(self):
        claim = self.claim()
        self.ledger.submitted(claim)
        self.ledger.bind_receipt(claim, "receipt-1")
        with self.assertRaisesRegex(RuntimeError, "active"):
            self.ledger.recover("account-a", "same", b"recovered", "audio/fixture", "receipt-1", 2)
        with self.ledger.connect(True) as con:
            con.execute("UPDATE requests SET lease=0")
        row = self.ledger.recover("account-a", "same", b"recovered", "audio/fixture", "receipt-1", 2)
        self.assertEqual(row["state"], "pending")

    def test_missing_receipt_cannot_become_reusable_content(self):
        claim = self.claim()
        self.ledger.submitted(claim)
        with self.assertRaisesRegex(RuntimeError, "receipt"):
            self.ledger.complete(claim, b"fixture", "audio/fixture", None)
        self.assertEqual(self.ledger.lookup("account-a", "same")["state"], "submitted")
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 4)

    def test_reject_releases_only_this_workers_submission(self):
        claim = self.claim()
        with self.assertRaisesRegex(RuntimeError, "submitted"):
            self.ledger.reject(claim)
        self.ledger.submitted(claim)
        with self.assertRaisesRegex(RuntimeError, "submitted"):
            self.ledger.reject({**claim, "token": "another worker"})
        self.ledger.reject(claim)
        self.assertIsNone(self.ledger.lookup("account-a", "same"))
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 0)
        self.assertEqual(self.claim()["state"], "leader")

    def test_release_requires_expired_never_submitted_reservation(self):
        claim = self.claim()
        with self.assertRaisesRegex(RuntimeError, "expired"):
            self.ledger.release_prepared("account-a", "same")
        with self.ledger.connect(True) as con:
            con.execute("UPDATE requests SET lease=0")
        self.ledger.release_prepared("account-a", "same")
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 0)
        with self.assertRaisesRegex(RuntimeError, "lease"):
            self.ledger.submitted(claim)
        submitted = self.claim()
        self.ledger.submitted(submitted)
        with self.ledger.connect(True) as con:
            con.execute("UPDATE requests SET lease=0")
        for state in ("submitted", "unknown"):
            with self.assertRaisesRegex(RuntimeError, "expired"):
                self.ledger.release_prepared("account-a", "same")
            self.ledger.unknown(submitted)

    def test_freeze_unknown_bucket_fails_and_existing_bucket_retains_commitments(self):
        with self.assertRaisesRegex(RuntimeError, "bucket"):
            self.ledger.freeze("missing")
        self.claim()
        self.ledger.freeze("fixture/credits")
        self.assertEqual(self.ledger.status()["budgets"][0]["ceiling"], 4)
        with self.assertRaisesRegex(RuntimeError, "ceiling"):
            self.claim("other")

    def test_reparse_point_detection_does_not_require_python312_path_api(self):
        with patch.object(pathlib.Path, "lstat", return_value=SimpleNamespace(st_file_attributes=0x400, st_mode=0)):
            self.assertTrue(linked_path(self.root))
        self.assertFalse(linked_path(self.root / "absent"))

    @unittest.skipIf(os.name == "nt", "POSIX symlink ownership")
    def test_root_owned_os_links_pass_but_user_or_writable_dir_links_are_refused(self):
        def stats(link_uid, parent_mode):
            return [SimpleNamespace(st_mode=stat.S_IFLNK | 0o755, st_uid=link_uid),
                    SimpleNamespace(st_mode=stat.S_IFDIR | parent_mode, st_uid=0)]
        with patch.object(pathlib.Path, "lstat", side_effect=stats(0, 0o755)):
            self.assertFalse(linked_path(pathlib.Path("/var")))  # macOS /var -> private/var
        with patch.object(pathlib.Path, "lstat", side_effect=stats(501, 0o755)):
            self.assertTrue(linked_path(pathlib.Path("/var")))
        with patch.object(pathlib.Path, "lstat", side_effect=stats(0, 0o1777)):
            self.assertTrue(linked_path(pathlib.Path("/tmp/planted")))

    def test_default_relocation_reuses_existing_accounting_and_namespace(self):
        salt = self.root / "namespace-salt"
        salt.write_bytes(b"s" * 32)
        self.claim()
        alias = self.root.parent / (self.root.name + "-alias")
        with patch("content_runtime.linked_path", side_effect=lambda path: path == alias), \
                patch.object(pathlib.Path, "resolve", return_value=self.root):
            self.assertEqual(canonical_default_root(alias), self.root)
        self.assertEqual(salt.read_bytes(), b"s" * 32)
        self.assertEqual(Ledger(self.root).status()["budgets"][0]["committed"], 4)

    def test_default_relocation_refuses_missing_or_partial_accounting(self):
        alias = self.root.parent / (self.root.name + "-alias")
        absent = self.root / "absent-ledger"
        for target in (absent, self.root):
            with patch("content_runtime.linked_path", side_effect=lambda path: path == alias), \
                    patch.object(pathlib.Path, "resolve", return_value=target):
                with self.assertRaisesRegex(RuntimeError, "restore the original"):
                    canonical_default_root(alias)
        self.assertFalse(absent.exists())
        (self.root / "namespace-salt").write_bytes(b"partial")
        with patch("content_runtime.linked_path", side_effect=lambda path: path == alias), \
                patch.object(pathlib.Path, "resolve", return_value=self.root):
            with self.assertRaisesRegex(RuntimeError, "restore the original"):
                canonical_default_root(alias)

    def test_recovery_epoch_preserves_cap_and_fences_other_text(self):
        text = "New synthetic sentence."
        manifest = self.root / "authorization.json"
        policy = {"epoch_id": "fixture-new-speech", "maximum_credits": 7,
                  "historical_accounting": "UNKNOWN", "historical_requests": "FENCED",
                  "owner_authorization": "Synthetic explicit test authorization",
                  "workspace": "fixture", "allowed_text_sha256": [hashlib.sha256(text.encode()).hexdigest()]}
        manifest.write_text(json.dumps(policy))
        path_class = type(self.root)
        with patch.dict(os.environ, {"LOCALAPPDATA": str(self.root)}), \
                patch("content_runtime.running_on_windows", return_value=True), \
                patch("content_runtime.secure_directory", side_effect=lambda p: p.mkdir(parents=True, exist_ok=True)):
            # Avoid platform-dependent Path construction while still exercising
            # the Windows default-root environment selection.
            with patch("content_runtime.pathlib.Path", path_class):
                ledger = recovery_epoch_ledger(manifest, "fixture", text, "eleven_flash_v2_5")
                ledger.claim("fixture", "one", "elevenlabs/credits", 7)
                again = recovery_epoch_ledger(manifest, "fixture", text, "eleven_flash_v2_5")
                with self.assertRaisesRegex(RuntimeError, "ceiling"):
                    again.claim("fixture", "two", "elevenlabs/credits", 1)
                with self.assertRaisesRegex(RuntimeError, "allowlist"):
                    recovery_epoch_ledger(manifest, "fixture", "Old ambiguous sentence.", "eleven_flash_v2_5")
                policy["maximum_credits"] = 8
                manifest.write_text(json.dumps(policy))
                with self.assertRaisesRegex(RuntimeError, "immutable"):
                    recovery_epoch_ledger(manifest, "fixture", text, "eleven_flash_v2_5")

    def test_additional_batch_shares_cap_without_replacing_original_authorization(self):
        first, second = "First new fixture.", "Second new fixture."
        h = lambda s: hashlib.sha256(s.encode()).hexdigest()
        policy = {"epoch_id":"fixture-batch", "maximum_credits":7,
                  "historical_accounting":"UNKNOWN", "historical_requests":"FENCED",
                  "owner_authorization":"Fixture authorization", "workspace":"fixture",
                  "allowed_text_sha256":[h(first)]}
        manifest=self.root/'first.json'; manifest.write_text(json.dumps(policy))
        original_raw=manifest.read_bytes(); path_class=type(self.root)
        with patch.dict(os.environ,{"LOCALAPPDATA":str(self.root)}), \
                patch("content_runtime.running_on_windows",return_value=True), \
                patch("content_runtime.secure_directory",side_effect=lambda p:p.mkdir(parents=True,exist_ok=True)), \
                patch("content_runtime.pathlib.Path",path_class):
            first_ledger=recovery_epoch_ledger(manifest,"fixture",first,"eleven_flash_v2_5")
            first_ledger.claim("fixture-a","first","elevenlabs/credits",4)
            additional={**policy,"additional_batch_id":"second", "parent_authorization_sha256":hashlib.sha256(original_raw).hexdigest(),"allowed_text_sha256":[h(second)]}
            other=self.root/'second.json';other.write_text(json.dumps(additional))
            ledger=recovery_epoch_ledger(other,"fixture",second,"eleven_flash_v2_5")
            self.assertEqual(ledger.root,first_ledger.root)
            ledger.claim("fixture-b","second","elevenlabs/credits",3)
            with self.assertRaisesRegex(RuntimeError,"ceiling"):
                ledger.claim("fixture-b","third","elevenlabs/credits",1)
            self.assertEqual((ledger.root/'authorization.json').read_bytes(),original_raw)
            other.write_text(json.dumps({**additional,"additional_batch_id":"duplicate-other-batch"}))
            with self.assertRaisesRegex(RuntimeError,"overlaps"):
                recovery_epoch_ledger(other,"fixture",second,"eleven_flash_v2_5")
            other.write_text(json.dumps(additional))
            guard=ledger.root/'batch-registration.lock';guard.write_text("Interrupted fixture")
            with self.assertRaisesRegex(RuntimeError,"registration busy"):
                recovery_epoch_ledger(other,"fixture",second,"eleven_flash_v2_5")
            guard.unlink()
            for change in ({"maximum_credits":8},{"parent_authorization_sha256":"0"*64},{"allowed_text_sha256":[h(first)]}):
                other.write_text(json.dumps({**additional,**change}))
                with self.assertRaises(RuntimeError):recovery_epoch_ledger(other,"fixture",first if 'allowed_text_sha256' in change else second,"eleven_flash_v2_5")
            other.write_text(json.dumps({**additional,"owner_authorization":"Changed"}))
            with self.assertRaisesRegex(RuntimeError,"immutable"):
                recovery_epoch_ledger(other,"fixture",second,"eleven_flash_v2_5")

    def test_recovery_epoch_rejects_unsafe_policy_without_creating_state(self):
        text = "Fresh fixture."
        digest = hashlib.sha256(text.encode()).hexdigest()
        policy = {"epoch_id": "fixture", "maximum_credits": 8,
                  "historical_accounting": "UNKNOWN", "historical_requests": "FENCED",
                  "owner_authorization": "Fixture authorization", "workspace": "fixture",
                  "allowed_text_sha256": [digest]}
        manifest = self.root / "recovery-policy.json"
        variants = [{"maximum_credits":1001}, {"historical_accounting":"RESTORED"},
                    {"historical_requests":"RETRY"}, {"owner_authorization":""},
                    {"workspace":"other"}, {"ambiguous_text_sha256":[digest]}]
        with patch("content_runtime.secure_directory") as secure:
            for change in variants:
                manifest.write_text(json.dumps({**policy, **change}))
                with self.assertRaises(RuntimeError):
                    recovery_epoch_ledger(manifest, "fixture", text, "eleven_flash_v2_5")
            manifest.write_text(json.dumps(policy))
            with self.assertRaises(RuntimeError):
                recovery_epoch_ledger(manifest, "fixture", text, "eleven_v3")
            secure.assert_not_called()

    def test_invalid_manifest_shapes_fail_with_controlled_error(self):
        manifest = self.root / "bad.json"
        for value in ([], {"content": []}, {"content": {}}):
            manifest.write_text(json.dumps(value))
            with self.assertRaises((RuntimeError, ValueError)):
                accept_manifest(self.ledger, "account-a", "same", manifest)

    def project_fixture(self):
        text = "New complete synthetic interview story."
        digest = hashlib.sha256(text.encode()).hexdigest()
        request = {"voice_id":"fixture-professional-clone", "model_id":"eleven_flash_v2_5",
                   "output_format":"pcm_44100", "revision":"fixture-v3",
                   "payload":{"text":text,"pronunciation_dictionary_locators":[]}}
        proof = {"kind":"elevenlabs-new-input-inventory", "enumerated_scopes":["Synthetic fixture inventory"],
                 "new_text_sha256":[digest], "historical_text_sha256":[], "ambiguous_text_sha256":[]}
        inventory = self.root/'inventory.json'; inventory.write_text(json.dumps(proof))
        policy = {"kind":"elevenlabs-owner-authorized-project-epoch-v1", "epoch_id":"elevenlabs-project-fixture",
                  "maximum_credits":12000, "owner_authorized_maximum_credits":12000,
                  "owner_authorization":"Authorize 12,000 existing credits", "workspace":"fixture",
                  "historical_accounting":"UNKNOWN", "historical_requests":"FENCED",
                  "voice_id":request['voice_id'],"output_format":request['output_format'],
                  "request_revision":request['revision'],"pronunciation_locators_sha256":request_key([]),
                  "allowed_text_sha256":[digest],
                  "allowed_requests":[{"text_sha256":digest,"request_sha256":request_key(request)}],
                  "inventory_proof":{"path":str(inventory),"sha256":hashlib.sha256(inventory.read_bytes()).hexdigest()}}
        manifest=self.root/'project.json';manifest.write_text(json.dumps(policy))
        return text, request, proof, inventory, policy, manifest

    def test_project_epoch_preserves_aggregate_unknown_and_immutable_authority(self):
        text,request,proof,inventory,policy,manifest=self.project_fixture()
        original=manifest.read_bytes()
        with patch.dict(os.environ,{"LOCALAPPDATA":str(self.root)}), \
                patch("content_runtime.running_on_windows",return_value=True), \
                patch("content_runtime.secure_directory",side_effect=lambda p:p.mkdir(parents=True,exist_ok=True)):
            ledger=recovery_epoch_ledger(manifest,'fixture',text,'eleven_flash_v2_5',request=request)
            claim=ledger.claim('one','one','elevenlabs/credits',11000)
            ledger.submitted(claim);ledger.unknown(claim)
            again=recovery_epoch_ledger(manifest,'fixture',text,'eleven_flash_v2_5',request=request)
            again.claim('two','two','elevenlabs/credits',1000)
            with self.assertRaisesRegex(RuntimeError,'ceiling'):
                again.claim('three','three','elevenlabs/credits',1)
            self.assertEqual((ledger.root/'authorization.json').read_bytes(),original)
            policy['maximum_credits']=11999;manifest.write_text(json.dumps(policy))
            with self.assertRaisesRegex(RuntimeError,'immutable'):
                recovery_epoch_ledger(manifest,'fixture',text,'eleven_flash_v2_5',request=request)

    def test_project_epoch_rejects_changed_approval_request_and_limits_before_state(self):
        text,request,proof,inventory,policy,manifest=self.project_fixture()
        variants=[{'maximum_credits':12001},{'owner_authorized_maximum_credits':13000},
                  {'owner_authorization':'Inferred approval'}, {'voice_id':'other'},
                  {'output_format':'other'}, {'request_revision':'other'},
                  {'pronunciation_locators_sha256':request_key(['other'])},
                  {'allowed_requests':[]},{'additional_batch_id':'second'},
                  {'kind':'generic','maximum_credits':1001}]
        with patch('content_runtime.secure_directory') as secure:
            for variant in variants:
                manifest.write_text(json.dumps({**policy,**variant}))
                with self.assertRaises(RuntimeError):
                    recovery_epoch_ledger(manifest,'fixture',text,'eleven_flash_v2_5',request=request)
            manifest.write_text(json.dumps(policy))
            with self.assertRaises(RuntimeError):
                recovery_epoch_ledger(manifest,'fixture',text,'eleven_flash_v2_5',request={**request,'payload':{'text':text,'speed':1.1}})
            secure.assert_not_called()

    def test_project_epoch_fences_ambiguous_and_tampered_inventory(self):
        text,request,proof,inventory,policy,manifest=self.project_fixture()
        with patch('content_runtime.secure_directory') as secure:
            proof['ambiguous_text_sha256']=proof['new_text_sha256']
            inventory.write_text(json.dumps(proof))
            with self.assertRaisesRegex(RuntimeError,'inventory proof'):
                recovery_epoch_ledger(manifest,'fixture',text,'eleven_flash_v2_5',request=request)
            policy['inventory_proof']['sha256']=hashlib.sha256(inventory.read_bytes()).hexdigest()
            manifest.write_text(json.dumps(policy))
            with self.assertRaisesRegex(RuntimeError,'fence'):
                recovery_epoch_ledger(manifest,'fixture',text,'eleven_flash_v2_5',request=request)
            secure.assert_not_called()

    def correction_fixture(self):
        text, request, proof, inventory, policy, manifest = self.project_v2_fixture()
        corrected = json.loads(json.dumps(request))
        corrected['payload']['text'] = 'The corrected financial explanation.'
        corrected['payload']['voice_settings'].update(speed=.88, stability=.4, style=.15)
        entry = dict(text_sha256=hashlib.sha256(corrected['payload']['text'].encode()).hexdigest(),
                     request_sha256=request_key(corrected))
        amendment = dict(kind='elevenlabs-project-delivery-correction-v1',
                         parent_authorization=dict(path=str(manifest), sha256=hashlib.sha256(manifest.read_bytes()).hexdigest()),
                         owner_authorization='Approve 4,200 existing credits',
                         purpose='owner-requested-delivery-correction', amendment_id='correction-one',
                         model_id='eleven_multilingual_v2',
                         allowed_requests=[entry])
        amendment_path = self.root / 'correction.json'
        amendment_path.write_text(json.dumps(amendment))
        return text, request, manifest, corrected, amendment, amendment_path, proof, inventory

    def test_v4_delivery_correction_pins_model_and_preserves_original_accounting(self):
        text, request, manifest, corrected, amendment, path, _, _ = self.correction_fixture()
        corrected['model_id'] = corrected['payload']['model_id'] = 'eleven_v4'
        corrected['payload']['voice_settings'] = {'stability': .5, 'similarity_boost': .75, 'clone_strength': 0.0}
        amendment['model_id'] = 'eleven_v4'
        amendment['allowed_requests'][0]['request_sha256'] = request_key(corrected)
        path.write_text(json.dumps(amendment))
        with self.project_v2_environment():
            original = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            salt = (original.root / 'namespace-salt').read_bytes()
            ns = original.namespace('synthetic-v2-fixture', 'fixture')
            claim = original.claim(ns, 'held-preview', 'elevenlabs/credits', 270)
            original.submitted(claim); original.unknown(claim)
            ledger = recovery_epoch_ledger(path, 'fixture', corrected['payload']['text'], 'eleven_v4', request=corrected)
            self.assertEqual(ledger.root, original.root)
            self.assertEqual((ledger.root / 'namespace-salt').read_bytes(), salt)
            self.assertEqual(json.loads((ledger.root / 'authorization.json').read_bytes())['model_id'], 'eleven_multilingual_v2')
            ledger.claim(ns, request_key(corrected), 'elevenlabs/credits', 200)
            self.assertEqual(ledger.status()['budgets'][0]['committed'], 470)
            for model in ('eleven_v4_turbo', 'eleven_multilingual_v2'):
                drift = json.loads(json.dumps(corrected)); drift['model_id'] = model
                with self.subTest(model=model), self.assertRaises(RuntimeError):
                    recovery_epoch_ledger(path, 'fixture', drift['payload']['text'], model, request=drift)
            with self.assertRaisesRegex(RuntimeError, 'ceiling'):
                ledger.claim(ns, 'over-cap', 'elevenlabs/credits', 3731)

    def test_delivery_correction_same_ledger_history_cap_and_immutable_reopen(self):
        text, request, manifest, corrected, amendment, path, _, _ = self.correction_fixture()
        with self.project_v2_environment():
            ledger = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            protected = {name: (ledger.root / name).read_bytes() for name in ('authorization.json', 'namespace-salt')}
            ns = ledger.namespace('synthetic-v2-fixture', 'fixture')
            claim = ledger.claim(ns, 'historical-preview', 'elevenlabs/credits', 270)
            ledger.submitted(claim); ledger.unknown(claim)
            again = recovery_epoch_ledger(path, 'fixture', corrected['payload']['text'], corrected['model_id'], request=corrected)
            self.assertEqual(again.root, ledger.root)
            again.claim(ns, request_key(corrected), 'elevenlabs/credits', 153)
            again = recovery_epoch_ledger(path, 'fixture', corrected['payload']['text'], corrected['model_id'], request=corrected)
            self.assertEqual(again.status()['budgets'][0]['committed'], 423)
            self.assertEqual(again.lookup(ns, 'historical-preview')['state'], 'unknown')
            with self.assertRaisesRegex(RuntimeError, 'ceiling'):
                again.claim(ns, 'over', 'elevenlabs/credits', 3778)
            for name, value in protected.items(): self.assertEqual((ledger.root / name).read_bytes(), value)
            amendment['allowed_requests'][0]['request_sha256'] = 'f' * 64
            path.write_text(json.dumps(amendment))
            with self.assertRaises(RuntimeError):
                recovery_epoch_ledger(path, 'fixture', corrected['payload']['text'], corrected['model_id'], request=corrected)

    def test_delivery_correction_missing_parent_accounting_and_drift_denied(self):
        text, request, manifest, corrected, amendment, path, _, _ = self.correction_fixture()
        with self.project_v2_environment():
            with self.assertRaisesRegex(RuntimeError, 'never initialize'):
                recovery_epoch_ledger(path, 'fixture', corrected['payload']['text'], corrected['model_id'], request=corrected)
            ledger = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            for field, value in [('voice_id', 'wrong'), ('model_id', 'wrong'), ('revision', 'wrong'), ('output_format', 'wrong')]:
                changed = json.loads(json.dumps(corrected)); changed[field] = value
                with self.subTest(field=field), self.assertRaises(RuntimeError):
                    recovery_epoch_ledger(path, 'fixture', changed['payload']['text'], changed['model_id'], request=changed)
            for field, value in [('maximum_credits', 4201), ('owner_authorization', 'unapproved')]:
                changed = dict(amendment); changed[field] = value; path.write_text(json.dumps(changed))
                with self.subTest(field=field), self.assertRaises(RuntimeError):
                    recovery_epoch_ledger(path, 'fixture', corrected['payload']['text'], corrected['model_id'], request=corrected)
            path.write_text(json.dumps(amendment))
            (ledger.root / 'namespace-salt').unlink()
            with self.assertRaises(RuntimeError):
                recovery_epoch_ledger(path, 'fixture', corrected['payload']['text'], corrected['model_id'], request=corrected)
            self.assertFalse((ledger.root / 'namespace-salt').exists())

    def test_delivery_correction_intact_historical_and_ambiguous_fences(self):
        text, request, manifest, corrected, amendment, path, proof, inventory = self.correction_fixture()
        forbidden = ['Historical speech.', 'Ambiguous speech.']
        for field, value in zip(('historical_text_sha256', 'ambiguous_text_sha256'), forbidden):
            proof[field].append(hashlib.sha256(value.encode()).hexdigest())
        inventory.write_text(json.dumps(proof))
        policy = json.loads(manifest.read_bytes())
        policy['inventory_proof']['sha256'] = hashlib.sha256(inventory.read_bytes()).hexdigest()
        manifest.write_text(json.dumps(policy))
        amendment['parent_authorization']['sha256'] = hashlib.sha256(manifest.read_bytes()).hexdigest()
        with self.project_v2_environment():
            ledger = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            for value in forbidden:
                changed = json.loads(json.dumps(corrected)); changed['payload']['text'] = value
                amendment['allowed_requests'] = [dict(text_sha256=hashlib.sha256(value.encode()).hexdigest(), request_sha256=request_key(changed))]
                path.write_text(json.dumps(amendment))
                with self.subTest(value=value), self.assertRaisesRegex(RuntimeError, 'fence'):
                    recovery_epoch_ledger(path, 'fixture', value, changed['model_id'], request=changed)
            self.assertFalse((ledger.root / 'delivery-corrections').exists())

    def test_delivery_correction_rejects_fifth_and_duplicate_text(self):
        text, request, manifest, corrected, amendment, path, _, _ = self.correction_fixture()
        with self.project_v2_environment():
            ledger = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            for index in range(4):
                changed = json.loads(json.dumps(corrected)); changed['payload']['text'] += str(index)
                current = json.loads(json.dumps(amendment)); current['amendment_id'] = 'correction-' + str(index)
                current['allowed_requests'] = [dict(text_sha256=hashlib.sha256(changed['payload']['text'].encode()).hexdigest(), request_sha256=request_key(changed))]
                path.write_text(json.dumps(current))
                recovery_epoch_ledger(path, 'fixture', changed['payload']['text'], changed['model_id'], request=changed)
            path.write_text(json.dumps(amendment))
            with self.assertRaisesRegex(RuntimeError, 'four corrections'):
                recovery_epoch_ledger(path, 'fixture', corrected['payload']['text'], corrected['model_id'], request=corrected)
            duplicate = json.loads(json.dumps(amendment))
            duplicate['allowed_requests'] = [dict(text_sha256=hashlib.sha256(text.encode()).hexdigest(), request_sha256=request_key(request))]
            path.write_text(json.dumps(duplicate))
            with self.assertRaisesRegex(RuntimeError, 'overlaps'):
                recovery_epoch_ledger(path, 'fixture', text, request['model_id'], request=request)

    def project_v2_fixture(self):
        text, request, proof, inventory, policy, manifest = self.project_fixture()
        request['model_id'] = 'eleven_multilingual_v2'
        request['payload']['voice_settings'] = {'stability': 0.5, 'similarity_boost': 0.75}
        policy.update(kind='elevenlabs-owner-authorized-project-epoch-v2',
                      epoch_id='elevenlabs-project-v2-fixture', maximum_credits=4200,
                      owner_authorized_maximum_credits=4200,
                      owner_authorization='Approve 4,200 existing credits',
                      model_id=request['model_id'])
        policy['allowed_requests'][0]['request_sha256'] = request_key(request)
        manifest.write_text(json.dumps(policy))
        return text, request, proof, inventory, policy, manifest

    @contextlib.contextmanager
    def project_v2_environment(self):
        with patch.dict(os.environ, {'LOCALAPPDATA': str(self.root),
                                    'ELEVENLABS_API_KEY': 'synthetic-v2-fixture'}), \
             patch('content_runtime.running_on_windows', return_value=True), \
             patch('content_runtime.secure_directory', side_effect=lambda p: p.mkdir(parents=True, exist_ok=True)):
            yield

    def test_project_v2_reopen_preserves_authority_salt_and_aggregate_ceiling(self):
        text, request, _, _, _, manifest = self.project_v2_fixture()
        with self.project_v2_environment():
            ledger = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            original = (ledger.root / 'authorization.json').read_bytes()
            salt = (ledger.root / 'namespace-salt').read_bytes()
            namespace = ledger.namespace('synthetic-v2-fixture', 'fixture')
            claim = ledger.claim(namespace, 'one', 'elevenlabs/credits', 4000)
            ledger.submitted(claim)
            ledger.unknown(claim)
            again = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            again.claim(namespace, 'two', 'elevenlabs/credits', 200)
            with self.assertRaisesRegex(RuntimeError, 'ceiling'):
                again.claim(namespace, 'three', 'elevenlabs/credits', 1)
            self.assertEqual((ledger.root / 'authorization.json').read_bytes(), original)
            self.assertEqual((ledger.root / 'namespace-salt').read_bytes(), salt)
            self.assertEqual(again.lookup(namespace, 'one')['state'], 'unknown')
            self.assertEqual(again.status()['budgets'][0]['committed'], 4200)

    def test_project_v2_rejects_unapproved_authority_and_requests_before_state(self):
        text, request, _, _, policy, manifest = self.project_v2_fixture()
        variants = [{'maximum_credits': 4199}, {'maximum_credits': 4201},
                    {'owner_authorized_maximum_credits': 12000},
                    {'owner_authorization': 'Authorize 12,000 existing credits'},
                    {'model_id': 'eleven_flash_v2_5'}, {'workspace': 'other'},
                    {'voice_id': 'other'}, {'output_format': 'other'},
                    {'request_revision': 'other'}, {'additional_batch_id': 'second'},
                    {'historical_accounting': 'KNOWN'}, {'historical_requests': 'RETRY'},
                    {'pronunciation_locators_sha256': request_key(['other'])},
                    {'allowed_requests': []}]
        with patch('content_runtime.secure_directory') as secure:
            for variant in variants:
                with self.subTest(variant=variant):
                    manifest.write_text(json.dumps({**policy, **variant}))
                    with self.assertRaises(RuntimeError):
                        recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            manifest.write_text(json.dumps(policy))
            for changed in ({**request, 'model_id': 'eleven_flash_v2_5'},
                            {**request, 'voice_id': 'other'},
                            {**request, 'payload': {**request['payload'], 'voice_settings': {'stability': 0.9}}}):
                with self.assertRaises(RuntimeError):
                    recovery_epoch_ledger(manifest, 'fixture', text, changed['model_id'], request=changed)
            secure.assert_not_called()

    def test_project_v2_fences_historical_ambiguous_and_tampered_proof(self):
        text, request, proof, inventory, policy, manifest = self.project_v2_fixture()
        original_proof = json.dumps(proof)
        with patch('content_runtime.secure_directory') as secure:
            inventory.write_text('{}')
            with self.assertRaisesRegex(RuntimeError, 'inventory proof'):
                recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            for field in ('historical_text_sha256', 'ambiguous_text_sha256'):
                changed = {**json.loads(original_proof), field: proof['new_text_sha256']}
                inventory.write_text(json.dumps(changed))
                policy['inventory_proof']['sha256'] = hashlib.sha256(inventory.read_bytes()).hexdigest()
                manifest.write_text(json.dumps(policy))
                with self.assertRaisesRegex(RuntimeError, 'fence'):
                    recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            secure.assert_not_called()

    def test_project_v2_missing_accounting_never_recreates_originals(self):
        text, request, _, _, _, manifest = self.project_v2_fixture()
        with self.project_v2_environment():
            ledger = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            for name in ('ledger.sqlite3', 'namespace-salt', 'assets'):
                path = ledger.root / name
                saved = path.with_name(name + '.saved')
                path.rename(saved)
                try:
                    with patch('content_runtime.Ledger') as opened:
                        with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                            recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
                    opened.assert_not_called()
                    self.assertFalse(path.exists())
                finally:
                    saved.rename(path)
            with ledger.connect(True) as con:
                con.execute("DELETE FROM budgets WHERE bucket='elevenlabs/credits'")
            with patch('content_runtime.Ledger') as opened:
                with self.assertRaisesRegex(RuntimeError, 'budget missing'):
                    recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            opened.assert_not_called()
            with ledger.connect() as con:
                self.assertIsNone(con.execute("SELECT ceiling FROM budgets WHERE bucket='elevenlabs/credits'").fetchone())

    def test_project_v2_orphan_root_and_changed_authorization_fail_closed(self):
        text, request, _, _, policy, manifest = self.project_v2_fixture()
        epoch_root = self.root / 'AgentHub/runtime/content-recovery-epochs' / policy['epoch_id']
        epoch_root.mkdir(parents=True)
        with self.project_v2_environment():
            with self.assertRaisesRegex(RuntimeError, 'initialization incomplete'):
                recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            self.assertEqual(list(epoch_root.iterdir()), [])
            epoch_root.rmdir()
            ledger = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            original = (ledger.root / 'authorization.json').read_bytes()
            policy['owner_note'] = 'Changed bytes remain unauthorized'
            manifest.write_text(json.dumps(policy))
            with self.assertRaisesRegex(RuntimeError, 'immutable'):
                recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            self.assertEqual((ledger.root / 'authorization.json').read_bytes(), original)

    def test_project_v2_damaged_schema_salt_and_missing_credential_fail_closed(self):
        text, request, _, _, _, manifest = self.project_v2_fixture()
        with self.project_v2_environment():
            with patch.dict(os.environ, {'ELEVENLABS_API_KEY': ''}):
                with patch('content_runtime.secure_directory') as secure:
                    with self.assertRaisesRegex(RuntimeError, 'credential'):
                        recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
                    secure.assert_not_called()
            ledger = recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
            salt_path = ledger.root / 'namespace-salt'
            salt = salt_path.read_bytes()
            salt_path.write_bytes(salt[:16])
            with patch('content_runtime.Ledger') as opened:
                with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                    recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
                opened.assert_not_called()
            self.assertEqual(salt_path.read_bytes(), salt[:16])
            salt_path.write_bytes(salt)
            with ledger.connect(True) as con:
                con.execute('DROP TABLE requests')
            with patch('content_runtime.Ledger') as opened:
                with self.assertRaises(sqlite3.OperationalError):
                    recovery_epoch_ledger(manifest, 'fixture', text, request['model_id'], request=request)
                opened.assert_not_called()
            with ledger.connect() as con:
                self.assertIsNone(con.execute("SELECT name FROM sqlite_master WHERE name='requests'").fetchone())

    def test_v1_and_generic_epochs_remain_flash_only(self):
        text, request, _, _, policy, manifest = self.project_fixture()
        with patch('content_runtime.secure_directory') as secure:
            for kind, ceiling in (('elevenlabs-owner-authorized-project-epoch-v1', 12000), ('generic', 1000)):
                changed = {**request, 'model_id': 'eleven_multilingual_v2'}
                changed_policy = {**policy, 'kind': kind, 'maximum_credits': ceiling,
                                  'model_id': changed['model_id'],
                                  'allowed_requests': [{'text_sha256': policy['allowed_text_sha256'][0],
                                                        'request_sha256': request_key(changed)}]}
                manifest.write_text(json.dumps(changed_policy))
                with self.assertRaises(RuntimeError):
                    recovery_epoch_ledger(manifest, 'fixture', text, changed['model_id'], request=changed)
            secure.assert_not_called()

    def test_unknown_billing_retains_reservation_and_acceptance_requires_gates(self):
        claim = self.claim()
        result = self.finish(claim)
        self.assertEqual(result["state"], "pending")
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 4)
        self.assertEqual(self.claim()["state"], "pending")
        with self.assertRaisesRegex(RuntimeError, "gate"):
            self.ledger.accept("account-a", "same", {})
        gates = {name: {"pass": True, "output_sha256": result["sha256"], "evidence_sha256": "a" * 64}
                 for name in ("identity", "content", "pronunciation", "listening", "artifact")}
        accepted = self.ledger.accept("account-a", "same", gates)
        self.assertEqual(accepted["state"], "accepted")
        self.assertEqual(self.ledger.read_asset(self.claim()), b"exact fixture bytes")

    def gate_set(self, sha, names):
        return {name: {"pass": True, "output_sha256": sha, "evidence_sha256": "a" * 64} for name in names}

    def test_speaker_identity_is_advisory_and_never_blocks_acceptance(self):
        # Owner direction 2026-10-27: "identity is advisory only; never fail, block or re-voice on speaker similarity".
        claim = self.claim()
        with self.ledger.connect() as con:
            self.assertNotIn("identity", con.execute("SELECT gates FROM requests WHERE key='same'").fetchone()[0])
        result = self.finish(claim)
        real = ("content", "pronunciation", "listening", "artifact")
        self.assertNotIn("identity", real)
        # no identity entry at all
        accepted = self.ledger.accept("account-a", "same", self.gate_set(result["sha256"], real))
        self.assertEqual(accepted["state"], "accepted")
        # a failing, malformed or mismatched identity entry is carried along and ignored
        for identity in ({"pass": False}, {"pass": False, "output_sha256": "0" * 64}, "not even an object", {}):
            gates = {**self.gate_set(result["sha256"], real), "identity": identity}
            self.assertEqual(self.ledger.accept("account-a", "same", gates)["state"], "accepted")
        # the real gates still block
        missing = self.gate_set(result["sha256"], ("content", "pronunciation", "artifact"))
        with self.assertRaisesRegex(RuntimeError, "listening"):
            self.ledger.accept("account-a", "same", {**missing, "identity": {"pass": True}})

    def test_identity_is_not_a_required_gate_of_a_new_or_legacy_claim(self):
        from content_runtime import ADVISORY_GATES, VOICE_GATES
        self.assertIn("identity", ADVISORY_GATES)
        self.assertNotIn("identity", VOICE_GATES)
        legacy = self.ledger.claim("account-a", "legacy", "fixture/credits", 1, 1,
                                   required_gates=("identity", "content", "pronunciation", "listening", "artifact"))
        with self.ledger.connect() as con:
            stored = json.loads(con.execute("SELECT gates FROM requests WHERE key='legacy'").fetchone()[0])
        self.assertNotIn("identity", stored)
        # a row written before the change still lists identity: a default claim must not report a policy change
        with self.ledger.connect(True) as con:
            con.execute("UPDATE requests SET gates=? WHERE key='legacy'",
                        (json.dumps(["artifact", "content", "identity", "listening", "pronunciation"]),))
        again = self.ledger.claim("account-a", "legacy", "fixture/credits", 1, 1)
        self.assertEqual(again["key"], "legacy")
        self.assertEqual(legacy["key"], "legacy")
        done = self.finish(legacy)
        legacy_gates = self.gate_set(done["sha256"], ("content", "pronunciation", "listening", "artifact"))
        self.assertEqual(self.ledger.accept("account-a", "legacy", legacy_gates)["state"], "accepted")

    def test_manifest_identity_entry_is_never_verified(self):
        row = self.finish(self.claim(), 1)
        evidence = self.root / "qa.json"
        evidence.write_text('{"synthetic_review":true}')
        real = {name: {"pass": True, "output_sha256": row["sha256"],
                       "evidence_sha256": hashlib.sha256(evidence.read_bytes()).hexdigest(),
                       "evidence_path": str(evidence), "reviewer": "synthetic-fixture"}
                for name in ("content", "pronunciation", "listening", "artifact")}
        # identity evidence is missing, relative and hash-mismatched: none of that may reject the acceptance
        manifest = self.root / "gates-with-bad-identity.json"
        manifest.write_text(json.dumps({**real, "identity": {"pass": False, "evidence_path": "relative.json",
                                                              "evidence_sha256": "0" * 64}}))
        accept_manifest(self.ledger, "account-a", "same", manifest)
        self.assertEqual(self.claim()["state"], "accepted")

    def test_settlement_is_idempotent_and_never_resets_spent(self):
        self.finish(self.claim(), 2)
        self.ledger.settle("account-a", "same", 2, "receipt-1")
        self.ledger.configure("fixture/credits", 10)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 2)
        with self.assertRaisesRegex(RuntimeError, "settled"):
            self.ledger.settle("account-a", "same", 1, "receipt-1")
        with self.assertRaisesRegex(RuntimeError, "ceiling"):
            self.ledger.configure("fixture/credits", 1)

    def test_lease_takeover_before_submission_fences_old_worker(self):
        original = self.claim(lease=.02)
        time.sleep(.04)
        replacement = self.claim()
        self.assertEqual(replacement["state"], "leader")
        with self.assertRaisesRegex(RuntimeError, "lease"):
            self.ledger.submitted(original)
        self.finish(replacement, 3)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 3)

    def test_takeover_cannot_increase_reservation_or_replace_bound_receipt(self):
        original = self.claim(lease=.02)
        time.sleep(.04)
        replacement = self.claim(maximum=9)
        self.assertEqual(replacement["maximum"], 4)
        self.ledger.submitted(replacement)
        self.ledger.bind_receipt(replacement, "original-receipt")
        self.ledger.unknown(replacement, "wrong-receipt")
        row = self.ledger.lookup("account-a", "same")
        self.assertEqual(row["receipt"], "original-receipt")
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 4)

    def test_submitted_crash_never_retries_and_can_recover_existing_bytes(self):
        claim = self.claim(lease=.3)
        self.ledger.submitted(claim)
        time.sleep(.4)
        restarted = Ledger(self.root)
        self.assertEqual(restarted.claim("account-a", "same", "fixture/credits", 4)["state"], "unknown")
        self.assertEqual(restarted.status()["budgets"][0]["committed"], 4)
        recovered = restarted.recover("account-a", "same", b"recovered fixture", "audio/fixture", "receipt-1", 2)
        self.assertEqual(recovered["state"], "pending")
        self.assertEqual(restarted.status()["budgets"][0]["committed"], 2)

    def test_namespace_isolation_and_full_key_invalidation(self):
        self.finish(self.claim(), 1)
        self.assertEqual(self.claim(namespace="account-b")["state"], "leader")
        request = {"provider": "fixture", "model": "m1", "voice": "v1", "settings": {},
                   "context": "before", "dictionary": "d:v1", "format": "wav", "scope": "task1"}
        original = request_key(request)
        for field in request:
            self.assertNotEqual(original, request_key({**request, field: "changed"}))
        self.assertEqual(original, request_key(dict(reversed(list(request.items())))))

    def test_tampered_asset_never_becomes_cache_hit(self):
        result = self.finish(self.claim(), 1)
        (self.root / "assets" / result["sha256"]).write_bytes(b"tampered")
        with self.assertRaisesRegex(RuntimeError, "hash"):
            self.ledger.read_asset(self.claim())

    def test_overrun_freezes_future_reservations(self):
        self.finish(self.claim(), 12)
        with self.assertRaisesRegex(RuntimeError, "ceiling"):
            self.claim("different", 1)

    def test_completion_cannot_replace_bound_receipt(self):
        claim = self.claim()
        self.ledger.submitted(claim)
        self.ledger.bind_receipt(claim, "original")
        with self.assertRaisesRegex(RuntimeError, "Completion"):
            self.ledger.complete(claim, b"fixture", "audio/fixture", "different", 1)
        self.assertEqual(self.ledger.lookup("account-a", "same")["receipt"], "original")

    def test_acceptance_checks_evidence_files_and_preserves_exact_accepted_bytes(self):
        row = self.finish(self.claim(), 1)
        evidence = self.root / "qa.json"
        evidence.write_text('{"synthetic_review":true}')
        gates = {name: {"pass": True, "output_sha256": row["sha256"],
                       "evidence_sha256": hashlib.sha256(evidence.read_bytes()).hexdigest(),
                       "evidence_path": str(evidence), "reviewer": "synthetic-fixture"}
                 for name in ("identity", "content", "pronunciation", "listening", "artifact")}
        manifest = self.root / "gates.json"
        manifest.write_text(json.dumps(gates))
        accept_manifest(self.ledger, "account-a", "same", manifest)
        self.assertEqual(self.claim()["state"], "accepted")
        self.assertEqual(self.ledger.read_asset(self.claim()), b"exact fixture bytes")
        evidence.write_text("changed evidence")
        with self.assertRaisesRegex(RuntimeError, "hash mismatch"):
            accept_manifest(self.ledger, "account-a", "same", manifest)

    def workers(self, mode, count):
        children = [subprocess.Popen([sys.executable, __file__, "worker", str(self.root), mode, str(i)],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0)) for i in range(count)]
        results = []
        for child in children:
            out, err = child.communicate(timeout=25)
            self.assertEqual(child.returncode, 0, err)
            results.append(json.loads(out))
        return results

    def test_separate_process_identical_request_calls_upstream_once(self):
        results = self.workers("same", 8)
        calls = list(self.root.glob("upstream-*.call"))
        self.assertEqual(len(calls), 1)
        self.assertEqual(len({result["sha256"] for result in results}), 1)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 3)

    def test_separate_process_distinct_request_budget_race(self):
        results = self.workers("different", 8)
        self.assertEqual(sum(result["ok"] for result in results), 2)
        self.assertEqual(len(list(self.root.glob("upstream-*.call"))), 2)
        self.assertEqual(self.ledger.status()["budgets"][0]["committed"], 8)


def worker(root, mode, number):
    ledger = Ledger(pathlib.Path(root))
    key = "same" if mode == "same" else number
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        try:
            claim = ledger.claim("account-a", key, "fixture/credits", 4)
        except RuntimeError:
            print(json.dumps({"ok": False}))
            return
        if claim["state"] == "leader":
            ledger.submitted(claim)
            (pathlib.Path(root) / f"upstream-{number}.call").write_text("synthetic")
            time.sleep(.15)
            result = ledger.complete(claim, b"exact fixture bytes", "audio/fixture", "receipt-" + number,
                                     3 if mode == "same" else 4)
            print(json.dumps({"ok": True, "sha256": result["sha256"]}))
            return
        if claim["state"] in ("pending", "accepted"):
            raw = ledger.read_asset(claim)
            print(json.dumps({"ok": True, "sha256": hashlib.sha256(raw).hexdigest()}))
            return
        time.sleep(.025)
    raise RuntimeError("fixture timed out")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "worker":
        worker(*sys.argv[2:])
    else:
        unittest.main()
