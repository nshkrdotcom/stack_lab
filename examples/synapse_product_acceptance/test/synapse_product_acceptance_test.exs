defmodule StackLab.Examples.SynapseProductAcceptanceTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.SynapseProductAcceptance

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
end
