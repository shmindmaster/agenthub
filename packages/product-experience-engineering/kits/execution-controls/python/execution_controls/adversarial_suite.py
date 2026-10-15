"""execution-controls kit: adversarial suite for an adopter's real approval path.

The vectors in ../../vectors/ prove ``decide`` itself. This suite proves the
product wired it correctly: the HTTP route (or service) binds the actor from
the session, holds the lock, applies at most once, and audits every refusal.

Implement ``CapsuleAdapter`` against the product (test client plus database)
and call ``assert_adversarial_suite(adapter)`` from the product's own tests.
Each case starts from ``adapter.setup()``, so cases cannot leak into each
other.
"""

from __future__ import annotations

import threading
from dataclasses import dataclass
from typing import Any, Callable, Protocol

Actor = str  # "approver" | "second_approver" | "proposer" | "viewer" | "other_tenant"


class CapsuleAdapter(Protocol):
    proposer_is_user: bool
    """True when the proposer is a person who could try to approve their own proposal."""

    def setup(self) -> Any:
        """Fresh subject at a known revision with one pending proposal. Returns a context."""

    def proposal(self, ctx: Any) -> dict[str, Any]:
        """The proposal as the product shows it to an approver; must include ``proposalHash``."""

    def decide(
        self,
        ctx: Any,
        *,
        actor: Actor,
        proposal_hash: str,
        decision: str,
        idempotency_key: str,
        claimed_actor_id: str | None = None,
    ) -> tuple[int, dict[str, Any]]:
        """Send the decision as ``actor`` through the product. Returns (status, body)."""

    def change_subject(self, ctx: Any) -> None:
        """Change the subject through a normal product path, bumping its revision."""

    def tamper_stored_proposal(self, ctx: Any) -> None:
        """Change the stored payload directly, without recomputing the hash."""

    def side_effects(self, ctx: Any) -> int:
        """How many times the approved change has been applied."""

    def audit_outcomes(self, ctx: Any) -> list[tuple[str, str | None]]:
        """(outcome, code) for every audit row written for this proposal, oldest first."""


@dataclass
class CaseResult:
    name: str
    passed: bool
    detail: str = ""


class _Fail(AssertionError):
    pass


def _expect(condition: bool, message: str) -> None:
    if not condition:
        raise _Fail(message)


def _code(body: dict[str, Any]) -> str | None:
    error = body.get("error") if isinstance(body, dict) else None
    return error.get("code") if isinstance(error, dict) else None


def _refused(adapter: CapsuleAdapter, ctx: Any, status: int, body: dict[str, Any], want_status: int, want_code: str) -> None:
    _expect(status == want_status, f"status {status}, want {want_status}")
    _expect(_code(body) == want_code, f"error code {_code(body)!r}, want {want_code!r}")
    _expect(adapter.side_effects(ctx) == 0, "a refused decision applied the change")
    _expect(("refused", want_code) in adapter.audit_outcomes(ctx), f"no audit row ('refused', {want_code!r})")


