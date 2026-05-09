defmodule StackLab.CitadelSpineHarness.Phase6EvidenceReportTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.Phase6EvidenceReport

  test "describes the Phase 6 evidence report validation release gate" do
    scenario = CitadelSpineHarness.phase6_evidence_report_scenario()

    assert scenario.name == :phase6_evidence_report_validation
    assert scenario.runbook == "evidence_report_validation.md"
    assert scenario.scenario == 611
    assert scenario.owner_repo == :stack_lab
    assert scenario.primary_repos == [:stack_lab, :AITrace]
    assert scenario.contract == "SimulationEvidenceReport.v1"
    assert scenario.schema_ref == "contracts/phase6_evidence_report.schema.json"

    assert scenario.cases == %{
             validated_report: %{
               kind: :validated_report,
               scenario: 611
             }
           }
  end

  test "generates a schema-valid report with owner evidence, AITrace receipts, and no raw payload" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase6_evidence_report(:validated_report)

    assert result.case == :validated_report
    assert result.contract == "SimulationEvidenceReport.v1"
    assert result.schema_ref == "contracts/phase6_evidence_report.schema.json"
    assert result.validation.status == :passed
    assert result.validation.schema_validation == :passed
    assert result.validation.aitrace_lineage_join == :passed

    report = result.report

    assert report["report_id"] == "phase6-m12-simulation-evidence-report"

    assert String.contains?(
             report["profile"]["service_profile_ref"],
             "ServiceSimulationProfile.v1"
           )

    assert String.contains?(report["profile"]["registry_entry_ref"], "profile-registry-entry://")
    assert report["profile"]["lower_scenario_refs"] != []

    assert Enum.any?(
             report["source_repos"],
             &(&1["repo"] == "stack_lab" and
                 &1["commit"] == "490feac6e000f07eb8f8d34339756fed5c00f58a" and
                 &1["pushed"])
           )

    assert Enum.any?(
             report["source_repos"],
             &(&1["repo"] == "AITrace" and
                 &1["commit"] == "ac3427c1f4a6741ca1a6544b6e2f4f442830aba8" and
                 &1["pushed"])
           )

    assert report["governed_workload"]["ingress_ref"] ==
             "app_kit_operator_surface_via_mezzanine_bridge"

    assert report["governed_workload"]["work_class_ref"] ==
             "stack_lab/work_classes/service_operations"

    assert report["governed_workload"]["pack_ref"] ==
             "mezzanine/packs/stack_lab_service_ops@1"

    assert "tenant:tenant-phase6-m8" in report["authority"]["tenant_refs"]
    assert report["authority"]["authority_decision_refs"] != []
    assert report["authority"]["authorization_scope_refs"] != []

    assert "temporal-worker://default/mezzanine.hazmat" in report["temporal"][
             "worker_health_refs"
           ]

    assert report["temporal"]["restart_replay_refs"] != []

    assert report["outer_brain"]["semantic_provenance_refs"] != []
    assert report["outer_brain"]["restart_refs"] != []

    assert Map.keys(report["provider_families"]) |> Enum.sort() == [
             "cli",
             "graphql",
             "rest",
             "self_hosted"
           ]

    assert report["no_egress"]["policy_ref"] == "no-egress://phase6/m12/report-validation"
    assert report["no_egress"]["positive_refs"] != []
    assert report["no_egress"]["negative_refs"] != []

    assert report["lineage"]["trace_refs"] != []
    assert report["lineage"]["aitrace_refs"] != []
    assert report["lineage"]["aitrace_receipt_refs"] != []
    assert String.contains?(report["lineage"]["join_ref"], "lineage-join://phase6/m12/")

    assert report["raw_payload_scan"]["status"] == "pass"
    assert report["cleanup"]["status"] == "pass"
    assert report["results"]["positive_evidence_refs"] != []
    assert report["results"]["negative_evidence_refs"] != []
    assert report["results"]["owner_evidence_refs"] != []

    refute raw_payload_present?(report)
    assert :ok = Phase6EvidenceReport.validate_report(report)
  end

  test "rejects reports missing authority, tenant, semantic, Temporal, no-egress, and owner proof" do
    report = Phase6EvidenceReport.valid_report()

    assert {:error, :missing_authority_evidence} =
             report
             |> put_in(["authority", "authority_decision_refs"], [])
             |> Phase6EvidenceReport.validate_report()

    assert {:error, :missing_tenant_evidence} =
             report
             |> put_in(["authority", "tenant_refs"], [])
             |> Phase6EvidenceReport.validate_report()

    assert {:error, :missing_semantic_provenance} =
             report
             |> put_in(["outer_brain", "semantic_provenance_refs"], [])
             |> Phase6EvidenceReport.validate_report()

    assert {:error, :missing_temporal_worker_evidence} =
             report
             |> put_in(["temporal", "worker_health_refs"], [])
             |> Phase6EvidenceReport.validate_report()

    assert {:error, :missing_no_egress_policy} =
             report
             |> put_in(["no_egress", "policy_ref"], "")
             |> Phase6EvidenceReport.validate_report()

    assert {:error, :local_only_owner_evidence} =
             report
             |> put_in(["source_repos", Access.at(0), "pushed"], false)
             |> Phase6EvidenceReport.validate_report()
  end

  test "rejects raw payload leaks and schema-invalid report shapes" do
    report = Phase6EvidenceReport.valid_report()

    assert {:error, {:raw_payload_leak, ["results", "positive_evidence_refs", 0]}} =
             report
             |> put_in(
               ["results", "positive_evidence_refs", Access.at(0)],
               "raw provider body leaked"
             )
             |> Phase6EvidenceReport.validate_report()

    assert {:error, {:schema_validation_failed, _details}} =
             report
             |> Map.put("unexpected_top_level", true)
             |> Phase6EvidenceReport.validate_report()
  end

  test "records required M12 negative validation failures" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase6_evidence_report(:validated_report)

    assert result.negative_failures.missing_authority == :missing_authority_evidence
    assert result.negative_failures.missing_tenant == :missing_tenant_evidence
    assert result.negative_failures.missing_semantic_provenance == :missing_semantic_provenance
    assert result.negative_failures.missing_temporal_worker == :missing_temporal_worker_evidence
    assert result.negative_failures.missing_no_egress == :missing_no_egress_policy

    assert result.negative_failures.raw_payload_leak ==
             {:raw_payload_leak, ["results", "positive_evidence_refs", 0]}

    assert result.negative_failures.local_only_proof == :local_only_owner_evidence
    assert result.negative_failures.missing_aitrace_receipt == :missing_aitrace_receipt
  end

  defp raw_payload_present?(term) when is_map(term) do
    Enum.any?(term, fn
      {key, _value} when key in ["raw_payload", "raw_prompt", "provider_body", "full_prompt"] ->
        true

      {_key, value} ->
        raw_payload_present?(value)
    end)
  end

  defp raw_payload_present?(term) when is_list(term), do: Enum.any?(term, &raw_payload_present?/1)

  defp raw_payload_present?(term) when is_binary(term) do
    term
    |> String.downcase()
    |> String.contains?("raw_payload")
  end

  defp raw_payload_present?(_term), do: false
end
