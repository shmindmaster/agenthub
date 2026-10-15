"""execution-controls kit: adversarial suite for an adopter's real approval path.

The vectors in ../../vectors/ prove ``decide`` itself. This suite proves the
product wired it correctly: the HTTP route (or service) binds the actor from
the session, holds the lock, applies at most once, and audits every refusal.

Implement ``CapsuleAdapter`` against the product (test client plus database)
and call ``assert_adversarial_suite(adapter)`` from a synchronous test, or
``await aassert_adversarial_suite(adapter)`` from an async one. Adapter methods
may be plain functions or coroutines: plain ones run in worker threads, so the
concurrency case is real either way. Each case starts from ``adapter.setup()``,
so cases cannot leak into each other. Same cases as the TypeScript suite.
"""

from __future__ import annotations

import asyncio
import inspect
from dataclasses import dataclass
from typing import Any, Awaitable, Callable, Protocol

Actor = str  # "approver" | "second_approver" | "proposer" | "viewer" | "other_tenant"


class CapsuleAdapter(Protocol):
    proposer_is_user: bool
    """True when the proposer is a person who could try to approve their own proposal."""

    has_viewer: bool
    """True when a signed-in participant can see the proposal without the right to decide it.
    Products where every participant may decide set False; the viewer case is then skipped."""

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
        """Change what the reviewer saw, bumping the subject's revision."""

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


async def _call(method: Callable[..., Any], *args: Any, **kwargs: Any) -> Any:
    if inspect.iscoroutinefunction(method):
        return await method(*args, **kwargs)
    result = await asyncio.to_thread(method, *args, **kwargs)
    return await result if inspect.isawaitable(result) else result


