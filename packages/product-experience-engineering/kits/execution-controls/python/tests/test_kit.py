"""Runs the shared vectors against the Python implementation.

The TypeScript tests run the same files, so a disagreement between languages
fails one side or the other.
"""

from __future__ import annotations

import contextlib
import copy
import json
import sys
import threading
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from execution_controls import (  # noqa: E402
    ApprovalPolicy,
    CanonicalJsonError,
    Principal,
    canonical_hash,
    canonical_json,
    compare_replay,
    create_proposal,
    create_receipt,
    decide,
    receipt_span,
    verify_chain,
    verify_proposal,
    verify_receipt,
)
from execution_controls.adversarial_suite import arun_adversarial_suite, run_adversarial_suite  # noqa: E402

VECTORS = HERE.parent.parent / "vectors"


def load(name: str):
    return json.loads((VECTORS / name).read_text(encoding="utf-8"))


def merge(base, patch):
    """Objects merge recursively, arrays and scalars replace, null deletes."""
    if patch is None:
        return base
    if not isinstance(patch, dict):
        return patch
    out = dict(base) if isinstance(base, dict) else {}
    for key, value in patch.items():
        if value is None:
            out.pop(key, None)
        else:
            out[key] = merge(out.get(key), value)
    return out


def substitute(value, proposal_hash):
    if value == "$proposalHash":
        return proposal_hash
    if isinstance(value, list):
        return [substitute(item, proposal_hash) for item in value]
    if isinstance(value, dict):
        return {key: substitute(item, proposal_hash) for key, item in value.items()}
    return value


def run_case(vectors, case):
    base = vectors["base"]
    proposal = create_proposal(merge(base["proposalInput"], case.get("proposalInput")))
    stored = merge(proposal, case.get("storedProposalPatch"))
    policy = ApprovalPolicy.from_json(merge(base["policy"], case.get("policy")))
    current_revision = case.get("currentRevision", base["currentRevision"])
    now = case.get("now", base["now"])
    prior_decisions = []
    for prior in case.get("priorRequests", []):
        earlier = decide(
            proposal=proposal,
            request=substitute(merge(base["request"], prior.get("request")), proposal["proposalHash"]),
            principal=Principal.from_json(merge(base["principal"], prior.get("principal"))),
            current_revision=base["currentRevision"],
            prior_decisions=list(prior_decisions),
            policy=policy,
            now=base["now"],
        )
        assert earlier.outcome in ("apply", "reject"), (case["name"], earlier)
        prior_decisions.append(earlier.record)
    return decide(
        proposal=stored,
        request=substitute(merge(base["request"], case.get("request")), proposal["proposalHash"]),
        principal=Principal.from_json(merge(base["principal"], case.get("principal"))),
        current_revision=current_revision,
        prior_decisions=prior_decisions,
        policy=policy,
        now=now,
    )


class CanonicalJsonVectors(unittest.TestCase):
    def test_vectors(self):
        for case in load("canonical-json.json")["cases"]:
            with self.subTest(case["name"]):
                if "error" in case:
                    with self.assertRaisesRegex(CanonicalJsonError, case["error"]):
                        canonical_json(case["input"])
                    continue
                self.assertEqual(canonical_json(case["input"]), case["canonical"])
                if "hash" in case:
                    self.assertEqual(canonical_hash(case["input"]), case["hash"])

    def test_refusals(self):
        for bad in ({"s": "\ud800"}, {"n": float("nan")}, {1: "x"}, {"d": object()}):
            with self.subTest(repr(bad)), self.assertRaises(CanonicalJsonError):
                canonical_json(bad)
        self.assertEqual(canonical_json([True, False, None, 3.0]), "[true,false,null,3]")


