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
    KIT_VERSION,
    ApprovalPolicy,
    CanonicalJsonError,
    Principal,
    canonical_hash,
    canonical_json,
    compare_replay,
    create_proposal,
    create_receipt,
    decide,
    proposal_hash_of,
    receipt_span,
    request_hash_of,
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


BASE_INPUT = load("approval-cases.json")["base"]["proposalInput"]
BASE_PRINCIPAL = load("approval-cases.json")["base"]["principal"]
BASE_POLICY = ApprovalPolicy.from_json(load("approval-cases.json")["base"]["policy"])
NO_EXPIRY_HASH = "sha256:9bb74b5cfa1d2995ac7d78ca37ba9131abec1de36558e1dd2f2ef158fed3438c"
RECEIPT_MIN = {
    "receiptId": "rcpt-x", "tenantId": "t1", "occurredAt": "2026-10-14T15:00:00Z", "kind": "retrieval", "engine": "rules",
    "input": {"hash": "sha256:" + "a" * 64}, "outcome": {"status": "succeeded"},
}
MIN_RECEIPT_HASH = "sha256:333426c67398ac6b6f620e127171a5d962a5788fea2260426c4872fcecc5245b"
MIN_REPLAY_KEY = "sha256:0d5edfdd1c40ba44d6e6bdc84b543b0c1504792101dec69731eb01ed868c1947"
EMPTY_RETRIEVAL_RECEIPT_HASH = "sha256:ca17d88c30195d798040ee4ac5443f50c36c0b68a315ae014d73358a8e321197"


def stored_with(**patch):
    """What an older writer could have stored: a valid hash over whatever it held."""
    body = {**create_proposal(BASE_INPUT), **patch}
    body.pop("proposalHash")
    return {**body, "proposalHash": proposal_hash_of(body)}


def approve_at(proposal, now, decision="approve", **request):
    return decide(
        proposal=proposal,
        request={"proposalHash": proposal["proposalHash"], "decision": decision, "idempotencyKey": "k", **request},
        principal=Principal.from_json(BASE_PRINCIPAL),
        current_revision=7,
        prior_decisions=[],
        policy=BASE_POLICY,
        now=now,
    )


