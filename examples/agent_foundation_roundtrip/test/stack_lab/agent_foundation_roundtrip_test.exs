defmodule StackLab.AgentFoundationRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.AgentFoundationRoundtrip

  test "deterministic proof covers the release acceptance matrix through AF-019" do
    assert {:ok, receipt} = AgentFoundationRoundtrip.run()

    assert receipt.status == :pass
    assert receipt.live_provider_required? == false
    assert receipt.acceptance["AF-001"].status == :pass
    assert receipt.acceptance["AF-019"].status == :pass
    assert receipt.acceptance["AF-020"].status == :deferred_to_phase_10
    assert receipt.mezzanine.seq_proof.strictly_monotonic? == true
    assert receipt.mezzanine.catch_up.lower_dispatch_count_delta == 0
    assert receipt.mezzanine.replay.lower_reexecution_allowed? == false
    assert receipt.mezzanine.replay.lower_dispatch_count_delta == 0
    assert receipt.jido.runtime_receipt["status"] == "succeeded"
    assert receipt.citadel.denial.no_jido_invocation? == true
    assert receipt.no_bypass.status == :pass
    assert receipt.no_bypass.ax_terms_rejected? == true
    assert receipt.no_bypass.a2a_terms_rejected? == true
  end

  test "fault receipts include the runbook failure cases" do
    assert {:ok, receipt} = AgentFoundationRoundtrip.run()

    ids = Enum.map(receipt.faults, & &1.scenario_id)

    assert ids == [
             "FI-001",
             "FI-002",
             "FI-003",
             "FI-004",
             "FI-005",
             "FI-006",
             "FI-007",
             "FI-008",
             "FI-009",
             "FI-010",
             "FI-011",
             "FI-012"
           ]

    assert Enum.all?(receipt.faults, &(&1.cleanup_status == :not_required))
  end

  test "JSON receipt is encoded without structs or atom values" do
    assert {:ok, receipt} = AgentFoundationRoundtrip.run()

    decoded = receipt |> AgentFoundationRoundtrip.to_json!() |> Jason.decode!()

    assert decoded["schema_version"] == "stack_lab_agent_foundation_roundtrip_v1"
    assert decoded["status"] == "pass"
    assert decoded["acceptance"]["AF-015"]["status"] == "pass"
    assert is_binary(decoded["aitrace"]["export_ref"])
  end

  test "no-bypass proof rejects explicit lower-stack and protocol tokens" do
    assert {:ok, no_bypass} = AgentFoundationRoundtrip.no_bypass_proof()

    assert no_bypass.status == :pass
    assert no_bypass.product_direct_lower_rejected? == true
    assert no_bypass.ax_terms_rejected? == true
    assert no_bypass.a2a_terms_rejected? == true
  end
end
