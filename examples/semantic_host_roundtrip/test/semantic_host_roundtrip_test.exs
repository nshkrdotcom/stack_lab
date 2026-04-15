defmodule StackLab.Examples.SemanticHostRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.SemanticHostRoundtrip

  test "semantic-host scenario exposes the semantic northbound proof surface" do
    scenario = SemanticHostRoundtrip.scenario()

    assert scenario.name == :semantic_host_roundtrip
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)

    assert scenario.cases == %{
             turn_acceptance: %{kind: :turn_acceptance},
             turn_replay: %{kind: :turn_replay},
             turn_scope_rejection: %{kind: :turn_scope_rejection}
           }
  end

  test "turn acceptance drives a real semantic host call into durable Spine acceptance" do
    assert {:ok, result} = SemanticHostRoundtrip.exercise(:turn_acceptance)

    assert result.case == :turn_acceptance
    assert result.app_kit.state == :accepted
    assert result.semantic.route == "compile_workspace"
    assert result.semantic.args.workspace_id == "workspace/main"
    assert result.invocation.request_id == result.app_kit.request_id
    assert result.invocation.execution_intent["args"] == ["compile", "workspace/main"]
    assert result.citadel.replay_status == :submission_accepted
    assert result.citadel.submission_key == result.spine.submission_key
    assert result.citadel.submission_receipt_ref == result.spine.submission_receipt_ref
  end

  test "semantic replay converges at the host-ingress seam and preserves one durable acceptance" do
    assert {:ok, result} = SemanticHostRoundtrip.exercise(:turn_replay)

    assert result.case == :turn_replay
    assert result.first.app_kit.state == :accepted
    assert result.first.app_kit.submission_status == :queued
    assert result.second.app_kit.state == :accepted
    assert result.second.app_kit.submission_status == :already_present
    assert result.first.app_kit.request_id == result.second.app_kit.request_id
    assert result.first.semantic.route == "compile_workspace"
    assert result.citadel.replay_status == :submission_accepted
    assert result.citadel.submission_key == result.spine.submission_key
  end

  test "semantic host submission surfaces lower-scope rejection through Citadel readback" do
    assert {:ok, result} = SemanticHostRoundtrip.exercise(:turn_scope_rejection)

    assert result.case == :turn_scope_rejection
    assert result.app_kit.state == :accepted
    assert result.semantic.route == "compile_workspace"
    assert result.citadel.replay_status == :superseded
    assert result.citadel.last_error_code == "workspace_ref_unresolved"
    assert result.citadel.has_redecision_entry
    assert result.spine.rejection_family == :scope_unresolvable
    assert result.spine.reason_code == "workspace_ref_unresolved"
  end
end
