defmodule StackLab.Examples.ContextABIRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.ContextABIRoundtrip

  test "runs a deterministic provider-free Context ABI platform proof" do
    assert {:ok, receipt} = ContextABIRoundtrip.run()
    assert {:ok, again} = ContextABIRoundtrip.run()

    assert receipt.status == :pass
    assert receipt.receipt_ref == again.receipt_ref
    assert receipt.context_packet_ref == again.context_packet_ref
    assert receipt.context_packet_hash == again.context_packet_hash
    assert receipt.provider_dependency? == false
    assert receipt.context_packet_hash =~ ~r/^sha256:[0-9a-f]{64}$/
    assert receipt.context_packet_ref =~ ~r/^context-packet:\/\/[0-9a-f]{64}$/
    assert receipt.authority_ref == "authority://context-abi/demo/grant"
    assert receipt.model_receipt_ref =~ "jido-model-invocation-receipt"
    assert receipt.provider_payload_ref =~ "provider-payload://"
    assert receipt.scanner_receipts.context_abi.status == :pass
    assert receipt.scanner_receipts.model_inference.status == :pass
    assert receipt.scanner_receipts.cost_budget.status == :pass
    assert receipt.scanner_receipts.ai_run_lineage.status == :pass
    assert receipt.scanner_receipts.tenant_isolation.status == :pass
    assert receipt.scanner_receipts.memory_fabric.status == :pass
  end

  test "serializes a bounded JSON receipt without raw payload fields" do
    assert {:ok, receipt} = ContextABIRoundtrip.run()

    json = ContextABIRoundtrip.to_json!(receipt)

    assert json =~ "\"status\": \"pass\""
    assert json =~ "\"context_packet_hash\": \"sha256:"
    refute json =~ "raw_prompt"
    refute json =~ "provider_payload\":"
    assert json =~ "provider_payload_ref"
  end
end
