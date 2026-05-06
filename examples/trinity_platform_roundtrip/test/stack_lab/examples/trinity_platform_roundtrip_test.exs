defmodule StackLab.Examples.TRINITYPlatformRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.TRINITYPlatformRoundtrip

  test "proves deterministic governed TRINITY platform roundtrip" do
    assert {:ok, receipt} = TRINITYPlatformRoundtrip.run()

    assert receipt.fixture_refs == ["AOC-026", "AOC-036", "AOC-039", "AOC-043"]
    assert receipt.status == :pass
    assert receipt.provider_dependency? == false
    assert receipt.coordination_fabric_scan.status == :pass
    assert receipt.appkit_projection.router_decision.selected_role_ref == "role/worker"
    assert receipt.router_decision_ref == "router_decision:ai_run/trinity/demo:role/worker"
    assert receipt.verifier_result_ref == "verifier/mock/pass"
    assert receipt.trace_refs == ["trace/trinity/demo", "trace/router/demo"]
  end
end
