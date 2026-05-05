# Governed Provider Roundtrip

`StackLab.Examples.GovernedProviderRoundtrip` records Phase 15 proof for
governed provider dispatch across CLI, HTTP, GraphQL, realtime, and inference
families.

## Phase

Owner phase: Phase 15 and Phase 16.

## Contract

The package proves that governed dispatch uses central refs for provider
accounts, credential handles, leases, native assertions, connector bindings,
target grants, trace refs, and idempotency refs. It separately records
standalone compatibility and promotion evidence, live-provider disposable
credential readiness, cleanup posture, SpecCell rows, and gn-ten receipts.

Missing disposable live-provider inputs are release-blocking open defects.
Receipts never include raw credential values, token text, local private auth
paths, source excerpts, provider payloads, or normal user auth roots.

## QC

```bash
mix test
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix docs --warnings-as-errors
```
