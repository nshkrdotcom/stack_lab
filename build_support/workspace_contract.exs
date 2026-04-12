defmodule StackLab.Build.WorkspaceContract do
  @moduledoc false

  @package_paths [
    "support/lab_core",
    "support/citadel_spine_harness",
    "examples/single_node_roundtrip",
    "examples/multi_node_roundtrip",
    "examples/restart_authority_drill",
    "examples/governed_run_roundtrip",
    "examples/session_lineage_drill",
    "examples/pressure_failover_drill"
  ]

  @active_project_globs [".", "support/*", "examples/*"]

  def package_paths, do: @package_paths
  def active_project_globs, do: @active_project_globs
end
