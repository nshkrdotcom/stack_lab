defmodule StackLab.Build.WorkspaceContract do
  @moduledoc false

  @package_paths [
    "support/lab_core",
    "support/spec_cell",
    "support/gn_ten_control_plane",
    "support/connector_hardening_scanner",
    "support/tenant_isolation_scanner",
    "support/no_bypass_scanner",
    "support/memory_fabric_scanner",
    "support/model_inference_scanner",
    "support/optimization_fabric_scanner",
    "support/coordination_fabric_scanner",
    "support/ai_run_lineage_scanner",
    "support/drift_detector",
    "support/citadel_spine_harness",
    "support/memsim_harness",
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
    "examples/gepa_platform_roundtrip",
    "examples/trinity_platform_roundtrip",
    "examples/skill_roundtrip",
    "examples/hive_roundtrip"
  ]

  @active_project_globs [".", "support/*", "examples/*"]

  @spec package_paths() :: [String.t()]
  def package_paths, do: @package_paths

  @spec active_project_globs() :: [String.t()]
  def active_project_globs, do: @active_project_globs
end
