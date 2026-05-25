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
