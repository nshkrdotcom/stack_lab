# Env Remediation Harness

`StackLab.Examples.EnvRemediationHarness` records environment and ambient-auth
cleanup evidence for the ENV phase sequence.

## Phase

Owner phase: ENV-01 through ENV-35.

## Contract

The harness scans source text for fixed env and ambient-auth tokens, records
redacted findings with bounded cleanup and production classifications, blocks
unresolved governed hot-path findings, and emits SpecCell plus gn-ten receipt
records for the target repo.

Receipts never include raw env values, provider payloads, token text, or source
line excerpts. They carry owner repo, path, line, fixed token id,
classification, production class, proof command, and receipt path.

## QC

```bash
mix test
mix format --check-formatted
```
