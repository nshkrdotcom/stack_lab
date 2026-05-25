defmodule StackLab.Examples.GnTenDistributedStackTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.GnTenDistributedStack

  test "runs the context 6-node distributed proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_context_6_node()

    assert receipt.status == :pass
    assert receipt.profile == "context_6_node"
    assert receipt.context_packet_hash =~ "sha256:"
    assert receipt.node_lab_run["status"] == "pass"
    assert receipt.node_lab_run["log_artifact"]["line_count"] > 0
    assert File.exists?(receipt.node_lab_run["log_artifact"]["path"])
    assert receipt.distributed_envelope_scan["status"] == "pass"
    assert receipt.evidence_status == "pass"
    assert length(receipt.node_trace_refs) == 5
    assert length(receipt.aitrace_exports) == 5
    assert Enum.all?(receipt.aitrace_exports, &(&1["status"] == "pass"))
    assert receipt.replay_bundle.bundle_ref =~ "replay-bundle://stack_lab/context-abi"
    assert receipt.node_placement.distinct_domain_nodes? == true
    assert receipt.node_placement.domain_node_count == 5
  end

  test "runs the router/model 6-node distributed proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_router_model_6_node()

    assert receipt.status == :pass
    assert receipt.profile == "router_model_6_node"
    assert receipt.context_packet_hash =~ "sha256:"
    assert receipt.route_decision_ref =~ "router_decision:"
    assert receipt.model_receipt_ref =~ "jido-model-invocation-receipt/"
    assert receipt.model_token_summary["input"] == 31
    assert receipt.model_token_summary["total"] == 45
    assert receipt.model_cost_summary["currency"] == "USD"
    assert receipt.model_stream_refs == []
    assert receipt.stream_fragment_posture == "not_requested"
    assert receipt.node_lab_run["status"] == "pass"
    assert receipt.node_lab_run["log_artifact"]["line_count"] > 0
    assert File.exists?(receipt.node_lab_run["log_artifact"]["path"])
    assert receipt.distributed_envelope_scan["status"] == "pass"
    assert receipt.evidence_status == "pass"
    assert length(receipt.node_trace_refs) == 6
    assert length(receipt.aitrace_exports) == 6
    assert Enum.all?(receipt.aitrace_exports, &(&1["status"] == "pass"))
    assert receipt.replay_bundle.bundle_ref =~ "replay-bundle://stack_lab/router-fabric"
    assert receipt.replay_bundle.model_receipt_ref == receipt.model_receipt_ref
    assert receipt.node_placement.distinct_domain_nodes? == true
    assert receipt.node_placement.domain_node_count == 6
  end

  test "records AITrace export failure posture without leaking raw evidence" do
    assert {:ok, receipt} =
             GnTenDistributedStack.run_router_model_6_node(
               evidence_opts: [
                 responses: %{
                   "export_trace" => {:error, %{"code" => "exporter_unavailable"}}
                 }
               ]
             )

    assert receipt.status == :open_defect
    assert receipt.evidence_status == "open_defect"
    assert Enum.all?(receipt.aitrace_exports, &(&1["status"] == "open_defect"))

    json = GnTenDistributedStack.to_json!(receipt)
    refute json =~ "cookie_value"
    refute json =~ "raw_prompt"
    refute json =~ "provider_payload\":"
  end

  test "runs the partition recovery fault receipt proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_partition_recovery()

    assert receipt.status == :pass
    assert receipt.profile == "partition_recovery"
    assert length(receipt.fault_receipts) == 7
    assert Enum.all?(receipt.fault_receipts, &(&1["status"] == "pass"))
    assert Enum.any?(receipt.fault_receipts, &(&1["fault_kind"] == "node_crash"))
    assert Enum.any?(receipt.fault_receipts, &(&1["fault_kind"] == "stale_dto"))
    assert Enum.any?(receipt.fault_receipts, &(&1["fault_kind"] == "trace_exporter_failure"))
    assert Enum.any?(receipt.owner_recovery_evidence, &(&1["owner"] == "mezzanine"))
    assert Enum.any?(receipt.owner_recovery_evidence, &(&1["owner"] == "citadel"))

    json = GnTenDistributedStack.to_json!(receipt)
    refute json =~ "cookie_value"
    refute json =~ "raw_prompt"
    refute json =~ "provider_payload\":"
  end
end
