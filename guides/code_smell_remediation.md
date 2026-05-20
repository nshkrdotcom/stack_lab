# StackLab Code Smell Remediation

This guide records the repo-local implementation posture after the GN-TEN code
smell remediation pass.

## What Changed

- Shared command execution now routes through `StackLab.CommandRunner`.
- Application-env mutation routes through `StackLab.AppEnvSandbox`.
- Structural scanner roles are split into traversal, zones, rules, allowlists,
  proof bundles, and receipts.
- `ToyDocumentReview` and Citadel spine proof surfaces are split into focused
  proof modules and scenario modules.
- Harness timing waits use `StackLab.CitadelSpineHarness.Timing`; raw sleeps
  are centralized behind named delay/soak/retry/await calls.

## Maintainer Rules

- StackLab proves cross-repo claims from outside the product and lower owners.
- It should not become the owner of product behavior, provider behavior,
  authority truth, connector truth, or lower runtime truth.
- Scanner behavior must be frozen by tests before scanner internals are
  refactored.

## QC

Use the repo root gate:

```bash
mix ci
```
