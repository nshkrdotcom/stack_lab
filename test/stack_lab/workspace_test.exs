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
    assert "examples/lower_facts_roundtrip" in package_paths
    assert "examples/outer_brain_restart_durability" in package_paths
    assert "examples/semantic_host_roundtrip" in package_paths
    assert "examples/typed_host_roundtrip" in package_paths
    assert "examples/multi_node_roundtrip" in package_paths
    assert "examples/restart_authority_drill" in package_paths
    assert "examples/governed_run_roundtrip" in package_paths
    assert "examples/session_lineage_drill" in package_paths
    assert "examples/pressure_failover_drill" in package_paths
  end

  test "uses the released Weld 0.7.1 line directly" do
    assert {:weld, "~> 0.7.1", runtime: false} in MixProject.project()[:deps]
  end

  test "uses Weld task autodiscovery instead of local release aliases" do
    aliases = MixProject.project()[:aliases]

    for alias_name <- [
          :"weld.inspect",
          :"weld.graph",
          :"weld.project",
          :"weld.verify",
          :"weld.release.prepare",
          :"weld.release.track",
          :"weld.release.archive",
          :"release.prepare",
          :"release.track",
          :"release.archive"
        ] do
      refute Keyword.has_key?(aliases, alias_name)
    end
  end
end
