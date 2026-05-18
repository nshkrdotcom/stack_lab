defmodule StackLab.GnTenLiveNeutralClaimBoundaryTest do
  use ExUnit.Case, async: true

  @receipt_path "docs/receipts/gn_ten_phase13/live_neutral_claim_boundary.json"
  @toy_proof_path "examples/toy_document_review/lib/stack_lab/examples/toy_document_review.ex"
  @proof_matrix_doc_path "docs/gn_ten_proof_matrix.md"

  test "Phase 13 release boundary does not overclaim live neutral provider proof" do
    receipt =
      @receipt_path
      |> File.read!()
      |> Jason.decode!()

    assert receipt["decision"]["multi_product_live_provider_claimed"] == false
    assert receipt["decision"]["live_provider_scope"] == "extravaganza_only"
    assert receipt["decision"]["neutral_genericity_scope"] == "deterministic_provider_free"
    assert receipt["decision"]["neutral_proof_app"] == "examples/toy_document_review"

    future_requirement = receipt["future_live_neutral_requirement"]

    assert future_requirement["requires_deterministic_fake_provider_acceptance"] == true
    assert future_requirement["requires_generic_stack_path"] == true
    assert future_requirement["requires_with_bash_secrets_for_github_or_linear"] == true
    assert future_requirement["guarded_live_command_prefix"] == "~/scripts/with_bash_secrets"
  end

  test "toy document review remains provider-free at the live acceptance boundary" do
    toy_proof = File.read!(@toy_proof_path)

    assert String.contains?(toy_proof, "live_profiles: []")
    assert String.contains?(toy_proof, "required?: false")
    assert String.contains?(toy_proof, "no_live_github_or_linear_profile_for_neutral_proof_app")
  end

  test "human proof matrix states the same live-provider claim boundary" do
    proof_matrix_doc = File.read!(@proof_matrix_doc_path)

    assert String.contains?(
             proof_matrix_doc,
             "Phase 13 does not add a multi-product live-provider claim"
           )

    assert String.contains?(proof_matrix_doc, "Current live-provider")
    assert String.contains?(proof_matrix_doc, "Extravaganza-scoped")

    assert String.contains?(proof_matrix_doc, "`~/scripts/with_bash_secrets`")
  end
end
