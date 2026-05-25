# StackLab Gn-Ten Node Lab

`support/gn_ten_node_lab` is StackLab's generic local BEAM node orchestration
support package for gn-ten distributed proofs.

It owns local test-harness mechanics:

- topology spec parsing and validation;
- node cap enforcement;
- EPMD and shortname controller startup;
- redacted per-run cookie generation;
- peer node lifecycle;
- code-path sync in dev peer mode;
- bounded `:erpc` admin/proof calls;
- node cleanup receipts.

It does not own AppKit, Mezzanine, Citadel, OuterBrain, Jido Integration,
Execution Plane, AITrace, TRINITY, GEPA, or product business semantics.

## Security Posture

Default Erlang distribution cookies are local development cluster authority,
not product, tenant, user, or production security authority. Receipts generated
by this package redact cookie values and record production security as a
non-claim.

## QC

```bash
mix test
mix format --check-formatted
mix credo --strict
```
