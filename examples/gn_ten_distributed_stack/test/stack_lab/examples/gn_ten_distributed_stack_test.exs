defmodule StackLab.Examples.GnTenDistributedStackTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.GnTenDistributedStack

  test "runs the context 6-node distributed proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_context_6_node()

    assert receipt.status == :pass
    assert receipt.profile == "context_6_node"
    assert receipt.context_packet_hash =~ "sha256:"
    assert receipt.node_lab_run["status"] == "pass"
    assert receipt.distributed_envelope_scan["status"] == "pass"
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
    assert receipt.distributed_envelope_scan["status"] == "pass"
    assert receipt.node_placement.distinct_domain_nodes? == true
    assert receipt.node_placement.domain_node_count == 6
  end
end
