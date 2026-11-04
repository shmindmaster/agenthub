# Agentic features

## Contents

- Where AI belongs
- Risk and autonomy
- Control
- Evidence and undo
- Failure
- Budgets
- Tools
- Evals
- Platform notes

## Where AI belongs

Use AI only where a deterministic UI is worse. Do not hide deterministic actions behind chat. A fixed action gets a control.

## Risk and autonomy

Rate each tool low, medium or high on four axes: read or write, reversibility, permissions, money. The highest rating applies.

| Consequence and reversibility | Rating | Interaction |
|---|---|---|
| Low consequence, easily reversible | Low | Act, with a status line and undo |
| Moderate consequence or ambiguity | Medium | Preview the plan and allow correction |
| High consequence, external effect or hard to reverse | High | Approval naming the exact action and arguments |
| Prohibited or unsupported | None | Refuse clearly and offer a safe alternative |

Narrow what each prompt asks rather than adding more prompts, because repeated approvals get approved unread. Never ask for blanket approval.

## Control

- Show a plan preview and checkpoints for multi-step work.
- Let the user interrupt and resume.
- Keep the user's input after a failed step.
- Make status available by keyboard and screen reader, never by motion or colour alone.

## Evidence and undo

- Attach sources to every claim and the tool call to every action.
- Keep an audit timeline of what ran, with what arguments, and what changed.
- Offer undo for every reversible action.
- Do not present model confidence as fact.

For a consequential approval or AI decision, use [execution controls](../kits/execution-controls/README.md), which binds the approval to the exact payload and records each step.

## Failure

Define the behaviour for each case, and give each a human handoff:

| Case | Define |
|---|---|
| Tool failure | Retry limit, what the user sees, what is kept |
| Timeout | Time limit, partial result, resume path |
| Stale context | How it is detected, and re-read or re-approval |
| Refusal | The reason shown and the safe alternative |

## Budgets

Set a latency and cost budget per task. Stream progress. Cap loop iterations, and stop with a handoff at the cap.

## Tools

Design tools like UI: clear names, few of them, short responses.

## Evals

1. Collect 20 to 50 tasks from real failures.
2. Run each task several times, because agents are not deterministic.
3. Grade the final environment state, not the agent's claim.
4. Use code graders first, then calibrated LLM graders, then humans.
5. Keep capability and regression sets separate.
6. Track cost and latency with each run.

## Platform notes

- MCP Apps: `ui://` HTML renders in a sandboxed iframe, and the host approves UI-initiated tool calls.
- AI SDK: use `toolApproval`. Do not use `needsApproval`, which is deprecated.
- Keep evals and orchestration portable. Do not hard-wire OpenAI Agent Builder or OpenAI Evals.
