"""execution-controls kit: approval capsule (spec: ../../spec/approval-capsule.md).

A capsule binds one proposed change to the exact payload, subject revision,
tenant and proposer it was computed from. ``decide`` is a pure function: the
adopter loads the stored proposal, the subject's current revision and the prior
decisions inside one transaction that holds a row lock on the subject, calls
``decide``, and then either applies the change and stores the decision, or
stores only the audit row. Every outcome, including every refusal, returns
exactly one audit row.

Proposals, requests and records are plain dicts with the same camelCase keys
as the TypeScript module and the JSON Schemas, so a proposal hashed in one
language verifies in the other.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Literal, Mapping, Sequence

from .canonical_json import canonical_hash, drop_none
from .timestamps import parse_utc_ms

CAPSULE_VERSION = "approval-capsule/v1"
AUDIT_VERSION = "approval-audit/v1"

REFUSALS: dict[str, int] = {
    "capsule_not_found": 404,
    "actor_mismatch": 403,
    "proposal_tampered": 409,
    "proposal_hash_mismatch": 409,
    "actor_not_authorized": 403,
    "self_approval_forbidden": 403,
    "idempotency_key_reused": 422,
    "already_decided": 409,
    "proposal_expired": 410,
    "stale_proposal": 409,
}

MESSAGES: dict[str, str] = {
    "capsule_not_found": "No such proposal for this tenant.",
    "actor_mismatch": "The actor in the request is not the signed-in user.",
    "proposal_tampered": "The stored proposal no longer matches its hash.",
    "proposal_hash_mismatch": "The proposal changed after you reviewed it.",
    "actor_not_authorized": "You are not allowed to decide this proposal.",
    "self_approval_forbidden": "The person who proposed a change cannot approve it.",
    "idempotency_key_reused": "This idempotency key was already used for a different request.",
    "already_decided": "This proposal already has a different decision.",
    "proposal_expired": "This proposal expired before it was approved.",
    "stale_proposal": "The record changed after this proposal was made.",
}

Outcome = Literal["apply", "reject", "replay", "refuse"]


@dataclass(frozen=True)
class DecideResult:
    outcome: Outcome
    status: int
    audit: dict[str, Any]
    record: dict[str, Any] | None = None
    code: str | None = None
    message: str | None = None

    def error_body(self) -> dict[str, Any]:
        """The error body every adopter returns for a refusal."""
        return {"error": {"code": self.code, "message": self.message}}


@dataclass(frozen=True)
class ApprovalPolicy:
    approver_roles: Sequence[str]
    allow_self_approval: bool = False

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "ApprovalPolicy":
        return cls(
            approver_roles=tuple(value.get("approverRoles", ())),
            allow_self_approval=bool(value.get("allowSelfApproval", False)),
        )


@dataclass(frozen=True)
class Principal:
    """The authenticated caller. Never built from request-body fields."""

    id: str
    tenant_id: str
    roles: Sequence[str] = field(default_factory=tuple)

    @classmethod
    def from_json(cls, value: Mapping[str, Any]) -> "Principal":
        return cls(id=value["id"], tenant_id=value["tenantId"], roles=tuple(value.get("roles", ())))


def proposal_hash_of(proposal: Mapping[str, Any]) -> str:
    """Hash of every field but ``proposalHash``, the stored ``capsuleVersion`` included.

    Top-level ``None`` means absent, so a proposal reloaded from a store that
    writes ``null`` for a missing ``expiresAt`` still verifies.
    """
    return canonical_hash(drop_none({key: value for key, value in proposal.items() if key != "proposalHash"}))


def create_proposal(proposal_input: Mapping[str, Any]) -> dict[str, Any]:
    """Return the stored form of a proposal: the input plus version and hash.

    Top-level ``None`` values mean "absent". The payload is hashed as given,
    nulls included. ``createdAt`` and ``expiresAt`` must be ISO-8601 UTC
    timestamps ending in ``Z``; anything else raises ``ValueError``.
    """
    body = drop_none(dict(proposal_input))
    if parse_utc_ms(body.get("createdAt")) is None:
        raise ValueError(f'createdAt must be an ISO-8601 UTC timestamp ending in "Z", got {body.get("createdAt")!r}')
    if "expiresAt" in body and parse_utc_ms(body["expiresAt"]) is None:
        raise ValueError(f'expiresAt must be an ISO-8601 UTC timestamp ending in "Z", got {body["expiresAt"]!r}')
    body["capsuleVersion"] = CAPSULE_VERSION
    body["proposalHash"] = proposal_hash_of(body)
    return body


def verify_proposal(proposal: Mapping[str, Any]) -> bool:
    return proposal.get("capsuleVersion") == CAPSULE_VERSION and proposal_hash_of(proposal) == proposal.get("proposalHash")


def request_hash_of(request: Mapping[str, Any], actor_id: str) -> str:
    return canonical_hash(
        drop_none(
            {
                "proposalHash": request["proposalHash"],
                "decision": request["decision"],
                "actorId": actor_id,
                "reason": request.get("reason"),
            }
        )
    )


def decide(
    *,
    proposal: Mapping[str, Any],
    request: Mapping[str, Any],
    principal: Principal,
    current_revision: int | str,
    prior_decisions: Sequence[Mapping[str, Any]],
    policy: ApprovalPolicy,
    now: str,
) -> DecideResult:
    decision = request.get("decision")
    if decision not in ("approve", "reject"):
        raise ValueError(f'decision must be "approve" or "reject", got {decision!r}')
    subject = proposal["subject"]

    def audit(outcome: str, status: int, code: str | None) -> dict[str, Any]:
        return {
            "auditVersion": AUDIT_VERSION,
            "tenantId": principal.tenant_id,
            "capsuleId": proposal["capsuleId"],
            "action": proposal["action"],
            "subjectType": subject["type"],
            "subjectId": subject["id"],
            "subjectRevision": current_revision,
            "presentedHash": request["proposalHash"],
            "proposalHash": proposal.get("proposalHash"),
            "decision": decision,
            "actorId": principal.id,
            "idempotencyKey": request["idempotencyKey"],
            "outcome": outcome,
            "code": code,
            "status": status,
            "at": now,
        }

    def refuse(code: str) -> DecideResult:
        status = REFUSALS[code]
        row = audit("refused", status, code)
        if code == "capsule_not_found":
            # The row lands in the caller's tenant: it must not describe another tenant's proposal.
            row.update(capsuleId=None, action=None, subjectType=None, subjectId=None, subjectRevision=None, proposalHash=None)
        return DecideResult("refuse", status, row, code=code, message=MESSAGES[code])

    # Tenant first, and as 404: a caller in another tenant learns nothing.
    if principal.tenant_id != proposal["tenantId"]:
        return refuse("capsule_not_found")
    claimed = request.get("claimedActorId")
    if claimed is not None and claimed != principal.id:
        return refuse("actor_mismatch")
    if not verify_proposal(proposal):
        return refuse("proposal_tampered")
    if request["proposalHash"] != proposal["proposalHash"]:
        return refuse("proposal_hash_mismatch")
    if not any(role in policy.approver_roles for role in principal.roles):
        return refuse("actor_not_authorized")
    proposer = proposal["proposedBy"]
    if (
        decision == "approve"
        and not policy.allow_self_approval
        and proposer["kind"] == "user"
        and proposer["id"] == principal.id
    ):
        return refuse("self_approval_forbidden")

    request_hash = request_hash_of(request, principal.id)
    same_key = next((r for r in prior_decisions if r["idempotencyKey"] == request["idempotencyKey"]), None)
    if same_key is not None:
        if same_key["requestHash"] != request_hash:
            return refuse("idempotency_key_reused")
        return DecideResult("replay", 200, audit("replayed", 200, None), record=dict(same_key))
    prior = next((r for r in prior_decisions if r["proposalHash"] == proposal["proposalHash"]), None)
    if prior is not None:
        if prior["decision"] != decision:
            return refuse("already_decided")
        return DecideResult("replay", 200, audit("replayed", 200, None), record=dict(prior))

    if decision == "approve":
        # Fail closed: a clock or an expiry that cannot be read is an expired proposal.
        now_ms = parse_utc_ms(now)
        if now_ms is None:
            return refuse("proposal_expired")
        expires_at = proposal.get("expiresAt")
        if expires_at is not None:
            expires_ms = parse_utc_ms(expires_at)
            if expires_ms is None or now_ms >= expires_ms:
                return refuse("proposal_expired")
        if str(current_revision) != str(subject["revision"]):
            return refuse("stale_proposal")

    record = drop_none(
        {
            "capsuleId": proposal["capsuleId"],
            "proposalHash": proposal["proposalHash"],
            "decision": decision,
            "actorId": principal.id,
            "idempotencyKey": request["idempotencyKey"],
            "requestHash": request_hash,
            "subjectRevisionBefore": current_revision,
            "decidedAt": now,
            "reason": request.get("reason"),
        }
    )
    if decision == "approve":
        return DecideResult("apply", 200, audit("applied", 200, None), record=record)
    return DecideResult("reject", 200, audit("rejected", 200, None), record=record)