class ApprovalVectors(unittest.TestCase):
    vectors = load("approval-cases.json")

    def test_base_proposal_hash_matches_typescript(self):
        proposal = create_proposal(self.vectors["base"]["proposalInput"])
        self.assertEqual(proposal["proposalHash"], self.vectors["expectedBaseProposalHash"])
        self.assertTrue(verify_proposal(proposal))

    def test_cases(self):
        for case in self.vectors["cases"]:
            with self.subTest(case["name"]):
                result = run_case(self.vectors, case)
                expect = case["expect"]
                self.assertEqual(result.outcome, expect["outcome"], result)
                self.assertEqual(result.status, expect["status"])
                self.assertEqual(result.audit["outcome"], expect["audit"])
                self.assertEqual(result.audit["status"], expect["status"])
                self.assertEqual(result.code, expect.get("code"))
                self.assertEqual(result.audit["code"], expect.get("code"))
                if "recordKey" in expect:
                    self.assertEqual(result.record["idempotencyKey"], expect["recordKey"])

    def test_cross_tenant_audit_row_does_not_describe_the_proposal(self):
        audit = run_case(self.vectors, {"name": "x", "principal": {"tenantId": "tenant-other"}}).audit
        self.assertEqual(audit["tenantId"], "tenant-other")
        for key in ("capsuleId", "action", "subjectType", "subjectId", "subjectRevision", "proposalHash"):
            self.assertIsNone(audit[key], key)

    def test_payload_nulls_are_hashed_not_dropped(self):
        proposal = create_proposal(merge(self.vectors["base"]["proposalInput"], {"payload": {"owner": "x"}}))
        proposal["payload"]["owner"] = None
        self.assertFalse(verify_proposal(proposal))


class ReceiptVectors(unittest.TestCase):
    vectors = load("receipts.json")

    def chain(self):
        receipts = []
        for receipt_input in copy.deepcopy(self.vectors["chain"]):
            receipts.append(create_receipt(receipt_input, receipts[-1] if receipts else None))
        return receipts

    def test_pinned_hashes_match_typescript(self):
        for index, receipt in enumerate(self.chain()):
            expected = self.vectors["expected"][index]
            with self.subTest(index):
                self.assertEqual(receipt["receiptHash"], expected["receiptHash"])
                self.assertEqual(receipt["replayKey"], expected["replayKey"])
                self.assertEqual(receipt.get("retrievalHash"), expected["retrievalHash"])
                self.assertTrue(verify_receipt(receipt))
        self.assertEqual(verify_chain(self.chain()), {"ok": True, "brokenAt": -1})

    def test_tamper_and_relink(self):
        tampered = self.chain()
        tampered[1]["outcome"]["outputHash"] = "sha256:" + "f" * 64
        self.assertEqual(verify_chain(tampered), {"ok": False, "brokenAt": 1, "reason": "receipt_hash"})
        relinked = self.chain()
        del relinked[1]
        self.assertEqual(verify_chain(relinked), {"ok": False, "brokenAt": 1, "reason": "chain_link"})

    def test_replay(self):
        original = self.chain()[0]
        replay = create_receipt({**self.vectors["chain"][0], "receiptId": "rcpt-replay", "occurredAt": "2026-10-15T09:00:00Z"})
        self.assertEqual(compare_replay(original, replay), {"sameStep": True, "sameOutput": True})

    def test_span_mapping_matches_typescript(self):
        for index, receipt in enumerate(self.chain()):
            expected = self.vectors["expected"][index]
            with self.subTest(index):
                span = receipt_span(receipt)
                self.assertEqual(span["name"], expected["spanName"])
                self.assertEqual(span["attributes"], expected["spanAttributes"])
                self.assertLessEqual(span["startTimeMs"], span["endTimeMs"])


