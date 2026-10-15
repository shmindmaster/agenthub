"""execution-controls kit (Python reference implementation).

Vendored into product repositories by
``packages/product-experience-engineering/scripts/vendor-execution-controls.mjs``;
do not edit a vendored copy. Change the kit in AgentHub, run its tests, and
re-vendor.
"""

from .approval_capsule import (
    AUDIT_VERSION,
    CAPSULE_VERSION,
    REFUSALS,
    ApprovalPolicy,
    DecideResult,
    Principal,
    create_proposal,
    decide,
    proposal_hash_of,
    request_hash_of,
    verify_proposal,
)
from .canonical_json import CanonicalJsonError, canonical_hash, canonical_json, sha256_hex
from .otel_genai import emit_receipt_span, receipt_span
from .receipt import (
    RECEIPT_VERSION,
    compare_replay,
    create_receipt,
    replay_key_of,
    verify_chain,
    verify_receipt,
)

KIT_VERSION = "1.1.1"

__all__ = [
    "AUDIT_VERSION",
    "CAPSULE_VERSION",
    "KIT_VERSION",
    "RECEIPT_VERSION",
    "REFUSALS",
    "ApprovalPolicy",
    "CanonicalJsonError",
    "DecideResult",
    "Principal",
    "canonical_hash",
    "canonical_json",
    "compare_replay",
    "create_proposal",
    "create_receipt",
    "decide",
    "emit_receipt_span",
    "proposal_hash_of",
    "receipt_span",
    "replay_key_of",
    "request_hash_of",
    "sha256_hex",
    "verify_chain",
    "verify_proposal",
    "verify_receipt",
]
