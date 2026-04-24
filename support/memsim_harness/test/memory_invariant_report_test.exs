defmodule StackLab.MemsimHarness.MemoryInvariantReportTest do
  use ExUnit.Case, async: true

  alias StackLab.MemsimHarness

  @required_scenarios Enum.to_list(700..712)
  @required_invariants ~w(11.0 11.1 11.2 11.3 11.4 11.5 11.6 11.7 11.8 11.9 11.10)
  @required_proof_kinds [:audit, :invalidate, :promote, :recall, :share_up, :write_private]
  @source_commits %{
    stack_lab: "4a39ec1097c28892fdfd18d3a8044999fc3415ef",
    jido_integration: "fb3dd263dad38911ab73adeb2f3905c6e5d69e44",
    mezzanine: "247045be4013c028a3a6411e5492d98d961ade77",
    outer_brain: "05ae0e6ff114a9f145c97987113a2cc88388967e",
    app_kit: "64842d17144b239a458f0038fbb043a749ec8b3f",
    citadel: "8f51221a3a7b3846ba82d07368a358d1376f4875",
    aitrace: "4c6dd67f4156fa95553a9acd5730a4a8a45a1dfa"
  }

  test "memory invariant scenario catalog covers Phase 7 scenarios 700 through 712" do
    scenarios = MemsimHarness.memory_invariant_scenarios()

    assert Enum.map(scenarios, & &1.id) == @required_scenarios
    assert Enum.all?(scenarios, & &1.local_only?)
    refute Enum.any?(scenarios, & &1.release_evidence?)

    scenario_709 = Enum.find(scenarios, &(&1.id == 709))
    scenario_712 = Enum.find(scenarios, &(&1.id == 712))

    assert :app_kit in scenario_709.owner_repos
    assert :stack_lab in scenario_712.owner_repos
    assert :evidence_report_validation in scenario_712.evidence_classes
  end

  test "memory invariant report composes required inputs without claiming release evidence" do
    report = report!()

    assert report.local_only?
    refute report.release_evidence?
    assert report.source_commits == @source_commits
    assert Enum.map(report.scenarios, & &1.id) == @required_scenarios
    assert Enum.map(report.invariants, & &1.id) == @required_invariants

    assert report.required_report_inputs.proof_token_kinds |> Enum.sort() ==
             Enum.sort(@required_proof_kinds)

    assert length(report.required_report_inputs.proof_tokens) >= length(@required_proof_kinds)
    assert length(report.required_report_inputs.source_node_ordering_refs) >= 2
    assert [_ | _] = report.required_report_inputs.snapshot_epoch_refs
    assert [_ | _] = report.required_report_inputs.invalidation_refs
    assert [_ | _] = report.required_report_inputs.outer_brain_provenance_refs
    assert [_ | _] = report.required_report_inputs.mezzanine_decision_refs
    assert [_ | _] = report.required_report_inputs.jido_derived_state_attachment_refs
    assert [_ | _] = report.required_report_inputs.appkit_memory_control_dto_refs
    assert [_ | _] = report.required_report_inputs.aitrace_refs

    assert "AppKit.MemoryFragmentProjection.v1" in report.owner_evidence.app_kit.dto_contracts
    assert report.owner_evidence.app_kit.unknown_staleness_red_indicator?

    assert :ok = MemsimHarness.validate_memory_invariant_report(report)
  end

  test "validator rejects missing invariant, proof family, release claim, and order gaps" do
    report = report!()

    missing_invariant =
      update_in(report.invariants, &Enum.reject(&1, fn invariant -> invariant.id == "11.8" end))

    assert {:error, {:invariants, {:missing, ["11.8"]}}} =
             MemsimHarness.validate_memory_invariant_report(missing_invariant)

    missing_proof_family =
      update_in(report.required_report_inputs.proof_tokens, fn tokens ->
        Enum.reject(tokens, &(&1.proof_kind == :promote))
      end)

    assert {:error, {:proof_tokens, {:missing_families, [:promote]}}} =
             MemsimHarness.validate_memory_invariant_report(missing_proof_family)

    release_claim = %{report | local_only?: false, release_evidence?: true}

    assert {:error, {:release_evidence, :claimed_before_owner_gates}} =
             MemsimHarness.validate_memory_invariant_report(release_claim)

    missing_order =
      update_in(report.required_report_inputs.proof_tokens, fn [first | rest] ->
        [%{first | commit_lsn: nil} | rest]
      end)

    assert {:error, {:proof_tokens, :missing_order_evidence}} =
             MemsimHarness.validate_memory_invariant_report(missing_order)
  end

  test "no-bypass invariant records direct-store negatives and scan evidence" do
    report = report!()
    no_bypass = invariant!(report, "11.10")

    assert no_bypass.scenario_id == 710

    assert no_bypass.forbidden_codepaths == [
             :product_direct_memory_store_import,
             :outer_brain_direct_tier_write,
             :sidecar_direct_tier_read,
             :memory_governed_write_outside_promotion_coordinator
           ]

    assert Enum.map(no_bypass.negative_fixtures, & &1.reason) == [
             :direct_store_import,
             :outer_brain_tier_write,
             :sidecar_store_subscription,
             :governed_write_bypass
           ]

    assert Enum.all?(no_bypass.negative_fixtures, & &1.rejected?)
    assert no_bypass.no_bypass_scan.product_code_direct_store_imports == 0
    assert no_bypass.no_bypass_scan.outer_brain_direct_tier_writes == 0
    assert no_bypass.no_bypass_scan.memory_governed_bypass_writes == 0
  end

  test "multi-node negative drills fail closed or reconcile before serving" do
    report = report!()

    assert Enum.map(report.multi_node_negative_drills, & &1.reason) == [
             :stale_graph_invalidation,
             :partitioned_node_recall,
             :wall_clock_inversion,
             :policy_cache_stale_reuse
           ]

    assert Enum.all?(report.multi_node_negative_drills, fn drill ->
             drill.rejected? or drill.fail_closed? or drill.reconciled_before_serving?
           end)

    wall_clock_inversion =
      Enum.find(report.multi_node_negative_drills, &(&1.reason == :wall_clock_inversion))

    assert wall_clock_inversion.ordering_source == :commit_lsn_and_hlc
    assert wall_clock_inversion.wall_clock_order_rejected?
  end

  test "runtime envelope and cleanup evidence cover the composed report" do
    report = report!()

    assert report.runtime_envelope.scenario_count == length(@required_scenarios)
    assert report.runtime_envelope.invariant_count == length(@required_invariants)
    assert report.runtime_envelope.proof_token_family_count == length(@required_proof_kinds)
    assert report.runtime_envelope.node_count >= 2
    assert report.cleanup.leaves_tracked_artifacts? == false
    assert report.cleanup.validation_ref == "scenario://phase7/712/evidence-report-validation"

    dirty_cleanup = put_in(report.cleanup.leaves_tracked_artifacts?, true)

    assert {:error, {:cleanup, :tracked_artifacts_claimed}} =
             MemsimHarness.validate_memory_invariant_report(dirty_cleanup)
  end

  defp report! do
    assert {:ok, report} =
             MemsimHarness.run_memory_invariants(
               tenant_ref: "tenant://phase7/m14",
               seed: 714,
               source_commits: @source_commits
             )

    report
  end

  defp invariant!(report, id) do
    Enum.find(report.invariants, &(&1.id == id)) || flunk("missing invariant #{id}")
  end
end