class InMemoryProduct:
    """A tiny product used to prove the adversarial suite can both pass and fail."""

    proposer_is_user = True
    supports_concurrency = True

    PRINCIPALS = {
        "approver": ("u-approver", "t1", ["reviewer"]),
        "second_approver": ("u-approver-2", "t1", ["reviewer"]),
        "proposer": ("u-proposer", "t1", ["reviewer"]),
        "viewer": ("u-viewer", "t1", ["viewer"]),
        "other_tenant": ("u-other", "t2", ["reviewer"]),
    }

    def __init__(self, *, trust_body_actor=False, lock=True):
        self.trust_body_actor = trust_body_actor
        self.lock = threading.Lock() if lock else None

    def setup(self):
        ctx = {"revision": 3, "applied": 0, "audit": [], "decisions": []}
        ctx["proposal"] = create_proposal(
            {
                "capsuleId": "cap-1",
                "tenantId": "t1",
                "subject": {"type": "task", "id": "task-1", "revision": 3},
                "action": "task.approve",
                "payload": {"status": "approved"},
                "proposedBy": {"kind": "user", "id": "u-proposer"},
                "createdAt": "2026-10-14T00:00:00Z",
            }
        )
        return ctx

    def proposal(self, ctx):
        return ctx["proposal"]

    def decide(self, ctx, *, actor, proposal_hash, decision, idempotency_key, claimed_actor_id=None):
        user, tenant, roles = self.PRINCIPALS[actor]
        if self.trust_body_actor and claimed_actor_id:
            user, claimed_actor_id = claimed_actor_id, None
        with self.lock or contextlib.nullcontext():
            result = decide(
                proposal=ctx["proposal"],
                request={
                    "proposalHash": proposal_hash,
                    "decision": decision,
                    "idempotencyKey": idempotency_key,
                    "claimedActorId": claimed_actor_id,
                },
                principal=Principal(user, tenant, roles),
                current_revision=ctx["revision"],
                prior_decisions=ctx["decisions"],
                policy=ApprovalPolicy(approver_roles=["reviewer"]),
                now="2026-10-14T01:00:00Z",
            )
            ctx["audit"].append((result.audit["outcome"], result.audit["code"]))
            if result.outcome in ("apply", "reject"):
                ctx["decisions"].append(result.record)
            if result.outcome == "apply":
                ctx["applied"] += 1
                ctx["revision"] += 1
        if result.outcome == "refuse":
            return result.status, result.error_body()
        return 200, {"decision": result.record}

    def change_subject(self, ctx):
        ctx["revision"] += 1

    def tamper_stored_proposal(self, ctx):
        ctx["proposal"] = copy.deepcopy(ctx["proposal"])
        ctx["proposal"]["payload"]["status"] = "rejected"

    def side_effects(self, ctx):
        return ctx["applied"]

    def audit_outcomes(self, ctx):
        return ctx["audit"]


class AdversarialSuite(unittest.TestCase):
    def test_correct_wiring_passes_every_case(self):
        results = run_adversarial_suite(InMemoryProduct())
        self.assertEqual([r for r in results if not r.passed], [])
        self.assertEqual(len(results), 14)

    def test_optional_cases_follow_the_adapter(self):
        product = InMemoryProduct()
        product.has_viewer = False
        product.proposer_is_user = False
        names = {r.name for r in run_adversarial_suite(product)}
        self.assertNotIn("viewer_is_refused", names)
        self.assertNotIn("self_approval_is_refused", names)
        self.assertEqual(len(names), 12)

    def test_async_adapter_runs_concurrently_and_passes(self):
        import asyncio

        class AsyncProduct(InMemoryProduct):
            async def decide(self, ctx, **kwargs):
                await asyncio.sleep(0)
                return InMemoryProduct.decide(self, ctx, **kwargs)

        results = asyncio.run(arun_adversarial_suite(AsyncProduct()))
        self.assertEqual([r for r in results if not r.passed], [])

    def test_missing_lock_is_caught_by_the_concurrency_case(self):
        import time

        class Racy(InMemoryProduct):
            """Reads prior decisions, pauses, then writes: no lock between read and write."""

            def decide(self, ctx, *, actor, proposal_hash, decision, idempotency_key, claimed_actor_id=None):
                user, tenant, roles = self.PRINCIPALS[actor]
                prior = list(ctx["decisions"])
                revision = ctx["revision"]
                time.sleep(0.05)
                result = decide(
                    proposal=ctx["proposal"],
                    request={"proposalHash": proposal_hash, "decision": decision,
                             "idempotencyKey": idempotency_key, "claimedActorId": claimed_actor_id},
                    principal=Principal(user, tenant, roles),
                    current_revision=revision,
                    prior_decisions=prior,
                    policy=ApprovalPolicy(approver_roles=["reviewer"]),
                    now="2026-10-14T01:00:00Z",
                )
                ctx["audit"].append((result.audit["outcome"], result.audit["code"]))
                if result.outcome == "apply":
                    ctx["decisions"].append(result.record)
                    ctx["applied"] += 1
                return (result.status, result.error_body()) if result.outcome == "refuse" else (200, {})

        failed = {r.name for r in run_adversarial_suite(Racy()) if not r.passed}
        self.assertIn("concurrent_approvals_apply_once", failed)

    def test_trusting_the_body_actor_is_caught(self):
        failed = {r.name for r in run_adversarial_suite(InMemoryProduct(trust_body_actor=True)) if not r.passed}
        self.assertIn("forged_actor_is_refused", failed)


if __name__ == "__main__":
    unittest.main()
