# CodeBuild pull-request CI

Reusable CloudFormation for one GitHub repository. AWS CodeBuild is the CI engine. This design uses no GitHub runner droplets and no persistent self-hosted runners. Applying this repository change creates nothing in AWS.

The template is `ci/codebuild/pr-ci.template.yaml`. A repository description is turned into a parameter file by `ci/codebuild/New-CodeBuildPrCiParameters.ps1`. `ci/codebuild/Get-CodeBuildPreflight.ps1` prints a read-only inventory when an operator runs it later.

## Assumptions

- Linux only. `ci/codebuild/buildspecs/agenthub.yml` mirrors the `powershell-tests` job in `.github/workflows/ci.yml`. It does not run the `doctor` job and it does not replace the macOS or Windows matrix.
- `scripts/AgentHub.ps1 validate` delegates to `scripts/Validate-AgentHub.ps1`. The buildspec calls `Validate-AgentHub.ps1` once, then `AgentHub.ps1 sync` against a synthetic profile, then `tests/Run-AllTests.ps1` with `./tests/ci-skip.json`.
- Default compute is `BUILD_GENERAL1_SMALL` and the default image is `aws/codebuild/standard:8.0`. Whether the AgentHub suite fits in SMALL was not measured.
- The artifact bucket and the CodeConnections connection already exist. The stack does not create them.
- Native mode defaults to `FORK_PULL_REQUESTS` with approver roles `GITHUB_WRITE`, `GITHUB_MAINTAIN`, and `GITHUB_ADMIN`. `ALL_PULL_REQUESTS` is the stricter setting.
- Runner mode does not set `PullRequestBuildPolicy`. Repository workflow approval settings apply there.
- `$0.005` per minute below is the public pricing-page example, not a measured regional rate.
- Nothing in this change was deployed. CloudFormation did not validate the template.

## Prerequisites

- A CodeConnections or CodeStar Connections GitHub App connection whose status is `AVAILABLE`. Shape only: `arn:aws:codeconnections:us-east-1:000000000000:connection/00000000-0000-0000-0000-000000000000`.
- An existing S3 bucket with SSE-S3 (AES256) and Block Public Access. A customer-managed key fails because the build role has no `kms` permission.
- Outbound HTTPS. The template attaches no VPC, no KMS key, and no ECR image.
- Authority to create the stack is a separate operator step. The files in this folder do not grant it.

## Parameter file

Write one JSON object. Unknown fields are rejected. A field that supplies a role, and any IAM role ARN, is rejected. The stack creates the build role itself.

```json
{
  "GitHubOwner": "example-owner",
  "GitHubRepository": "example-repo",
  "ConnectionArn": "arn:aws:codeconnections:us-east-1:000000000000:connection/00000000-0000-0000-0000-000000000000",
  "BuildSpecPath": "ci/codebuild/buildspecs/agenthub.yml",
  "ArtifactBucketName": "example-ci-artifacts",
  "BaseBranches": ["main"]
}
```

`BaseBranches` is a list of branch names or one comma-separated string. The writer escapes each name and emits `BaseBranchPattern`. One branch becomes `^refs/heads/main$`. `main` and `release.1` become `^refs/heads/(main|release\.1)$`.

```powershell
pwsh -NoProfile -File .\ci\codebuild\New-CodeBuildPrCiParameters.ps1 -DescriptionPath .\repo.json -OutPath .\ci-params.json
```

The output is a CreateStack parameters document: an array of `ParameterKey` and `ParameterValue`. It is not a `deploy --parameter-overrides` file. The writer always emits all 19 template parameters, including `PrivilegedMode` as `false` unless the description sets the JSON boolean `true`.

## Deploy one repository

Run these only from an operator session that is allowed to create the stack. Replace the placeholders. This change did not run them.

```text
aws cloudformation create-change-set --stack-name example-repo-pr-ci --change-set-name pr-ci-1 --template-body file://ci/codebuild/pr-ci.template.yaml --parameters file://ci-params.json --capabilities CAPABILITY_NAMED_IAM --profile example --region us-east-1
```

Review the change set, then create or update the stack with the same parameters file and `CAPABILITY_NAMED_IAM`. Named IAM is required because the role name is `${ProjectName}-build`.

`ProjectName` is 2 to 48 characters so that name plus `-build` stays inside the IAM 64-character limit. The role, the project, and the log group use `DeletionPolicy: Delete` and `UpdateReplacePolicy: Delete`.

