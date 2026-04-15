# Layout

The workspace is organized as:

- `build_support/`
  - workspace and weld contracts
- `tools/`
  - compose, fault-injection, and OTLP configs
- `support/lab_core/`
  - shared harness helpers
- `support/citadel_spine_harness/`
  - harness-only sibling assembly for `citadel -> jido_integration`
- `examples/`
  - first-class proving projects
  - `single_node_roundtrip`
  - `outer_brain_restart_durability`
  - `multi_node_roundtrip`
  - `restart_authority_drill`
  - `pressure_failover_drill`
- `packaging/`
  - weld verification support

The examples are versioned workspace members, not ad hoc scripts.
