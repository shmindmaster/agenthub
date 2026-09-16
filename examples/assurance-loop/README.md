# AgentHub Assurance Loop

This offline demo makes the product boundary visible:

> The model proposes. Software decides. The executor acts. Evidence records what happened.

The proposed action is untrusted JSON. AgentHub validates its typed contract, loads approval from a separate trusted store bound to the decision ID and proposal digest, applies policy outside the model, performs only an authorized synthetic file write in a temporary workspace, and records the observed final state in a hash-linked receipt.

Run the four-outcome demo:

```powershell
pwsh -NoProfile -File ./examples/assurance-loop/Invoke-AssuranceDemo.ps1
```

It demonstrates four materially different outcomes:

1. `invalid`: an undeclared `confidence` field fails strict schema validation before policy evaluation; this is a synthetic example of treating model output as untrusted input, not a calibration claim.
2. `traversal`: a schema-valid request containing a `..` segment is denied before path resolution.
3. `unapproved`: a valid write request is denied because the trusted approval store has no matching grant.
4. `approved`: the same byte-identical request is executed only when a separately stored approval matches both its decision ID and SHA-256 digest.

The demo does not call a model, touch a real repository, or claim that a model response is proof. Replace the fixture producer with any model that supports structured output; keep schema validation, authorization, execution, and receipt capture in deterministic software.

## Cross-project story

- **AgentHub Assurance Plane** owns capability resolution, policy, approval, and receipts.
- **[GitPin Evidence Gate](https://github.com/shmindmaster/gitpin)** can bind the resulting change claim to an exact base, head, path, line, and content hash.
- **[CrewScore Policy Linter](https://github.com/shmindmaster/crewscore)** can check whether the written operating policy explicitly covers approval, tool boundaries, state, and evidence requirements.

These projects remain independently useful. This is an illustrative composition, not a bundled integration or a claim that one score or model response guarantees safety.
