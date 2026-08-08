# Execution Plans

Complex, multi-session work gets a resumable plan under `docs/plans/active/`.
Completed plans move to `docs/plans/completed/`.

## When a plan is required

- Work spanning multiple capabilities, registry surfaces, or fleet repos.
- Changes to the fleet standard, the checker, or the RepoWise workspace shape.
- Anything likely to outlive one session's context.

## What a plan maintains

Purpose/outcome · verified current behavior · target observable behavior ·
explicit exclusions · progress · discoveries · decision log · milestones with
validation per milestone · files expected to change · risks and rollback ·
final evidence.

A plan is living execution state, not a design document. Another agent must
be able to resume from the plan alone.
