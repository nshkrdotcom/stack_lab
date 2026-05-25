defmodule StackLab.Examples.GEPAPlatformRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.GEPAPlatformRoundtrip

  test "proves deterministic governed GEPA platform roundtrip" do
    assert {:ok, receipt} = GEPAPlatformRoundtrip.run()

    assert receipt.fixture_refs == ["AOC-018", "AOC-019", "AOC-038", "AOC-041", "AOC-042"]
    assert receipt.status == :pass
    assert receipt.provider_dependency? == false
    assert receipt.model_inference_scan.status == :pass
    assert receipt.optimization_fabric_scan.status == :pass
    assert receipt.ai_run_lineage_scan.status == :pass

    assert receipt.framework_projection.best_candidate_ref ==
             "candidate:component:gepa:mezzanine:1"

    assert receipt.candidate_receipt.candidate_ref ==
             receipt.framework_projection.best_candidate_ref

    assert receipt.candidate_receipt.context_packet_ref == "context-packet://gepa/phase-13"
    assert receipt.candidate_receipt.route_decision_ref == "target://gepa/role-worker"
    assert receipt.appkit_projection.candidate_ref == receipt.candidate_receipt.candidate_ref

    assert receipt.promotion_ref == "promotion://gepa/candidate"
    assert receipt.rollback_ref == "rollback://gepa/candidate"
  end
end
