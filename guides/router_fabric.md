# Router Fabric Proofs

StackLab proves routing and optimization substrates through owner-defined
adapter contracts. It does not own route selection, optimization math, or model
execution semantics.

## Adapter Path

- `Trinity.MezzanineRouterAdapter` implements
  `Mezzanine.AIExecution.RouterAdapter`.
- `GEPA.MezzanineOptimizerAdapter` implements
  `Mezzanine.AIExecution.OptimizerAdapter`.
- Mezzanine owns workflow truth and projection reduction.
- AppKit owns product-safe route and optimization projections.

## Required Evidence

Router proofs record route decision refs, candidate refs, eval refs, cost
summaries, promotion posture, rollback posture, and no direct product access to
lower repos.

## Local QC

```bash
mix test examples/trinity_platform_roundtrip
mix test examples/gepa_platform_roundtrip
mix gn_ten.proofs.validate --json
```

For JSON receipts that are redirected or parsed by automation, precompile the
proof package first. A cold Mix invocation may print dependency compilation
lines before the task runs, so the release-readiness command shape is:

```bash
cd examples/nshkr_router_fabric_roundtrip
MIX_ENV=test mix deps.get
MIX_ENV=test mix compile --quiet
MIX_ENV=test mix stack_lab.nshkr.router_fabric.roundtrip --json > /tmp/router_fabric_receipt.json
jq -e '.status == "pass" and .scanner_receipts.router_fabric.status == "pass"' /tmp/router_fabric_receipt.json
```
