defmodule StackLab.Examples.SessionLineageDrillTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.SessionLineageDrill

  test "session-lineage drill points at the multi-node harness" do
    scenario = SessionLineageDrill.scenario()

    assert scenario.name == :session_lineage_drill
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
    assert :ok = SessionLineageDrill.validate_proof(scenario.proof)
  end

  test "assembled proof covers every agent-turn repo boundary" do
    proof = SessionLineageDrill.proof()

    assert proof.proof_id == "agent_turn_runtime_patterns"
    assert proof.profile == "assembled_offline"

    assert Enum.map(proof.repo_evidence, & &1.repo) == [
             "outer_brain",
             "citadel",
             "jido_integration",
             "execution_plane",
             "mezzanine",
             "AITrace"
           ]
  end

  test "assembled proof records multi-turn recovery and dynamic tool manifest behavior" do
    proof = SessionLineageDrill.proof()
    [first_turn, second_turn] = proof.turns

    assert second_turn.restored_from_turn_ref == first_turn.turn_ref
    assert second_turn.tool_manifest_ref == first_turn.tool_manifest_ref
    assert proof.recovery.recovered?
    assert proof.recovery.semantic_context_restored?
    assert proof.dynamic_tool_manifest.resolved_after_recovery?
    assert proof.dynamic_tool_manifest.unauthorized_tool_rejected?

    assert proof.dynamic_tool_manifest.selected_tool_role_ref in proof.dynamic_tool_manifest.allowed_tool_role_refs
  end

  test "assembled proof records fault injection fallback and AITrace replay evidence" do
    proof = SessionLineageDrill.proof()

    assert proof.fault_injection.injected_fault == "primary_lane_timeout"
    assert proof.fault_injection.fallback_selected?
    assert proof.fault_injection.unmanifested_tool_failed_closed?
    assert proof.aitrace_lineage.replay_causality_verified?

    assert proof.aitrace_lineage.event_kinds == [
             "turn_started",
             "semantic_context_restored",
             "dynamic_tool_manifest_resolved",
             "authority_checked",
             "lower_runtime_invoked",
             "fallback_lane_selected",
             "operation_receipt_recorded",
             "trace_replay_exported"
           ]
  end

  test "validator rejects missing repo evidence" do
    proof =
      SessionLineageDrill.proof()
      |> Map.update!(
        :repo_evidence,
        &Enum.reject(&1, fn evidence -> evidence.repo == "AITrace" end)
      )

    assert {:error, failures} = SessionLineageDrill.validate_proof(proof)
    assert failure_code?(failures, "agent_turn_missing_repo_evidence")
  end

  test "validator rejects single-turn sessions" do
    proof =
      SessionLineageDrill.proof()
      |> Map.update!(:turns, &Enum.take(&1, 1))

    assert {:error, failures} = SessionLineageDrill.validate_proof(proof)
    assert failure_code?(failures, "agent_turn_needs_multi_turn_recovery")
  end

  test "validator rejects dynamic manifest and fallback regressions" do
    manifest_regression =
      SessionLineageDrill.proof()
      |> put_in([:dynamic_tool_manifest, :unauthorized_tool_rejected?], false)

    assert {:error, manifest_failures} = SessionLineageDrill.validate_proof(manifest_regression)
    assert failure_code?(manifest_failures, "agent_turn_unmanifested_tool_not_rejected")

    fallback_regression =
      SessionLineageDrill.proof()
      |> put_in([:fault_injection, :fallback_selected?], false)

    assert {:error, fallback_failures} = SessionLineageDrill.validate_proof(fallback_regression)
    assert failure_code?(fallback_failures, "agent_turn_fallback_not_selected")
  end

  test "validator rejects missing AITrace lineage events" do
    proof =
      SessionLineageDrill.proof()
      |> Map.update!(:aitrace_lineage, fn lineage ->
        Map.update!(lineage, :event_kinds, &List.delete(&1, "trace_replay_exported"))
      end)

    assert {:error, failures} = SessionLineageDrill.validate_proof(proof)
    assert failure_code?(failures, "agent_turn_missing_aitrace_events")
  end

  defp failure_code?(failures, code) do
    Enum.any?(failures, &(&1.code == code))
  end
end