## IAM boundary

The build role trusts only `codebuild.amazonaws.com` to call `sts:AssumeRole`. Its inline policy is named `build-only`. That policy allows:

- `logs:CreateLogGroup`, `logs:CreateLogStream`, and `logs:PutLogEvents` on this project's log group and its streams.
- `s3:GetObject`, `s3:PutObject`, `s3:AbortMultipartUpload`, and `s3:ListMultipartUploadParts` on `arn:...:s3:::bucket/prefix/*`.
- `s3:ListBucket` on the bucket, and only when the prefix matches the artifact prefix.
- `s3:GetBucketLocation` and `s3:GetEncryptionConfiguration` on the bucket.
- `GetConnectionToken`, `GetConnection`, and `UseConnection` for both `codeconnections` and `codestar-connections`, on the one connection ARN.

It does not allow `ecr`, `secretsmanager`, `ssm`, `iam`, or `kms`. It does not allow `iam:PassRole`, `s3:DeleteObject`, or an action of `*` on a resource of `*`. There are no managed policies. `PrivilegedMode` defaults to `false`. `PermissionsBoundaryArn` is optional and must be an IAM policy ARN. A role ARN is refused. This role cannot deploy and it is not attached to a production resource.

The project reports build status to GitHub (`ReportBuildStatus: true`) with context `codebuild/${ProjectName}`. Image pull credentials are `CODEBUILD`, so the role needs no registry permission. Cache and artifacts stay under the one prefix. Because the artifact type is S3, a native-mode buildspec must publish at least one file. The example and the AgentHub buildspec write `ci-out/source-version.txt`.

## Trusted actors and fork pull requests

Native mode (`CiMode=native`, the default) installs one webhook filter group. Both filters must match:

- `EVENT` is `PULL_REQUEST_CREATED,PULL_REQUEST_UPDATED,PULL_REQUEST_REOPENED`.
- `BASE_REF` matches `BaseBranchPattern`.

`PUSH` is not a filter. A branch push does not start this project.

`RequiresCommentApproval` defaults to `FORK_PULL_REQUESTS`. A pull request from this repository builds when the author holds one of `ApproverRoles` (default `GITHUB_WRITE`, `GITHUB_MAINTAIN`, `GITHUB_ADMIN`). A fork pull request does not build until one of those roles approves it. CodeBuild records an unapproved build as failed and asks for pull-request approval. A trusted user then comments on the pull request, substituting the pull request head SHA:

```text
/codebuild_run(<head-sha>)
```

`ALL_PULL_REQUESTS` requires that approval for every pull request, including same-repository ones. Use it when the repository wants the tighter gate. `DISABLED` turns the approval gate off. Leave the default in place unless the repository has a written reason to change it.

`CODEBUILD_RESOLVED_SOURCE_VERSION` is the commit id after source download. On a pull-request webhook, `CODEBUILD_SOURCE_VERSION` is `pr/<number>`, and `CODEBUILD_WEBHOOK_HEAD_REF` is a ref name, not a SHA. This change did not observe a live status, so it does not claim that the GitHub status SHA equals the pull request head. The AgentHub buildspec prints those variables. The first real pull request has to confirm the status is on the head SHA.

## Runner mode

Set `CiMode` to `runner` when the repository keeps its workflow YAML and wants a CodeBuild-hosted ephemeral GitHub Actions runner. The only webhook event is `WORKFLOW_JOB_QUEUED`. `PullRequestBuildPolicy` is omitted in this mode. The buildspec parameter is ignored because GitHub Actions runs the workflow already in the repository.

The stack output `RunnerRunsOnPrefix` is `codebuild-${ProjectName}-`. The workflow label adds the run id and the run attempt. Those expressions stay in the workflow file. They are not substituted by the template:

```text
codebuild-<ProjectName>-${{ github.run_id }}-${{ github.run_attempt }}
```

An ephemeral runner still bills CodeBuild minutes. It is not a persistent runner and it is not a droplet.

## Cost model

On-demand CodeBuild bills duration rounded up to the next minute. A build that runs for more than zero seconds bills at least one minute.

```text
billed_minutes = ceil(seconds / 60)
monthly_codebuild = max(0, sum(billed_minutes) - free_tier_minutes) * rate_per_minute
monthly_droplet = 24 * days_in_month * hourly_price + storage
break_even_minutes = monthly_droplet / rate_per_minute
```