def _cases(adapter: CapsuleAdapter) -> list[tuple[str, Callable[[], Awaitable[None]]]]:
    async def setup() -> Any:
        return await _call(adapter.setup)

    async def shown_hash(ctx: Any) -> str:
        return (await _call(adapter.proposal, ctx))["proposalHash"]

    async def side_effects(ctx: Any) -> int:
        return await _call(adapter.side_effects, ctx)

    async def audit(ctx: Any) -> list[tuple[str, str | None]]:
        return [tuple(row) for row in await _call(adapter.audit_outcomes, ctx)]

    async def approve(
        ctx: Any,
        actor: Actor = "approver",
        key: str = "adversarial-key-1",
        decision: str = "approve",
        proposal_hash: str | None = None,
        claimed_actor_id: str | None = None,
    ) -> tuple[int, dict[str, Any]]:
        return await _call(
            adapter.decide,
            ctx,
            actor=actor,
            proposal_hash=proposal_hash or await shown_hash(ctx),
            decision=decision,
            idempotency_key=key,
            claimed_actor_id=claimed_actor_id,
        )

    async def refused(ctx: Any, result: tuple[int, dict[str, Any]], want_status: int, want_code: str) -> None:
        status, body = result
        _expect(status == want_status, f"status {status}, want {want_status}")
        _expect(_code(body) == want_code, f"error code {_code(body)!r}, want {want_code!r}")
        _expect(await side_effects(ctx) == 0, "a refused decision applied the change")
        _expect(("refused", want_code) in await audit(ctx), f"no audit row ('refused', {want_code!r})")

    async def approve_applies_once() -> None:
        ctx = await setup()
        status, _ = await approve(ctx)
        _expect(status == 200, f"approve returned {status}")
        _expect(await side_effects(ctx) == 1, f"side effects {await side_effects(ctx)}, want 1")
        _expect(("applied", None) in await audit(ctx), "no audit row ('applied', None)")

    async def replay_same_key_applies_once() -> None:
        ctx = await setup()
        first, _ = await approve(ctx)
        second, _ = await approve(ctx)
        _expect((first, second) == (200, 200), f"statuses {(first, second)}")
        _expect(await side_effects(ctx) == 1, "a replay applied the change twice")
        _expect(("replayed", None) in await audit(ctx), "replay was not audited")

    async def reapprove_new_key_applies_once() -> None:
        ctx = await setup()
        await approve(ctx, key="adversarial-key-1")
        status, _ = await approve(ctx, key="adversarial-key-2")
        _expect(status == 200, f"re-approve returned {status}")
        _expect(await side_effects(ctx) == 1, "re-approve applied the change twice")

    async def second_approver_is_a_replay() -> None:
        ctx = await setup()
        await approve(ctx)
        status, _ = await approve(ctx, actor="second_approver", key="adversarial-key-2")
        _expect(status == 200, f"second approver got {status}")
        _expect(await side_effects(ctx) == 1, "second approver applied the change again")

    async def reject_after_approve_conflicts() -> None:
        ctx = await setup()
        await approve(ctx)
        status, body = await approve(ctx, key="adversarial-key-2", decision="reject")
        _expect(status == 409 and _code(body) == "already_decided", f"got {status} {_code(body)!r}")
        _expect(await side_effects(ctx) == 1, "side effects changed")

    async def same_key_different_body() -> None:
        ctx = await setup()
        await approve(ctx)
        status, body = await approve(ctx, decision="reject")
        _expect(status == 422 and _code(body) == "idempotency_key_reused", f"got {status} {_code(body)!r}")

    async def stale_revision_is_refused() -> None:
        ctx = await setup()
        shown = await shown_hash(ctx)
        await _call(adapter.change_subject, ctx)
        await refused(ctx, await approve(ctx, proposal_hash=shown), 409, "stale_proposal")

    async def tampered_proposal_is_refused() -> None:
        ctx = await setup()
        shown = await shown_hash(ctx)
        await _call(adapter.tamper_stored_proposal, ctx)
        await refused(ctx, await approve(ctx, proposal_hash=shown), 409, "proposal_tampered")

    async def wrong_presented_hash_is_refused() -> None:
        ctx = await setup()
        await refused(ctx, await approve(ctx, proposal_hash="sha256:" + "0" * 64), 409, "proposal_hash_mismatch")

    async def forged_actor_is_refused() -> None:
        ctx = await setup()
        await refused(ctx, await approve(ctx, claimed_actor_id="someone-else"), 403, "actor_mismatch")

    async def viewer_is_refused() -> None:
        ctx = await setup()
        await refused(ctx, await approve(ctx, actor="viewer"), 403, "actor_not_authorized")

    async def self_approval_is_refused() -> None:
        ctx = await setup()
        await refused(ctx, await approve(ctx, actor="proposer"), 403, "self_approval_forbidden")

    async def other_tenant_is_not_found() -> None:
        ctx = await setup()
        status, _ = await approve(ctx, actor="other_tenant")
        _expect(status == 404, f"other tenant got {status}, want 404")
        _expect(await side_effects(ctx) == 0, "other tenant applied the change")

    async def concurrent_approvals_apply_once() -> None:
        ctx = await setup()
        shown = await shown_hash(ctx)
        results = await asyncio.wait_for(
            asyncio.gather(*(approve(ctx, key=f"adversarial-key-c{i}", proposal_hash=shown) for i in range(4))),
            timeout=60,
        )
        statuses = [status for status, _ in results]
        _expect(all(status < 500 for status in statuses), f"concurrent statuses {statuses}")
        _expect(await side_effects(ctx) == 1, f"concurrent approvals applied {await side_effects(ctx)} times")

    cases: list[tuple[str, Callable[[], Awaitable[None]]]] = [
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
        ("other_tenant_is_not_found", other_tenant_is_not_found),
    ]
    if getattr(adapter, "has_viewer", True):
        cases.append(("viewer_is_refused", viewer_is_refused))
    if getattr(adapter, "proposer_is_user", False):
        cases.append(("self_approval_is_refused", self_approval_is_refused))
    if getattr(adapter, "supports_concurrency", False):
        cases.append(("concurrent_approvals_apply_once", concurrent_approvals_apply_once))
    return cases


async def arun_adversarial_suite(adapter: CapsuleAdapter) -> list[CaseResult]:
    results = []
    for name, case in _cases(adapter):
        try:
            await case()
            results.append(CaseResult(name, True))
        except _Fail as failure:
            results.append(CaseResult(name, False, str(failure)))
    return results


def _raise_on_failure(results: list[CaseResult]) -> list[CaseResult]:
    failed = [result for result in results if not result.passed]
    if failed:
        raise AssertionError(
            "approval capsule adversarial suite failed:\n" + "\n".join(f"  {r.name}: {r.detail}" for r in failed)
        )
    return results


async def aassert_adversarial_suite(adapter: CapsuleAdapter) -> list[CaseResult]:
    return _raise_on_failure(await arun_adversarial_suite(adapter))


def run_adversarial_suite(adapter: CapsuleAdapter) -> list[CaseResult]:
    """Synchronous entry point; do not call from inside a running event loop."""
    return asyncio.run(arun_adversarial_suite(adapter))


def assert_adversarial_suite(adapter: CapsuleAdapter) -> list[CaseResult]:
    return _raise_on_failure(run_adversarial_suite(adapter))
