defmodule StackLab.WorkspaceTest do
  use ExUnit.Case, async: true

  alias StackLab.Workspace.MixProject

  test "workspace exposes the expected project globs" do
    assert StackLab.Workspace.active_project_globs() == [".", "support/*", "examples/*"]
  end

  test "workspace package paths cover support and examples" do
    package_paths = StackLab.Workspace.package_paths()

    assert "support/lab_core" in package_paths
    assert "support/spec_cell" in package_paths
    assert "support/gn_ten_control_plane" in package_paths
    assert "support/citadel_spine_harness" in package_paths
    assert "support/model_inference_scanner" in package_paths
    assert "support/optimization_fabric_scanner" in package_paths
    assert "support/coordination_fabric_scanner" in package_paths
    assert "support/cost_budget_scanner" in package_paths
    assert "support/adaptive_control_scanner" in package_paths
    assert "support/ai_run_lineage_scanner" in package_paths
    assert "examples/single_node_roundtrip" in package_paths
    assert "examples/lower_facts_roundtrip" in package_paths
    assert "examples/outer_brain_restart_durability" in package_paths
    assert "examples/mezzanine_restart_recovery" in package_paths
    assert "examples/semantic_host_roundtrip" in package_paths
    assert "examples/typed_host_roundtrip" in package_paths
    assert "examples/multi_node_roundtrip" in package_paths
    assert "examples/restart_authority_drill" in package_paths
    assert "examples/governed_run_roundtrip" in package_paths
    assert "examples/governed_provider_roundtrip" in package_paths
    assert "examples/atom_cleanup_harness" in package_paths
    assert "examples/session_lineage_drill" in package_paths
    assert "examples/pressure_failover_drill" in package_paths
    assert "examples/deployment_receipts_drill" in package_paths
    assert "examples/gepa_platform_roundtrip" in package_paths
    assert "examples/trinity_platform_roundtrip" in package_paths
    assert "examples/adaptive_control_roundtrip" in package_paths
    assert "examples/skill_roundtrip" in package_paths
    assert "examples/hive_roundtrip" in package_paths
  end

  test "uses the released Weld 0.7.2 line directly" do
    assert {:weld, "~> 0.7.2", runtime: false} in MixProject.project()[:deps]
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

  test "runs package tests with workspace parallelism" do
    workspace = MixProject.project()[:blitz_workspace]

    assert get_in(workspace, [:parallelism, :base, :test]) == 3
    assert get_in(workspace, [:parallelism, :overrides]) == []
    assert Blitz.MixWorkspace.max_concurrency(workspace, :test) > 1
  end
end