The public pricing page, published 2026-10-16 and read 2026-11-11, states a free tier of 100 build minutes per month for `general1.small` or `arm1.small` on-demand EC2. Its worked example is 100 builds of 5 minutes, which is 500 minutes, minus 100 free minutes, times `$0.005`, which is `$2` for `build.general1.small`. That `$0.005` is the page's example. It is not a quote for a region and it was not measured for this account.

These numbers still have to be measured before a cost decision:

- the regional on-demand rate for the chosen compute type
- this repository's build duration distribution
- pull-request volume
- the account concurrent-build quota (the preflight prints it)
- CloudWatch Logs and S3 storage
- any droplet hourly price used only as the comparison term

A persistent runner droplet is the comparison in `monthly_droplet`. It is not the selected design.

## Rollback

Delete the stack. That is the rollback.

```text
aws cloudformation delete-stack --stack-name example-repo-pr-ci --profile example --region us-east-1
```

Deleting the stack deletes the CodeBuild project, the build role, and the log group. It does not delete the artifact bucket or the CodeConnections connection. Objects under the prefix remain until an operator removes that prefix.

## Per repository

### AgentHub

Use native mode and `BuildSpecPath` `ci/codebuild/buildspecs/agenthub.yml`. GitHub-hosted Ubuntu already has PowerShell. The CodeBuild image does not, so the buildspec installs it from packages.microsoft.com, then Node.js LTS from `https://nodejs.org/dist/index.json` the same way `actions/setup-node` resolves `lts/*`, then Python 3.12, ripgrep, ffmpeg, `@anthropic-ai/claude-code@2.1.310`, `typescript@5.9.3`, and `@types/node@24.10.1`. It then runs:

```text
pwsh -NoProfile -File ./scripts/Validate-AgentHub.ps1
pwsh -NoProfile -File ./scripts/AgentHub.ps1 sync -UserProfile <synthetic-dir>
pwsh -NoProfile -File ./tests/Run-AllTests.ps1 -SkipListPath ./tests/ci-skip.json
```

`ci/codebuild/buildspec.example.yml` is the short placeholder for another repository. It still publishes `ci-out/source-version.txt`.

The AgentHub pull-request reviewer at `packages/coding-agent-dispatch/reviewer` is manual. This template does not trigger it.

### ABACare

ABACare keeps a one-workflow policy. `tests/architecture/test_ci_release_gate.py` guards that policy. ABACare also has a separate SSH pre-push gate (SH-4400). This template does not replace that gate. ABACare uses native webhook mode and adds no new workflow file. Do not point ABACare at runner mode in order to host a second workflow.

## Preflight

The preflight is read-only. Run it from an operator session that already has the named profile. This change did not run it against AWS.

```powershell
pwsh -NoProfile -File .\ci\codebuild\Get-CodeBuildPreflight.ps1 -Profile example -Region us-east-1
```

It prints the UTC time, the region, the profile name, the caller account masked to the last four digits, each CodeBuild project's source, auth, cache, artifacts, and webhook filters, each connection's provider and status, the concurrent-build quota when `list-service-quotas` returns a quota whose name contains "concurrent", and the last 30 days of build minutes by project. Billed minutes are `ceil(seconds / 60)`. Webhook secrets are not printed. Account ids inside ARNs are masked to eight asterisks plus the last four digits. If `batch-get-projects` omits webhook filters, the line says they were not returned. That is "not established", not "checked and absent".

The local guard check calls no AWS API:

```powershell
pwsh -NoProfile -File .\ci\codebuild\Get-CodeBuildPreflight.ps1 -SelfTest
```

A real inventory needs `sts:GetCallerIdentity`, `codebuild:ListProjects`, `codebuild:BatchGetProjects`, `codebuild:ListBuildsForProject`, `codebuild:BatchGetBuilds`, `codeconnections:ListConnections` or `codestar-connections:ListConnections`, and `servicequotas:ListServiceQuotas`. The script refuses any other operation shape.

## Not verified

- No stack was created, updated, or deleted.
- CloudFormation `validate-template` was not run. The repository test reads the template with an indent subset parser and says so.
- The buildspec was not executed on CodeBuild.
- A GitHub status SHA was not compared with a pull request head SHA.
- Regional price, build duration, pull-request volume, and the concurrent-build quota were not measured.
- The preflight was not run against an AWS account.
