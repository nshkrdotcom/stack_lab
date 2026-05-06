defmodule StackLab.CitadelSpineHarness.Stage9OrchestrationRecoveryTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "scenario 9 operator pause preserves Temporal handoffs and does not starve peer tenants" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage9_orchestration_recovery(
               :operator_pause_during_active_execution
             )

    assert result.case == :operator_pause_during_active_execution
    assert result.scenario == 9

    assert result.pause.result_status == "paused"
    assert result.pause.temporal_handoff_count == 100
    assert result.pause.workflow_signal_count == 100
    assert result.pause.delayed_temporal_handoff_count == 100
    assert result.pause.decision_timer_preserved?
    assert result.pause.reconcile_handoff_preserved?

    assert result.resume.result_status == "active"
    assert result.resume.temporal_handoff_schedule_restored?
    assert result.resume.decision_timer_preserved?
    assert result.resume.reconcile_handoff_preserved?

    assert match?(
             {:snooze, seconds} when is_integer(seconds) and seconds >= 1,
             result.paused_probe.worker_result
           )

    assert result.paused_probe.handoff_status == :scheduled
    assert result.paused_probe.execution_state == :queued
    refute result.paused_probe.lower_gateway_called?

    assert result.saturation.paused_temporal_handoff_count == 10_000
    assert result.saturation.peer_dispatch.classification == :accepted
    assert result.saturation.peer_dispatch.worker_result == :ok
    assert result.saturation.peer_dispatch.handoff_status == :completed
  end

  test "scenario 16 operator cancel emits workflow signal and records late receipts as audit only" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage9_orchestration_recovery(
               :operator_cancel_during_active_execution
             )

    assert result.case == :operator_cancel_during_active_execution
    assert result.scenario == 16

    assert result.cancel.result_status == "cancelled"
    assert length(result.cancel.cancelled_execution_ids) == 1
    assert length(result.cancel.workflow_signal_refs) == 1
    assert length(result.cancel.local_mutation_refs) == 1
    assert result.cancel.execution_state == :cancelled

    assert result.workflow_cancel.action_kind == :workflow_signal
    assert result.workflow_cancel.signal_name == "operator.cancel"
    assert result.workflow_cancel.target_state == :accepted_active

    assert result.workflow_cancel.reason == %{
             "reason" => "operator cancel",
             "execution_id" => "execution://stage9/operator-cancel/accepted-active"
           }

    assert result.late_receipt.result == :audit_only
    assert result.late_receipt.audit_kinds == ["post_cancel_receipt", "reconciliation_warning"]
    assert result.late_receipt.subject_lifecycle_state == "queued"
    assert result.late_receipt.lifecycle_advance_delta == 0
  end

  test "scenario 17 decision expiry uses workflow timers and stays idempotent under races" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage9_orchestration_recovery(:decision_sla_expiry)

    assert result.case == :decision_sla_expiry
    assert result.scenario == 17

    assert result.early_resolution.lifecycle_state == "resolved"
    assert result.early_resolution.workflow_timer_cancelled?
    assert result.early_resolution.expiry_intent_cleared?

    assert result.expiry_resolution.workflow_timer_result == :ok
    assert result.expiry_resolution.lifecycle_state == "expired"
    assert result.expiry_resolution.expiry_intent_cleared?

    assert result.non_pending_expiry.workflow_timer_result == :discard
    assert result.non_pending_expiry.safe_action == :ignore_stale_timer_signal

    assert result.race_resolution.expiry_intent_cleared?
    assert result.race_resolution.lifecycle_state in ["resolved", "expired"]

    case result.race_resolution.lifecycle_state do
      "resolved" ->
        assert result.race_resolution.decide_result == {:ok, "resolved"}
        assert result.race_resolution.expire_result == :discard

      "expired" ->
        assert result.race_resolution.expire_result == :ok

        assert result.race_resolution.decide_result ==
                 {:error, {:decision_not_pending, "expired"}}
    end
  end

  test "scenario 23 parallel join closure closes the barrier exactly once and advances the subject once only" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage9_orchestration_recovery(:parallel_join_closure)

    assert result.case == :parallel_join_closure
    assert result.scenario == 23

    assert result.atomic_close.completion_row_count == 2
    assert result.atomic_close.completed_children == 2
    assert result.atomic_close.expected_children == 2
    assert result.atomic_close.status == :ready
    assert result.atomic_close.duplicate_progress_count == 2
    assert result.atomic_close.closer_count == 1

    assert result.atomic_close.over_increment_attempt ==
             {:error, {:workflow_closed, "fanout-group-stage9"}}

    assert Enum.all?(result.worker_integration.workflow_signal_results, &(&1 == :ok))

    assert Enum.all?(
             result.worker_integration.duplicate_signal_results,
             &(&1 == :duplicate_suppressed)
           )

    assert result.worker_integration.completion_row_count == 2
    assert result.worker_integration.barrier_before_join.status == :ready
    assert result.worker_integration.barrier_before_join.completed_children == 2
    assert length(result.worker_integration.join_workflow_refs) == 1
    assert result.worker_integration.subject_before_join.lifecycle_state == "awaiting_join"
    assert result.worker_integration.subject_before_join.row_version == 1
    assert result.worker_integration.subject_after_join.lifecycle_state == "paid"
    assert result.worker_integration.subject_after_join.row_version == 2
    assert result.worker_integration.barrier_after_join.status == :closed
    assert result.worker_integration.join_transition_count == 1
  end

  test "scenario 18 restart recovery resumes by persisted submission identity instead of blind redispatch" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage9_orchestration_recovery(
               :restart_during_dispatch_ambiguity
             )

    assert result.case == :restart_during_dispatch_ambiguity
    assert result.scenario == 18
    assert result.recovered_count == 1
    assert result.final_dispatch.classification == :accepted
    assert result.final_dispatch.unique_submission_count == 1
    assert result.final_dispatch.duplicate_replay_count == 1
    assert is_binary(result.preserved_submission_dedupe_key)
  end

  test "scenario 26 lower-gateway outage opens the circuit, snoozes handoffs, and leader-elects the half-open probe" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage9_orchestration_recovery(
               :lower_gateway_outage_recovery
             )

    assert result.case == :lower_gateway_outage_recovery
    assert result.scenario == 26
    assert result.circuit_before_probe.state == :open
    assert result.circuit_before_probe.error_count >= 5

    assert match?(
             {:snooze, seconds} when is_integer(seconds) and seconds >= 1,
             result.dispatch_handoff.worker_result
           )

    assert result.dispatch_handoff.handoff_status == :scheduled

    assert match?(
             {:snooze, seconds} when is_integer(seconds) and seconds >= 1,
             result.reconcile_handoff.worker_result
           )

    assert result.reconcile_handoff.receipt_handoff_refs == []

    assert result.probe_results == [
             {"scheduler-node-a", :allow},
             {"scheduler-node-b", {:snooze, 250}},
             {"scheduler-node-c", {:snooze, 250}}
           ]

    assert result.circuit_after_probe.state == :half_open
  end

  test "scenario 27 startup reconciliation deduplicates reconcile handoffs across concurrent launchers" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage9_orchestration_recovery(
               :startup_reconciliation_deduplication
             )

    assert result.case == :startup_reconciliation_deduplication
    assert result.scenario == 27
    assert result.launcher_count == 3
    assert length(result.reconcile_handoff_refs) == 1
    assert Enum.uniq(result.reconcile_handoff_refs) == result.reconcile_handoff_refs

    assert Enum.all?(result.summary_execution_ids, fn execution_ids ->
             length(execution_ids) == 1
           end)
  end
end
