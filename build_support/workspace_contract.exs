defmodule StackLab.Build.WorkspaceContract do
  @moduledoc false

  @package_paths [
    "support/lab_core",
    "support/spec_cell",
    "support/gn_ten_control_plane",
    "support/gn_ten_node_lab",
    "support/connector_hardening_scanner",
    "support/tenant_isolation_scanner",
    "support/no_bypass_scanner",
    "support/memory_fabric_scanner",
    "support/model_inference_scanner",
    "support/optimization_fabric_scanner",
    "support/coordination_fabric_scanner",
    "support/cost_budget_scanner",
    "support/context_abi_scanner",
    "support/router_fabric_scanner",
    "support/adaptive_control_scanner",
    "support/ai_run_lineage_scanner",
    "support/persistence_matrix_scanner",
    "support/drift_detector",
    "support/citadel_spine_harness",
    "support/memsim_harness",
    "bridges/stacklab_chassis_bridge",
    "examples/single_node_roundtrip",
    "examples/lower_facts_roundtrip",
    "examples/outer_brain_restart_durability",
    "examples/mezzanine_restart_recovery",
    "examples/semantic_host_roundtrip",
    "examples/typed_host_roundtrip",
    "examples/multi_node_roundtrip",
    "examples/restart_authority_drill",
    "examples/governed_run_roundtrip",
    "examples/governed_provider_roundtrip",
    "examples/atom_cleanup_harness",
    "examples/env_remediation_harness",
    "examples/session_lineage_drill",
    "examples/pressure_failover_drill",
    "examples/deployment_receipts_drill",
    "examples/guardrail_roundtrip",
    "examples/replay_roundtrip",
    "examples/cost_roundtrip",
    "examples/context_abi_roundtrip",
    "examples/gn_ten_distributed_stack",
    "examples/nshkr_router_fabric_roundtrip",
    "examples/toy_document_review",
    "examples/synapse_product_acceptance",
    "examples/gepa_platform_roundtrip",
    "examples/trinity_platform_roundtrip",
    "examples/trinity_single_node_roundtrip",
    "examples/trinity_parity_harness",
    "examples/adaptive_control_roundtrip",
    "examples/persistence_mode_roundtrip",
    "examples/skill_roundtrip",
    "examples/hive_roundtrip",
    "examples/agent_foundation_roundtrip"
  ]

  @active_project_globs [".", "support/*", "examples/*", "bridges/*"]

  @spec package_paths() :: [String.t()]
  def package_paths, do: @package_paths

  @spec active_project_globs() :: [String.t()]
  def active_project_globs, do: @active_project_globs
end