def _cases(adapter: CapsuleAdapter) -> list[tuple[str, Callable[[], None]]]:
    def approve(ctx: Any, actor: Actor = "approver", key: str = "adv-1", **extra: Any) -> tuple[int, dict[str, Any]]:
        return adapter.decide(
            ctx,
            actor=actor,
            proposal_hash=extra.pop("proposal_hash", adapter.proposal(ctx)["proposalHash"]),
            decision=extra.pop("decision", "approve"),
            idempotency_key=key,
            **extra,
        )

    def approve_applies_once() -> None:
        ctx = adapter.setup()
        status, _ = approve(ctx)
        _expect(status == 200, f"approve returned {status}")
        _expect(adapter.side_effects(ctx) == 1, f"side effects {adapter.side_effects(ctx)}, want 1")
        _expect(("applied", None) in adapter.audit_outcomes(ctx), "no audit row ('applied', None)")

    def replay_same_key_applies_once() -> None:
        ctx = adapter.setup()
        first, _ = approve(ctx)
        second, _ = approve(ctx)
        _expect((first, second) == (200, 200), f"statuses {(first, second)}")
        _expect(adapter.side_effects(ctx) == 1, "a replay applied the change twice")
        _expect(("replayed", None) in adapter.audit_outcomes(ctx), "replay was not audited")

    def reapprove_new_key_applies_once() -> None:
        ctx = adapter.setup()
        approve(ctx, key="adv-1")
        status, _ = approve(ctx, key="adv-2")
        _expect(status == 200, f"re-approve returned {status}")
        _expect(adapter.side_effects(ctx) == 1, "re-approve applied the change twice")

    def second_approver_is_a_replay() -> None:
        ctx = adapter.setup()
        approve(ctx)
        status, _ = approve(ctx, actor="second_approver", key="adv-2")
        _expect(status == 200, f"second approver got {status}")
        _expect(adapter.side_effects(ctx) == 1, "second approver applied the change again")

    def reject_after_approve_conflicts() -> None:
        ctx = adapter.setup()
        approve(ctx)
        status, body = approve(ctx, key="adv-2", decision="reject")
        _expect(status == 409 and _code(body) == "already_decided", f"got {status} {_code(body)!r}")
        _expect(adapter.side_effects(ctx) == 1, "side effects changed")

    def same_key_different_body() -> None:
        ctx = adapter.setup()
        approve(ctx)
        status, body = approve(ctx, decision="reject")
        _expect(status == 422 and _code(body) == "idempotency_key_reused", f"got {status} {_code(body)!r}")

    def stale_revision_is_refused() -> None:
        ctx = adapter.setup()
        adapter.change_subject(ctx)
        status, body = approve(ctx)
        _refused(adapter, ctx, status, body, 409, "stale_proposal")

    def tampered_proposal_is_refused() -> None:
        ctx = adapter.setup()
        shown = adapter.proposal(ctx)["proposalHash"]
        adapter.tamper_stored_proposal(ctx)
        status, body = approve(ctx, proposal_hash=shown)
        _refused(adapter, ctx, status, body, 409, "proposal_tampered")

    def wrong_presented_hash_is_refused() -> None:
        ctx = adapter.setup()
        status, body = approve(ctx, proposal_hash="sha256:" + "0" * 64)
        _refused(adapter, ctx, status, body, 409, "proposal_hash_mismatch")

    def forged_actor_is_refused() -> None:
        ctx = adapter.setup()
        status, body = approve(ctx, claimed_actor_id="someone-else")
        _refused(adapter, ctx, status, body, 403, "actor_mismatch")

    def viewer_is_refused() -> None:
        ctx = adapter.setup()
        status, body = approve(ctx, actor="viewer")
        _refused(adapter, ctx, status, body, 403, "actor_not_authorized")

    def self_approval_is_refused() -> None:
        ctx = adapter.setup()
        status, body = approve(ctx, actor="proposer")
        _refused(adapter, ctx, status, body, 403, "self_approval_forbidden")

    def other_tenant_is_not_found() -> None:
        ctx = adapter.setup()
        status, body = approve(ctx, actor="other_tenant")
        _expect(status == 404, f"other tenant got {status}, want 404")
        _expect(adapter.side_effects(ctx) == 0, "other tenant applied the change")

    def concurrent_approvals_apply_once() -> None:
        ctx = adapter.setup()
        shown = adapter.proposal(ctx)["proposalHash"]
        statuses: list[int] = []

        def worker(key: str) -> None:
            status, _ = adapter.decide(ctx, actor="approver", proposal_hash=shown, decision="approve", idempotency_key=key)
            statuses.append(status)

        threads = [threading.Thread(target=worker, args=(f"adv-c{i}",)) for i in range(4)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(timeout=60)
        _expect(len(statuses) == 4, "a concurrent request did not finish")
        _expect(all(status < 500 for status in statuses), f"concurrent statuses {statuses}")
        _expect(adapter.side_effects(ctx) == 1, f"concurrent approvals applied {adapter.side_effects(ctx)} times")

    cases: list[tuple[str, Callable[[], None]]] = [
        ("approve_applies_once", approve_applies_once),
        ("replay_same_key_applies_once", replay_same_key_applies_once),
        ("reapprove_new_key_applies_once", reapprove_new_key_applies_once),
        ("second_approver_is_a_replay", second_approver_is_a_replay),
        ("reject_after_approve_conflicts", reject_after_approve_conflicts),
        ("same_key_different_body", same_key_different_body),
        ("stale_revision_is_refused", stale_revision_is_refused),
        ("tampered_proposal_is_refused", tampered_proposal_is_refused),
        ("wrong_presented_hash_is_refused", wrong_presented_hash_is_refused),
        ("forged_actor_is_refused", forged_actor_is_refused),
        ("viewer_is_refused", viewer_is_refused),
        ("other_tenant_is_not_found", other_tenant_is_not_found),
    ]
    if getattr(adapter, "proposer_is_user", False):
        cases.append(("self_approval_is_refused", self_approval_is_refused))
    if getattr(adapter, "supports_concurrency", False):
        cases.append(("concurrent_approvals_apply_once", concurrent_approvals_apply_once))
    return cases


def run_adversarial_suite(adapter: CapsuleAdapter) -> list[CaseResult]:
    results = []
    for name, case in _cases(adapter):
        try:
            case()
            results.append(CaseResult(name, True))
        except _Fail as failure:
            results.append(CaseResult(name, False, str(failure)))
    return results


def assert_adversarial_suite(adapter: CapsuleAdapter) -> list[CaseResult]:
    results = run_adversarial_suite(adapter)
    failed = [result for result in results if not result.passed]
    if failed:
        raise AssertionError("approval capsule adversarial suite failed:\n" + "\n".join(f"  {r.name}: {r.detail}" for r in failed))
    return results
