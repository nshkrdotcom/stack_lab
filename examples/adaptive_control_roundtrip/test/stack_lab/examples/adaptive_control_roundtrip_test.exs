defmodule StackLab.Examples.AdaptiveControlRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.AdaptiveControlRoundtrip

  test "proves deterministic closed-loop adaptive control roundtrip" do
    assert {:ok, receipt} = AdaptiveControlRoundtrip.run()

    assert "AOC-037" in receipt.fixture_refs
    assert "AOC-040" in receipt.fixture_refs
    assert "AOC-045" in receipt.fixture_refs
    assert "AOC-046" in receipt.fixture_refs
    assert "AOC-047" in receipt.fixture_refs
    assert "PERSIST-AOC-006" in receipt.fixture_refs
    assert "PERSIST-AOC-007" in receipt.fixture_refs
    assert receipt.status == :pass
    assert receipt.provider_dependency? == false
    assert receipt.adaptive_control_scan.status == :pass
    assert receipt.live_provider_gate_ref == "live-provider-gate://phase14/openai"
    assert receipt.openapi_operation_ref == "pristine-operation://github/issues/list"
    assert receipt.graphql_operation_ref == "prismatic-operation://linear/viewer"
    assert receipt.persistence_profile_ref == "persistence-profile://phase14/integration-postgres"
    assert receipt.debug_sidecar_ref == "debug-sidecar://phase14/redacted"
    assert receipt.appkit_projection.approval_decision_ref == "approval://operator/worker/v2"
    assert receipt.trace_dataset_ref == "trace-dataset://trinity/repair"
    assert receipt.candidate_ref == "candidate://role-worker/v2"
    assert receipt.promotion_ref == "promotion://candidate/worker/v2"
    assert receipt.rollback_ref == "rollback://candidate/worker/v1"
    assert receipt.stale_artifact_rejection_refs == ["stale-rejection://candidate/worker/v1"]
  end
end
