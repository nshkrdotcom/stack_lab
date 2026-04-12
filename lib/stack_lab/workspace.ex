defmodule StackLab.Workspace do
  @moduledoc """
  Root helpers for the StackLab workspace.
  """

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

  @spec active_project_globs() :: [String.t()]
  def active_project_globs, do: @active_project_globs

  @spec package_paths() :: [String.t()]
  def package_paths, do: @package_paths
end
