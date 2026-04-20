# Monorepo Project Map

- `./examples/governed_run_roundtrip/mix.exs`: Governed-run proving example for StackLab
- `./examples/lower_facts_roundtrip/mix.exs`: Substrate-facing lower-facts proving example for StackLab
- `./examples/mezzanine_restart_recovery/mix.exs`: Stage-2 restart-recovery proof for the neutral Mezzanine substrate
- `./examples/multi_node_roundtrip/mix.exs`: Multi-node proving example for StackLab
- `./examples/outer_brain_restart_durability/mix.exs`: Stage-1 durable restart-authority proof for OuterBrain
- `./examples/pressure_failover_drill/mix.exs`: Pressure and failover proving example for StackLab
- `./examples/restart_authority_drill/mix.exs`: Restart-authority proving example for StackLab
- `./examples/semantic_host_roundtrip/mix.exs`: Semantic host proving example above the lower seam
- `./examples/session_lineage_drill/mix.exs`: Session-lineage proving example for StackLab
- `./examples/single_node_roundtrip/mix.exs`: Single-node proving example for StackLab
- `./examples/typed_host_roundtrip/mix.exs`: Typed host proving example for AppKit and Citadel.DomainSurface
- `./mix.exs`: Tooling root for the StackLab non-umbrella monorepo
- `./support/citadel_spine_harness/mix.exs`: Harness-only assembly package for Citadel and Jido Integration proofs
- `./support/lab_core/mix.exs`: Shared harness helpers for the StackLab workspace

# AGENTS.md

## Temporal developer environment

Temporal CLI is implicitly available on this workstation as `temporal` for local durable-workflow development. Do not make repo code silently depend on that implicit machine state; prefer explicit scripts, documented versions, and README-tracked ergonomics work.

## Native Temporal development substrate

When Temporal runtime behavior is required, use the stack substrate in `/home/home/p/g/n/mezzanine`:

```bash
just dev-up
just dev-status
just dev-logs
just temporal-ui
```

Do not invent raw `temporal server start-dev` commands for normal work. Do not reset local Temporal state unless the user explicitly approves `just temporal-reset-confirm`.
