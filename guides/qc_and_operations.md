# StackLab QC And Operations

## Local Commands

```bash
mix deps.get
mix ci
mix gn_ten.proofs.validate --json
mix gn_ten.connector.scan --all-repos
mix gn_ten.tenant.scan --all-repos
```

Use proof-specific commands for focused work, then root `mix ci` before commit.

## Scanner And Proof Obligations

StackLab changes must keep these obligations green:

- `proof_matrix.yml` has no unintentional missing or partial rows;
- proof apps have deterministic provider-free baselines before live claims;
- receipts state proof posture and non-goals;
- scanner fixtures include positive and negative controls;
- no Regex usage in touched code/tests;
- no dynamic atom construction from runtime input;
- every proof worker or background process is supervised or test-owned.

## Secrets And Live Providers

StackLab does not store live secrets. Any proof command that calls GitHub or
Linear must be run with:

```bash
~/scripts/with_bash_secrets <command>
```

Live-provider receipts must record disposable object refs, cleanup evidence,
and what remains outside the claim. Deterministic proofs must not silently read
live environment variables.

## Tenant, Observability, And Replay

Proof receipts should carry tenant refs, authority refs, binding refs, lower
receipt refs, trace refs, redaction refs, and proof posture. AITrace fixture
exports are evidence inputs, not production audit truth unless a release claim
explicitly upgrades that posture.

## Documentation Checks

After doc edits, run:

```bash
test -f README.md
find guides -maxdepth 1 -type f -name '*.md' -print | sort
git diff --check -- README.md guides
```
