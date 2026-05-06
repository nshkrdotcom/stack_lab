defmodule StackLab.CoordinationFabricScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.CoordinationFabricScanner

  test "passes complete governed coordination facts" do
    assert {:ok, receipt} =
             CoordinationFabricScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/coordination_engine",
               coordination_facts: [complete_fact()]
             })

    assert receipt.status == :pass
    assert receipt.fixture_refs == ["AOC-026", "AOC-043"]
    assert receipt.findings == []
  end

  test "requires router, calibration, role, provider pool, inference, verifier, handoff, trace, and replay refs" do
    assert {:ok, receipt} =
             CoordinationFabricScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/coordination_engine",
               coordination_facts: [%{}]
             })

    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.rule) == [
             :router_artifact_refs,
             :router_eval_refs,
             :calibration_refs,
             :drift_detection_refs,
             :parity_check_refs,
             :role_prompt_refs,
             :provider_pool_refs,
             :governed_inference_boundary_ref,
             :verifier_refs,
             :handoff_scope_ref,
             :trace_refs,
             :replay_refs
           ]
  end

  test "rejects raw coordination payloads and unredacted trace posture" do
    fact =
      complete_fact()
      |> Map.put(:trace_redaction, :raw)
      |> Map.put(:provider_payload, %{body: "hidden"})

    assert {:ok, receipt} =
             CoordinationFabricScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/coordination_engine",
               coordination_facts: [fact]
             })

    assert has_finding?(receipt, :trace_refs, :trace_refs_not_redacted)

    assert has_finding?(receipt, :raw_payload, {:forbidden_raw_field, :provider_payload})
  end

  defp has_finding?(receipt, rule, reason) do
    Enum.any?(receipt.findings, fn finding ->
      finding.rule == rule and finding.reason == reason
    end)
  end

  defp complete_fact do
    %{
      router_artifact_refs: ["router://mock"],
      router_eval_refs: ["router-eval://golden"],
      calibration_refs: ["calibration://router/threshold"],
      drift_detection_refs: ["drift://router/window"],
      parity_check_refs: ["parity://qwen-sakana"],
      role_prompt_refs: ["prompt://role/worker"],
      provider_pool_refs: ["provider-pool://mock"],
      governed_inference_boundary_ref: "inference-boundary://governed/mock",
      verifier_refs: ["verifier-result://pass"],
      handoff_scope_ref: "handoff-scope://worker/reviewer",
      trace_refs: ["trace://trinity/demo"],
      replay_refs: ["replay://trinity/demo"],
      trace_redaction: :redacted
    }
  end
end
