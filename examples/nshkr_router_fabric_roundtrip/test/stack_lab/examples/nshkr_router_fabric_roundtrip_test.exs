defmodule StackLab.Examples.NSHKRRouterFabricRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.NSHKRRouterFabricRoundtrip

  test "runs a deterministic provider-free TRINITY router fabric proof" do
    assert {:ok, receipt} = NSHKRRouterFabricRoundtrip.run()
    assert {:ok, again} = NSHKRRouterFabricRoundtrip.run()

    assert receipt.status == :pass
    assert receipt.receipt_ref == again.receipt_ref
    assert receipt.provider_dependency? == false
    assert receipt.context_packet_hash == again.context_packet_hash
    assert receipt.selected_route_kind == :trinity_coordinated
    assert receipt.selected_model_profile_ref == "model-profile://fixture/worker"
    assert receipt.trinity_selected_role_ref == "role://router-fabric/worker"
    assert receipt.scanner_receipts.context_abi.status == :pass
    assert receipt.scanner_receipts.router_fabric.status == :pass
    assert receipt.scanner_receipts.coordination_fabric.status == :pass
    assert receipt.scanner_receipts.model_inference.status == :pass
  end

  test "serializes a bounded JSON receipt without raw payload fields" do
    assert {:ok, receipt} = NSHKRRouterFabricRoundtrip.run()

    json = NSHKRRouterFabricRoundtrip.to_json!(receipt)

    assert json =~ "\"status\": \"pass\""
    assert json =~ "\"selected_route_kind\": \"trinity_coordinated\""
    assert json =~ "Trinity.MezzanineRouterAdapter" or json =~ "router_fabric"
    refute json =~ "raw_prompt"
    refute json =~ "provider_payload\":"
    assert json =~ "provider_payload_ref"
  end
end
