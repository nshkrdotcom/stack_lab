defmodule StackLab.CitadelSpineHarness.SemanticGatewayContractEvidenceTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "describes the Phase 6 SemanticGatewayContract evidence consumer scenario" do
    scenario = CitadelSpineHarness.semantic_gateway_contract_scenario()

    assert scenario.name == :phase6_semantic_gateway_contract

    assert scenario.cases == %{
             semantic_gateway_owner_evidence: %{kind: :semantic_gateway_owner_evidence}
           }

    assert scenario.contract == "SemanticGatewayContract.v1"
    assert scenario.owner_repo == :outer_brain
    assert :stack_lab in scenario.primary_repos
    assert scenario.real_durability_scenario == :outer_brain_restart_durability
  end

  test "consumes OuterBrain SemanticGatewayContract.v1 and real restart durability evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_semantic_gateway_contract(
               :semantic_gateway_owner_evidence
             )

    assert result.case == :semantic_gateway_owner_evidence
    assert result.stack_lab_role == :evidence_composer_not_owner
    assert result.contract.id == "SemanticGatewayContract.v1"
    assert result.contract.owner == "outer_brain"

    assert result.service_mode_gate.outer_brain_owner_contract_consumed?
    assert result.service_mode_gate.real_outer_brain_restart_durability_consumed?
    assert result.service_mode_gate.lower_runtime_only_rejected?
    assert result.service_mode_gate.raw_payload_absent?

    assert result.positive.contract_id == "SemanticGatewayContract.v1"
    assert result.positive.semantic_context_provenance_ref == "semantic:result-phase6-m7"
    assert result.positive.semantic_failure_ref =~ "semantic_failure_journal:v1:"
    assert result.positive.read_only_context_adapter_boundary_ref == "context-adapter:phase6-m7"
    assert result.positive.reply_publication_dedupe_ref == "causal-phase6-m7:final"
    assert result.positive.suppression_visibility_ref == "suppression:phase6-m7"
    assert result.positive.privacy_redaction_fixture_ref == "fixture:phase6-m7-privacy"
    assert result.positive.restart_replay_with_semantic_state_ref =~ "outer-brain-restart://"

    assert result.real_restart.case == :duplicate_publication_suppressed_after_restart
    assert result.real_restart.after_restart.next_action == {:noop, :final_reply_published}

    assert result.real_restart.after_restart.publication_ids == [
             result.real_restart.durable.initial_publication_id
           ]

    assert result.negative_failures.missing_semantic_provenance ==
             {:missing_required_semantic_gateway_evidence, :semantic_context_provenance}

    assert result.negative_failures.raw_payload ==
             {:raw_payload_forbidden, :raw_provider_body}

    assert result.negative_failures.lower_runtime_only ==
             :lower_runtime_only_semantic_gateway_proof
  end
end
