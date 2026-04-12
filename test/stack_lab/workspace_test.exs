defmodule StackLab.WorkspaceTest do
  use ExUnit.Case, async: true

  test "workspace exposes the expected project globs" do
    assert StackLab.Workspace.active_project_globs() == [".", "support/*", "examples/*"]
  end

  test "workspace package paths cover support and examples" do
    package_paths = StackLab.Workspace.package_paths()

    assert "support/lab_core" in package_paths
    assert "support/citadel_spine_harness" in package_paths
    assert "examples/single_node_roundtrip" in package_paths
    assert "examples/multi_node_roundtrip" in package_paths
    assert "examples/restart_authority_drill" in package_paths
    assert "examples/governed_run_roundtrip" in package_paths
    assert "examples/session_lineage_drill" in package_paths
    assert "examples/pressure_failover_drill" in package_paths
  end
end
