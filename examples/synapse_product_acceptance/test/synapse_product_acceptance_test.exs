defmodule StackLab.Examples.SynapseProductAcceptanceTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.SynapseProductAcceptance
  alias StackLab.Examples.SynapseStagedLive

  test "runs the Synapse product acceptance proof" do
    assert {:ok, receipt} = SynapseProductAcceptance.run()

    assert receipt["schema_version"] == "stack_lab.synapse_product_acceptance.v1"
    assert receipt["status"] == "pass"
    assert receipt["product_repo"] == "synapse"
    assert receipt["product_path"] == "/home/home/p/g/n/synapse"
    assert receipt["no_bypass"]["status"] == "pass"

    proofs = receipt["proofs"]

    assert proofs["bootstrap"]["status"] == "pass"
    assert proofs["run_start"]["run_ref"] == "run://fixture/stacklab-synapse-proof"
    assert proofs["turn_submission"]["status"] == "accepted"
    assert proofs["review_decision"]["status"] == "accepted"
    assert proofs["memory_context"]["status"] == "pass"
    assert proofs["denial_path"]["status"] == "pass"
    assert proofs["evidence"]["status"] == "pass"
    assert proofs["cross_tenant"]["status"] == "not_applicable"
  end

  test "runs the Synapse staged-live governed-effect proof" do
    assert {:ok, receipt} = SynapseStagedLive.run()

    assert receipt["schema_version"] == "stack_lab.synapse_staged_live.v1"
    assert receipt["status"] == "pass"
    assert receipt["classification"] == "staging_live"
    assert receipt["no_bypass"]["status"] == "pass"

    proofs = receipt["proofs"]

    assert proofs["fixture_acceptance"]["status"] == "pass"
    assert proofs["run_start"]["status"] == "pass"
    assert proofs["run_start"]["feature_status"] == "staging_live"

    assert proofs["run_start"]["effect_ref"] ==
             "effect://synapse/stacklab-synapse-staged-live/echo"

    assert proofs["governed_pipeline"]["status"] == "pass"
    assert proofs["governed_pipeline"]["citadel_authority"] == "allow"
    assert proofs["governed_pipeline"]["jido_receipt_status"] == "success"
    assert proofs["governed_pipeline"]["execution_plane_status"] == "ok"
    assert proofs["governed_pipeline"]["aitrace_span_count"] > 0
    assert proofs["timeline"]["status"] == "pass"
    assert proofs["denial_path"]["status"] == "pass"
    assert proofs["denial_path"]["lower_invocation_submitted?"] == false
    assert proofs["evidence_chain"]["status"] == "pass"
    assert String.starts_with?(proofs["evidence_chain"]["command_envelope_hash"], "sha256:")
  end
end
