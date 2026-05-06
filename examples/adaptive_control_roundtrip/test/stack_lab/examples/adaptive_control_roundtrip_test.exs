defmodule StackLab.Examples.AdaptiveControlRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.AdaptiveControlRoundtrip

  test "proves deterministic closed-loop adaptive control roundtrip" do
    assert {:ok, receipt} = AdaptiveControlRoundtrip.run()

    assert receipt.fixture_refs == ["AOC-037", "AOC-040"]
    assert receipt.status == :pass
    assert receipt.provider_dependency? == false
    assert receipt.adaptive_control_scan.status == :pass
    assert receipt.appkit_projection.approval_decision_ref == "approval://operator/worker/v2"
    assert receipt.trace_dataset_ref == "trace-dataset://trinity/repair"
    assert receipt.candidate_ref == "candidate://role-worker/v2"
    assert receipt.promotion_ref == "promotion://candidate/worker/v2"
    assert receipt.rollback_ref == "rollback://candidate/worker/v1"
    assert receipt.stale_artifact_rejection_refs == ["stale-rejection://candidate/worker/v1"]
  end
end
