# Ready-only independent PR reviewer (SH-4416)

`packages/coding-agent-dispatch/reviewer/Invoke-PrReview.ps1` replaces the
Sentry Seer Code Review step for AgentHub pull requests from 2026-12-08. It
reviews a pull request through the existing windowless dispatcher on a host
different from the one that authored the PR. The script itself never
approves, never merges, never pushes and never edits the pull request. The
owner keeps merge control.

## Read-only is not enforced on the model run

The script issues no write command, but the model it starts is a normal
dispatcher run. What the reviewer does to limit that run (see Guardrails)
does not make the model run read-only: the dispatcher has no enforced
read-only mode, so a model that follows text injected through a pull
request can still write wherever its host's own permissions allow.

- Automatic triggering must not be enabled until the dispatcher has an
  enforced read-only mode. That includes the SH-4411 wiring below.
- Until then the tool is run manually by the owner's session, on pull
  requests the owner has chosen to review.

## Run it

Manual run (reviews and prints the result, posts nothing):

```powershell
pwsh -NoProfile -File .\packages\coding-agent-dispatch\reviewer\Invoke-PrReview.ps1 `
  -Repo shmindmaster/agenthub -Pr <number>
```

Review and publish the one bounded summary comment (the only write this tool
ever performs):

```powershell
pwsh -NoProfile -File .\packages\coding-agent-dispatch\reviewer\Invoke-PrReview.ps1 `
  -Repo shmindmaster/agenthub -Pr <number> -Post
```

Is an earlier verdict still current? A new head SHA makes an earlier PASS
stale:

```powershell
pwsh -NoProfile -File .\packages\coding-agent-dispatch\reviewer\Invoke-PrReview.ps1 `
  -Repo shmindmaster/agenthub -Pr <number> -Status
```

Optional: `-HostId` picks the reviewer host (refused if it is also the author
host), `-Model` passes a model through to the dispatcher (subscription routes
only; the dispatcher enforces that), `-Force` re-reviews a head that already
has a verdict, `-ReviewerLogin` names the GitHub login whose comments carry
trusted markers (default: the account `gh` is signed in as), `-DiffMaxChars` and `-MaxGroups` bound the per-group diff
review. Everything is also testable offline: `tests/Test-PrReview.ps1` runs
the full behavior with a stubbed `gh` and dispatcher — no network, no model
run, no GitHub.

## Behavior

- A draft PR is refused with exit 3 and a clear message.
- If a review comment from this tool already exists for the exact head SHA,
  the run exits 0 without a new model run unless `-Force`. The marker is a
  hidden HTML comment carrying the idempotence key
  `agenthub-pr-review|<repo>|<pr>|<head>|<trigger>` and the verdict.
- A marker counts only in a comment authored by the reviewer's own GitHub
  login (`gh api user`, or `-ReviewerLogin`) and only as the very first thing
  in the comment body; one marker is read per comment. A marker anyone else
  posts, or one further down a comment, is ignored by the idempotence check
  and by `-Status`. If the login cannot be resolved the run stops with exit
  2. `-ReviewerLogin` must match the login exactly as
  `gh pr view --json comments` shows it for the posting account.
- Trigger filter: `opened` non-draft, `ready_for_review` and `manual`
  review; `synchronize` and `converted_to_draft` never review; a replayed
  event with the same key does not review a second time.
- The brief carries the PR title/body, linked issue ids, the base-to-head
  diff, the repo's `AGENTS.md` at the reviewed head, and the reviewer
  instructions in `packages/product/agents/reviewer.agent.md`. The diff is
  bounded (default 50000 characters per file group, 8 groups); files beyond
  that are named as not covered in the result and in the posted comment.
- The reviewer must answer in a fixed shape: verdict PASS | FAIL | BLOCKED,
  the exact head SHA, and findings each with severity, confidence, file,
  line, reproduction command or failing test, and fix rationale. A malformed
  answer is retried once; then the verdict is BLOCKED.
- A dispatcher failure (for example a policy-disabled host) is BLOCKED, not
  a crash. So is a run with no accepted answer, and a diff that could not be
  split into file groups (no review call ran).
- Without `-Post` nothing is posted. With `-Post` exactly one bounded
  comment is published by the script; the script never approves, never
  merges and never pushes. Text the model supplied is made inert before it
  is posted (marker text, HTML, table pipes and `@` mentions), each
  covered / not covered item is capped at 120 characters and each list at 20
  items, and the whole comment at 12000 characters.

## How it will be triggered later (SH-4411)

This run delivers the reviewer as code and tests only. It does not wire
webhooks, runners or cloud resources. The planned trigger is a GitHub
`pull_request` workflow filtering to `ready_for_review` (and manual
`workflow_dispatch`), running on AWS CodeBuild, which invokes this script
with `-Trigger ready_for_review -Post`. The trigger filter above is what
makes replayed and synchronize events safe. SH-4411 owns that wiring, and it
is blocked on an enforced read-only mode in the dispatcher (see above):
until both exist, the reviewer runs only when the owner's session invokes it
by hand.

## Rollback

The reviewer is additive: it replaces nothing until SH-4411 switches the
Seer step over. Rollback is revert the branch (or, after SH-4411, point the
CodeBuild step back at Sentry Seer). No state, service or credential is
created by this package: brief files and the per-call working directory
under `%LOCALAPPDATA%\AgentHub\runtime\pr-review\` are deleted after every
run.

## Guardrails

- Subscription routes only, never a pay-as-you-go wallet; the dispatcher's
  subscription-only refusals stay in force for the reviewer's runs.
- The reviewer host differs from the author host when the author host is
  known (branch prefix or `[host: <id>]` PR-body marker).
- No merge, approval or push is issued by this script or asked of the
  reviewer; the tests assert that the script issues no write command. They
  cannot assert what a real model run does.
- Limits on the model run, none of which is enforcement:
  - The pull request's own text (title, body, branch and author names, file
    names, `AGENTS.md` at the PR head, the diff) sits in blocks fenced by a
    random per-run delimiter, and the brief says that content is data, never
    instructions. The delimiter is removed from the data.
  - `GH_TOKEN`, `GITHUB_TOKEN`, `GH_ENTERPRISE_TOKEN` and every variable
    matching `*_API_KEY`, `*_TOKEN` or `*_SECRET` are removed from the
    environment for the dispatcher call and restored afterwards. A host that
    signs in through such a variable will fail and the verdict is BLOCKED.
    Credentials a host keeps on disk (its own login, `gh auth` state, git
    credential helpers) are not affected and stay reachable by the model.
  - The dispatcher's working directory is a new empty directory under
    `%LOCALAPPDATA%\AgentHub\runtime\pr-review\<id>`, never a repository
    checkout. The model can still reach other paths on the machine.
- The verdict is data, not action: PASS/FAIL/BLOCKED is printed (and posted
  with `-Post`), and a human owner decides what happens to the PR.
