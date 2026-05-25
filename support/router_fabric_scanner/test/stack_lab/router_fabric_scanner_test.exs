defmodule StackLab.RouterFabricScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.RouterFabricScanner

  test "passes a ref-only TRINITY route handoff" do
    assert {:ok, receipt} =
             RouterFabricScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "examples/nshkr_router_fabric_roundtrip",
               route_requests: [route_request()],
               route_decisions: [route_decision()]
             })

    assert receipt.status == :pass
    assert receipt.findings == []
    assert :trinity_adapter_contract in receipt.checked_rules
  end

  test "detects selected model and route policy mismatches" do
    bad_decision =
      route_decision()
      |> Map.put(:selected_model_profile_ref, "model-profile://not-allowed")
      |> Map.put(:route_policy_ref, "route-policy://other")

    assert {:ok, receipt} =
             RouterFabricScanner.scan(%{
               route_requests: [route_request()],
               route_decisions: [bad_decision]
             })

    assert receipt.status == :open_defect
    assert has_finding?(receipt, :selected_model_allowlist, :selected_model_not_allowed)
    assert has_finding?(receipt, :route_policy_consistency, :route_policy_mismatch)
  end

  test "rejects raw prompt fields anywhere in router proof facts" do
    assert {:ok, receipt} =
             RouterFabricScanner.scan(%{
               route_requests: [route_request()],
               route_decisions: [route_decision()],
               metadata: %{raw_prompt: "never"}
             })

    assert receipt.status == :open_defect
    assert has_finding?(receipt, :no_raw_route_payloads, {:forbidden_raw_field, "raw_prompt"})
  end

  defp has_finding?(receipt, rule, reason) do
    Enum.any?(receipt.findings, &(&1.rule == rule and &1.reason == reason))
  end

  defp route_request do
    %{
      tenant_ref: "tenant://router/demo",
      workflow_ref: "workflow://router/demo",
      context_packet_ref: "context-packet://router/demo",
      packet_hash: sha("a"),
      authority_ref: "authority://router/demo",
      route_policy_ref: "route-policy://router/demo",
      model_class_allowlist: ["model-profile://fixture/worker"],
      trace_ref: "trace://router/demo"
    }
  end

  defp route_decision do
    %{
      route_decision_ref: "router_decision:workflow://router/demo:role://fixture/worker",
      context_packet_ref: route_request().context_packet_ref,
      packet_hash: route_request().packet_hash,
      selected_route_kind: :trinity_coordinated,
      selected_model_profile_ref: "model-profile://fixture/worker",
      provider_or_runtime_ref: "runtime://fixture/worker",
      route_policy_ref: route_request().route_policy_ref,
      authority_packet_ref: route_request().authority_ref,
      reason_codes: ["trinity.route.selected.v1"],
      trace_ref: route_request().trace_ref,
      trinity: %{
        router_artifact_ref: "router-artifact://fixture",
        extractor_ref: "extractor://fixture",
        head_ref: "head://fixture",
        selected_role_ref: "role://fixture/worker",
        confidence_band: :high
      }
    }
  end

  defp sha(char), do: "sha256:" <> String.duplicate(char, 64)
end
