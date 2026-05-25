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
- checked-in topology fixture loading;
- required app boot probes;
- owner-defined facade host and `:pg` readiness checks;
- JSON admin receipts for `preflight`, `up`, `status`, `probe`, `attach`, and
  `down`;
- distributed envelope scanning for tenant, authority, trace, idempotency,
  payload-mode, redaction, local-term, raw-payload, cross-tenant, stale-schema,
  and direct-lower-import defects;
- node cleanup receipts.

It does not own AppKit, Mezzanine, Citadel, OuterBrain, Jido Integration,
Execution Plane, AITrace, TRINITY, GEPA, or product business semantics.

## Topology Fixtures

Temporary v2 topology fixtures live under `priv/topologies/` until
`examples/gn_ten_distributed_stack` exists:

- `control_3_node.exs`
- `context_6_node.exs`
- `fixture_single_node.exs`

These fixtures name owner facade modules and owner-defined `:pg` groups. The
node lab can host those modules on peer nodes for readiness proof, but StackLab
does not define the domain contract.

## Admin Commands

Root StackLab Mix tasks delegate into this package:

```bash
mix stack_lab.gn_ten.node_lab.preflight --json
mix stack_lab.gn_ten.node_lab.up \
  --topology support/gn_ten_node_lab/priv/topologies/fixture_single_node.exs \
  --json
mix stack_lab.gn_ten.node_lab.status --json
mix stack_lab.gn_ten.node_lab.probe --node fixture_profile_0 --json
mix stack_lab.gn_ten.node_lab.attach --node fixture_profile_0 --json
mix stack_lab.gn_ten.node_lab.down --json
```

Phase 6 peer mode starts peers, validates app and facade readiness, writes a
run-state receipt, and cleans up peers before returning. `--keep` is accepted
and recorded as an explicit intent, but cross-command peer retention is not a
v2 Phase 6 claim. A later daemon or release-path controller must own that
stronger claim.

`status` returns a debug summary with node ids, profile names, node names,
started apps, owner `:pg` membership, facade readiness, log path, latest
receipt refs, cleanup posture, and artifact hygiene. `attach` prints a
redacted local debug-shell recipe for a logical node. It intentionally omits
the Erlang cookie value and records that Phase 15 does not prove production
security or cross-command peer retention.

## Distributed Envelope Scanner

The package exposes `StackLab.GnTenNodeLab.scan_envelope/2` and
`scan_envelopes/2`. The scanner validates only boundary hygiene; owner repos
remain responsible for domain semantics.

It fails:

- missing schema, tenant, authority, trace, idempotency, source node,
  payload-mode, redaction, correlation, target profile, or issue time fields;
- stale schema versions when supported versions are supplied;
- cross-tenant read hints;
- raw prompt/memory/provider/secret payload fields;
- local-only runtime terms such as PIDs, ports, references, and functions;
- direct lower-import or bypass hints.

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
