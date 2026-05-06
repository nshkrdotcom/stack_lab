defmodule StackLab.AdaptiveControlScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.AdaptiveControlScanner

  test "passes complete adaptive-control facts" do
    assert {:ok, receipt} =
             AdaptiveControlScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/adaptive_control_engine",
               adaptive_control_facts: [complete_fact()]
             })

    assert receipt.status == :pass
    assert receipt.fixture_refs == ["AOC-040"]
    assert receipt.findings == []
  end

  test "requires trace, dataset, candidate, gate, promotion, rollback, stale rejection, projection, and receipt refs" do
    assert {:ok, receipt} =
             AdaptiveControlScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/adaptive_control_engine",
               adaptive_control_facts: [%{}]
             })

    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.rule) == [
             :trinity_trace_refs,
             :eval_dataset_refs,
             :replay_dataset_refs,
             :gepa_target_refs,
             :candidate_refs,
             :shadow_gate_refs,
             :canary_gate_refs,
             :approval_refs,
             :promotion_refs,
             :rollback_refs,
             :stale_artifact_rejection_refs,
             :appkit_projection_refs,
             :receipt_refs
           ]
  end

  test "rejects raw adaptive-control payloads and unredacted trace posture" do
    fact =
      complete_fact()
      |> Map.put(:trace_redaction, :raw)
      |> Map.put(:provider_payload, %{body: "hidden"})

    assert {:ok, receipt} =
             AdaptiveControlScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/adaptive_control_engine",
               adaptive_control_facts: [fact]
             })

    assert has_finding?(receipt, :trinity_trace_refs, :trace_refs_not_redacted)
    assert has_finding?(receipt, :raw_payload, {:forbidden_raw_field, :provider_payload})
  end

  defp has_finding?(receipt, rule, reason) do
    Enum.any?(receipt.findings, fn finding ->
      finding.rule == rule and finding.reason == reason
    end)
  end

  defp complete_fact do
    %{
      trinity_trace_refs: ["trace://trinity/repair"],
      eval_dataset_refs: ["eval-dataset://trinity/repair"],
      replay_dataset_refs: ["replay-dataset://trinity/repair"],
      gepa_target_refs: ["gepa-target://role-prompt"],
      candidate_refs: ["candidate://role-worker/v2"],
      shadow_gate_refs: ["shadow://candidate/worker/v2"],
      canary_gate_refs: ["canary://candidate/worker/v2"],
      approval_refs: ["approval://operator/worker/v2"],
      promotion_refs: ["promotion://candidate/worker/v2"],
      rollback_refs: ["rollback://candidate/worker/v1"],
      stale_artifact_rejection_refs: ["stale-rejection://candidate/worker/v1"],
      appkit_projection_refs: ["appkit://adaptive-control/worker"],
      receipt_refs: ["adaptive-control-receipt://worker"],
      trace_redaction: :redacted
    }
  end
end
