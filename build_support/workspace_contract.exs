defmodule StackLab.Build.WorkspaceContract do
  @moduledoc false

  @package_paths [
    "support/lab_core",
    "support/citadel_spine_harness",
    "examples/single_node_roundtrip",
    "examples/lower_facts_roundtrip",
    "examples/semantic_host_roundtrip",
    "examples/typed_host_roundtrip",
    "examples/multi_node_roundtrip",
    "examples/restart_authority_drill",
    "examples/governed_run_roundtrip",
    "examples/session_lineage_drill",
    "examples/pressure_failover_drill"
  ]

  @active_project_globs [".", "support/*", "examples/*"]

  @spec package_paths() :: [String.t()]
  def package_paths, do: @package_paths

  @spec active_project_globs() :: [String.t()]
  def active_project_globs, do: @active_project_globs
end
