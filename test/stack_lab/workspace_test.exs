defmodule StackLab.WorkspaceTest do
  use ExUnit.Case, async: true

  alias StackLab.Workspace.MixProject

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

  test "uses the released Weld 0.7.0 line directly" do
    assert {:weld, "~> 0.7.0", runtime: false} in MixProject.project()[:deps]
  end

  test "exposes the release aliases for projection tracking" do
    aliases = MixProject.project()[:aliases]

    assert Keyword.fetch!(aliases, :"release.prepare") == ["weld.release.prepare"]
    assert Keyword.fetch!(aliases, :"release.track") == ["weld.release.track"]
    assert Keyword.fetch!(aliases, :"release.archive") == ["weld.release.archive"]
  end
end
