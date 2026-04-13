defmodule StackLab.Examples.TypedHostRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.TypedHostRoundtrip

  test "typed-host scenario exposes the real AppKit and Domain proof surface" do
    scenario = TypedHostRoundtrip.scenario()

    assert scenario.name == :typed_host_roundtrip
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)

    assert scenario.cases == %{
             command_acceptance: %{kind: :command_acceptance},
             command_duplicate: %{kind: :command_duplicate},
             command_scope_rejection: %{kind: :command_scope_rejection}
           }
  end

  test "command acceptance drives a real typed host call into durable Spine acceptance" do
    assert {:ok, result} = TypedHostRoundtrip.exercise(:command_acceptance)

    assert result.case == :command_acceptance
    assert result.app_kit.state == :accepted
    assert result.app_kit.route_name == :compile_workspace
    assert result.domain.lifecycle_event == :live_owner
    assert result.invocation.request_id == result.app_kit.request_id
    assert result.invocation.execution_intent["args"] == ["compile", "workspace/main"]
    assert result.citadel.replay_status == :submission_accepted
    assert result.citadel.submission_key == result.spine.submission_key
    assert result.citadel.submission_receipt_ref == result.spine.submission_receipt_ref
  end

  test "duplicate command submission converges at the Citadel host-ingress seam" do
    assert {:ok, result} = TypedHostRoundtrip.exercise(:command_duplicate)

    assert result.case == :command_duplicate
    assert result.first.app_kit.state == :accepted
    assert result.first.app_kit.submission_status == :queued
    assert result.second.app_kit.state == :accepted
    assert result.second.app_kit.submission_status == :already_present
    assert result.first.app_kit.request_id == result.second.app_kit.request_id
    assert result.first.app_kit.request_id == result.invocation.request_id
    assert result.citadel.replay_status == :submission_accepted
    assert result.citadel.submission_key == result.spine.submission_key
  end

  test "typed host submission surfaces lower-scope rejection through Citadel readback" do
    assert {:ok, result} = TypedHostRoundtrip.exercise(:command_scope_rejection)

    assert result.case == :command_scope_rejection
    assert result.app_kit.state == :accepted
    assert result.citadel.replay_status == :superseded
    assert result.citadel.last_error_code == "workspace_ref_unresolved"
    assert result.citadel.has_redecision_entry
    assert result.spine.rejection_family == :scope_unresolvable
    assert result.spine.reason_code == "workspace_ref_unresolved"
  end
end
