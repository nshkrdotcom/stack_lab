# Layout

The workspace is organized as:

- `build_support/`
  - workspace and weld contracts
- `tools/`
  - compose, fault-injection, and OTLP configs
- `support/lab_core/`
  - shared harness helpers
- `support/spec_cell/`
  - executable requirement cells for release gates
- `support/gn_ten_control_plane/`
  - bounded gn-ten receipt records for release gates
- `support/citadel_spine_harness/`
  - harness-only sibling assembly for `citadel -> jido_integration`
- `support/memsim_harness/`
  - Phase 7 governed-memory substrate simulations
- `support/model_inference_scanner/`
  - governed model profile and endpoint profile checks
- `support/optimization_fabric_scanner/`
  - GEPA candidate, eval, promotion, budget, trace, and rollback checks
- `support/ai_run_lineage_scanner/`
  - adaptive AI run lineage and required-ref checks
- `examples/`
  - first-class proving projects
  - `single_node_roundtrip`
  - `outer_brain_restart_durability`
  - `mezzanine_restart_recovery`
  - `multi_node_roundtrip`
  - `restart_authority_drill`
  - `atom_cleanup_harness`
  - `pressure_failover_drill`
  - `gepa_platform_roundtrip`
- `packaging/`
  - weld verification support

The examples are versioned workspace members, not ad hoc scripts.
