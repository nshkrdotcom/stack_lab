defmodule StackLab.MemsimHarness.Phase7EvidenceReportTest do
  use ExUnit.Case, async: true

  alias StackLab.MemsimHarness

  @proof_kinds ~w(audit invalidate promote recall share_up write_private)
  @scenario_refs ~w(
    s700_multi_node_epoch_monotonicity_and_ordering
    s701_access_graph_epoch_and_views
    s702_memory_tier_constraints
    s703_recall_accessibility
    s704_private_write_and_share_up
    s705_promotion_to_governed
    s706_invalidation_and_post_revocation
    s707_retrospective_audit_replay
    s708_citadel_authority_graph_integration
    s709_appkit_memory_control
    s710_no_bypass_memory
    s711_policy_version_and_transform_drift
    s712_release_evidence_report
  )

  @source_commits %{
    stack_lab: "71f2f64290e5da88d76927dbf1969a226d739220",
    jido_integration: "2272b9f112795c32e089ad293b749e4fb5a5e289",
    mezzanine: "247045be4013c028a3a6411e5492d98d961ade77",
    outer_brain: "05ae0e6ff114a9f145c97987113a2cc88388967e",
    app_kit: "64842d17144b239a458f0038fbb043a749ec8b3f",
    citadel: "8f51221a3a7b3846ba82d07368a358d1376f4875",
    aitrace: "4c6dd67f4156fa95553a9acd5730a4a8a45a1dfa"
  }

  test "builds the final Phase 7 evidence report shape from the invariant report" do
    report = report!()

    assert :ok = MemsimHarness.validate_phase7_evidence_report(report)

    assert Map.keys(report["stacklab_invariants"]["scenario_refs"]) == @scenario_refs
    assert report["stacklab_invariants"]["passed"] == true
    refute Map.has_key?(report["proof_tokens"], "ordering_refs")

    assert proof_kinds(report["multinode"]["commit_lsn_refs"]) == @proof_kinds
    assert proof_kinds(report["multinode"]["commit_hlc_refs"]) == @proof_kinds
    assert proof_kinds(report["multinode"]["snapshot_epoch_refs"]) == @proof_kinds
    assert proof_kinds(report["lineage"]["trace_join_refs"]) == @proof_kinds

    assert Enum.all?(report["source_repos"], & &1["pushed"])
    assert [_ | _] = report["lineage"]["parent_link_refs"]
    assert [_ | _] = report["lineage"]["source_lineage_refs"]
    assert [_ | _] = report["lineage"]["access_projection_hash_refs"]
  end

  test "rejects missing release evidence, duplicate ordering refs, and unknown properties" do
    report = report!()

    missing_snapshot_refs = put_in(report, ["multinode", "snapshot_epoch_refs"], [])

    assert {:error, {:multinode, {:empty, "snapshot_epoch_refs"}}} =
             MemsimHarness.validate_phase7_evidence_report(missing_snapshot_refs)

    duplicate_ordering_refs = put_in(report, ["proof_tokens", "ordering_refs"], [])

    assert {:error, {:unknown_properties, ["proof_tokens"], ["ordering_refs"]}} =
             MemsimHarness.validate_phase7_evidence_report(duplicate_ordering_refs)

    cleanup_failed = put_in(report, ["cleanup", "status"], "fail")

    assert {:error, {:cleanup, :not_passed}} =
             MemsimHarness.validate_phase7_evidence_report(cleanup_failed)

    stale_policy_negative_missing =
      update_in(report, ["negative_evidence"], &Map.delete(&1, "stale_policy_rejection"))

    assert {:error, {:negative_evidence, {:missing, ["stale_policy_rejection"]}}} =
             MemsimHarness.validate_phase7_evidence_report(stale_policy_negative_missing)
  end

  defp report! do
    assert {:ok, report} =
             MemsimHarness.phase7_evidence_report(
               tenant_ref: "tenant://phase7/m16",
               seed: 716,
               source_commits: @source_commits
             )

    report
  end

  defp proof_kinds(refs) do
    refs
    |> Enum.map(& &1["proof_kind"])
    |> Enum.sort()
  end
end