class Fixes110(unittest.TestCase):
    base_now = load("approval-cases.json")["base"]["now"]

    def test_expiry_fails_closed_on_unparseable_expires_at(self):
        for expires_at in ("garbage", "2026-10-15T15:00:00", "2026-10-15T15:00:00+00:00", "2026-02-30T00:00:00Z", "2026-10-15", ""):
            with self.subTest(expires_at):
                result = approve_at(stored_with(expiresAt=expires_at), self.base_now)
                self.assertEqual((result.outcome, result.code), ("refuse", "proposal_expired"))

    def test_expiry_fails_closed_on_unparseable_now(self):
        proposal = create_proposal(BASE_INPUT)
        for now in ("garbage", "2026-10-14T16:00:00", "2026-10-14T16:00:00+00:00", ""):
            with self.subTest(now):
                result = approve_at(proposal, now)
                self.assertEqual((result.outcome, result.code), ("refuse", "proposal_expired"))
        no_expiry = {k: v for k, v in BASE_INPUT.items() if k != "expiresAt"}
        self.assertEqual(approve_at(create_proposal(no_expiry), "garbage").code, "proposal_expired")

    def test_reject_is_still_allowed_when_timestamps_cannot_be_parsed(self):
        self.assertEqual(approve_at(stored_with(expiresAt="garbage"), "garbage", "reject").outcome, "reject")

    def test_fractional_seconds_in_a_z_timestamp_are_accepted(self):
        self.assertEqual(approve_at(stored_with(expiresAt="2026-10-15T15:00:00.500Z"), self.base_now).outcome, "apply")

    def test_sub_millisecond_expiry_compares_like_typescript(self):
        # TypeScript floors to whole milliseconds, so 0.0005 s and 0.0001 s are the same instant there.
        proposal = stored_with(expiresAt="2026-10-14T16:00:00.0005Z")
        self.assertEqual(approve_at(proposal, "2026-10-14T16:00:00.0001Z").code, "proposal_expired")

    def test_create_proposal_rejects_bad_timestamps(self):
        for patch in (
            {"createdAt": "garbage"}, {"createdAt": "2026-10-14T15:00:00"}, {"createdAt": "2026-10-14T15:00:00+00:00"},
            {"expiresAt": "tomorrow"}, {"expiresAt": "2026-10-15T15:00:00+02:00"}, {"expiresAt": "2026-13-01T00:00:00Z"},
            {"createdAt": 5},
        ):
            with self.subTest(patch), self.assertRaises(ValueError):
                create_proposal({**BASE_INPUT, **patch})

    def test_chain_head_is_anchored(self):
        chain = ReceiptVectors().chain()
        forged_head = create_receipt(load("receipts.json")["chain"][0], {"receiptHash": "sha256:" + "1" * 64})
        self.assertTrue(verify_receipt(forged_head))
        self.assertEqual(verify_chain([forged_head]), {"ok": False, "brokenAt": 0, "reason": "chain_link"})
        self.assertEqual(verify_chain(chain[1:]), {"ok": False, "brokenAt": 0, "reason": "chain_link"})

    def test_chain_slice_verifies_from_its_known_head(self):
        chain = ReceiptVectors().chain()
        self.assertEqual(verify_chain(chain[1:], chain[0]["receiptHash"]), {"ok": True, "brokenAt": -1})
        self.assertEqual(verify_chain(chain, None), {"ok": True, "brokenAt": -1})
        self.assertEqual(verify_chain(chain[1:], "sha256:" + "2" * 64), {"ok": False, "brokenAt": 0, "reason": "chain_link"})

    def test_null_expires_at_hashes_like_absent_same_literal_as_typescript(self):
        rest = {k: v for k, v in BASE_INPUT.items() if k != "expiresAt"}
        self.assertEqual(create_proposal({**rest, "expiresAt": None})["proposalHash"], NO_EXPIRY_HASH)
        self.assertEqual(create_proposal(rest)["proposalHash"], NO_EXPIRY_HASH)

    def test_reloaded_proposal_with_null_expires_at_still_verifies(self):
        rest = {k: v for k, v in BASE_INPUT.items() if k != "expiresAt"}
        reloaded = {**create_proposal(rest), "expiresAt": None}
        self.assertTrue(verify_proposal(reloaded))
        self.assertEqual(approve_at(reloaded, "2030-01-01T00:00:00Z").outcome, "apply")

    def test_null_reason_and_claimed_actor_are_absent(self):
        digest = "sha256:" + "a" * 64
        self.assertEqual(
            request_hash_of({"proposalHash": digest, "decision": "approve", "reason": None}, "u1"),
            request_hash_of({"proposalHash": digest, "decision": "approve"}, "u1"),
        )
        result = approve_at(create_proposal(BASE_INPUT), self.base_now, reason=None, claimedActorId=None)
        self.assertEqual(result.outcome, "apply")
        self.assertNotIn("reason", result.record)

    def test_receipt_prunes_nulls_recursively(self):
        receipt = create_receipt({**RECEIPT_MIN, "durationMs": None, "subject": None, "outcome": {"status": "succeeded", "code": None}})
        self.assertEqual((receipt["receiptHash"], receipt["replayKey"]), (MIN_RECEIPT_HASH, MIN_REPLAY_KEY))
        self.assertTrue(verify_receipt(receipt))

    def test_empty_retrieval_is_absent_for_derived_fields(self):
        receipt = create_receipt({**RECEIPT_MIN, "retrieval": {}})
        self.assertNotIn("retrievalHash", receipt)
        self.assertEqual(receipt["replayKey"], MIN_REPLAY_KEY)
        self.assertEqual(receipt["receiptHash"], EMPTY_RETRIEVAL_RECEIPT_HASH)
        self.assertTrue(verify_receipt(receipt))
        with_documents = create_receipt({**RECEIPT_MIN, "retrieval": {"queryHash": "sha256:" + "b" * 64, "documents": []}})
        self.assertRegex(with_documents["retrievalHash"], r"^sha256:[0-9a-f]{64}$")

    def test_decision_must_be_approve_or_reject(self):
        proposal = create_proposal(BASE_INPUT)
        for decision in ("approved", "APPROVE", "", None, 1):
            with self.subTest(decision), self.assertRaises(ValueError):
                approve_at(proposal, self.base_now, decision)

    def test_capsule_version_is_bound(self):
        evil = {**create_proposal(BASE_INPUT), "capsuleVersion": "evil"}
        self.assertFalse(verify_proposal(evil))
        self.assertEqual(approve_at(evil, self.base_now).code, "proposal_tampered")
        rehashed = stored_with(capsuleVersion="evil")
        self.assertFalse(verify_proposal(rehashed))
        self.assertNotEqual(rehashed["proposalHash"], create_proposal(BASE_INPUT)["proposalHash"])
        self.assertEqual(approve_at(rehashed, self.base_now).code, "proposal_tampered")

    def test_otel_timing_floors_to_integer_milliseconds_like_date_parse(self):
        def end(occurred_at):
            return receipt_span(create_receipt({**RECEIPT_MIN, "occurredAt": occurred_at}))["endTimeMs"]

        self.assertEqual(end("2026-10-14T15:00:00.9996Z"), 1791990000999)
        self.assertEqual(end("2026-10-14T15:00:00.001500Z"), 1791990000001)

    def test_lone_surrogate_key_is_a_canonical_json_error(self):
        for bad in ({"\ud800": 1, "a": 2}, {"a": {"\udfff": 1}}):
            with self.subTest(repr(bad)), self.assertRaises(CanonicalJsonError):
                canonical_json(bad)

    def test_kit_version(self):
        self.assertEqual(KIT_VERSION, "1.1.1")


if __name__ == "__main__":
    unittest.main()
