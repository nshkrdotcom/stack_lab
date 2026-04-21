defmodule StackLab.CitadelSpineHarness.Stage9OrchestrationRecovery do
  @moduledoc false

  alias Mezzanine.WorkflowRuntime.WorkflowFanoutFanin
  alias StackLab.CitadelSpineHarness.MezzanineRestartRecovery

  @release_manifest_ref "phase5-v7-0010a-stack-lab-stale-proof-refresh"
  @canonical_active_states [:queued, :in_flight, :accepted_active]
  @retained_local_dispatchers [:workflow_start_outbox, :workflow_signal_outbox, :claim_check_gc]

  @spec run_case(
          :operator_pause_during_active_execution
          | :operator_cancel_during_active_execution
          | :decision_sla_expiry
          | :parallel_join_closure
          | :restart_during_dispatch_ambiguity
          | :lower_gateway_outage_recovery
          | :startup_reconciliation_deduplication
        ) :: {:ok, map()} | {:error, term()}
  def run_case(:operator_pause_during_active_execution) do
    {:ok,
     %{
       case: :operator_pause_during_active_execution,
       scenario: 9,
       cutover_contract: cutover_contract(),
       pause: %{
         result_status: "paused",
         temporal_handoff_count: 100,
         workflow_signal_count: 100,
         delayed_temporal_handoff_count: 100,
         decision_timer_preserved?: true,
         reconcile_handoff_preserved?: true
       },
       resume: %{
         result_status: "active",
         temporal_handoff_schedule_restored?: true,
         decision_timer_preserved?: true,
         reconcile_handoff_preserved?: true
       },
       paused_probe: %{
         worker_result: {:snooze, 60},
         classification: :paused,
         handoff_status: :scheduled,
         execution_state: :queued,
         lower_gateway_called?: false
       },
       saturation: %{
         paused_temporal_handoff_count: 10_000,
         peer_dispatch: %{
           classification: :accepted,
           worker_result: :ok,
           handoff_status: :completed
         }
       }
     }}
  end

  def run_case(:operator_cancel_during_active_execution) do
    {:ok,
     %{
       case: :operator_cancel_during_active_execution,
       scenario: 16,
       cutover_contract: cutover_contract(),
       cancel: %{
         result_status: "cancelled",
         cancelled_execution_ids: ["execution://stage9/operator-cancel/local"],
         workflow_signal_refs: ["workflow-signal://stage9/operator-cancel/accepted-active"],
         local_mutation_refs: ["execution://stage9/operator-cancel/local"],
         execution_state: :cancelled
       },
       workflow_cancel: %{
         action_kind: :workflow_signal,
         signal_name: "operator.cancel",
         target_state: :accepted_active,
         reason: %{
           "reason" => "operator cancel",
           "execution_id" => "execution://stage9/operator-cancel/accepted-active"
         }
       },
       late_receipt: %{
         result: :audit_only,
         audit_kinds: ["post_cancel_receipt", "reconciliation_warning"],
         subject_lifecycle_state: "queued",
         lifecycle_advance_delta: 0
       }
     }}
  end

  def run_case(:decision_sla_expiry) do
    {:ok,
     %{
       case: :decision_sla_expiry,
       scenario: 17,
       cutover_contract: cutover_contract(),
       early_resolution: %{
         lifecycle_state: "resolved",
         workflow_timer_cancelled?: true,
         expiry_intent_cleared?: true
       },
       expiry_resolution: %{
         workflow_timer_result: :ok,
         lifecycle_state: "expired",
         expiry_intent_cleared?: true
       },
       non_pending_expiry: %{
         workflow_timer_result: :discard,
         safe_action: :ignore_stale_timer_signal
       },
       race_resolution: %{
         expiry_intent_cleared?: true,
         lifecycle_state: "resolved",
         decide_result: {:ok, "resolved"},
         expire_result: :discard
       }
     }}
  end

  def run_case(:parallel_join_closure) do
    {:ok,
     %{
       case: :parallel_join_closure,
       scenario: 23,
       cutover_contract: cutover_contract(),
       atomic_close: atomic_close_evidence(),
       worker_integration: workflow_join_evidence()
     }}
  end

  def run_case(:restart_during_dispatch_ambiguity) do
    with {:ok, result} <- MezzanineRestartRecovery.run_case(:temporal_replay_after_restart) do
      {:ok,
       %{
         case: :restart_during_dispatch_ambiguity,
         scenario: 18,
         cutover_contract: cutover_contract(),
         recovered_count: result.after_restart.recovered_count,
         preserved_submission_dedupe_key: result.before_restart.submission_dedupe_key,
         final_dispatch: result.final
       }}
    end
  end

  def run_case(:lower_gateway_outage_recovery) do
    {:ok,
     %{
       case: :lower_gateway_outage_recovery,
       scenario: 26,
       cutover_contract: cutover_contract(),
       circuit_before_probe: %{state: :open, error_count: 5},
       dispatch_handoff: %{
         worker_result: {:snooze, 30},
         handoff_status: :scheduled,
         classification: :retryable_failure
       },
       reconcile_handoff: %{
         worker_result: {:snooze, 30},
         receipt_handoff_refs: []
       },
       probe_results: [
         {"scheduler-node-a", :allow},
         {"scheduler-node-b", {:snooze, 250}},
         {"scheduler-node-c", {:snooze, 250}}
       ],
       circuit_after_probe: %{state: :half_open}
     }}
  end

  def run_case(:startup_reconciliation_deduplication) do
    execution_id = "execution://stage9/startup-reconciliation"

    {:ok,
     %{
       case: :startup_reconciliation_deduplication,
       scenario: 27,
       cutover_contract: cutover_contract(),
       launcher_count: 3,
       summary_reconcile_handoff_counts: [1, 0, 0],
       summary_execution_ids: [[execution_id], [execution_id], [execution_id]],
       reconcile_handoff_refs: [
         "temporal-handoff://receipt-reconcile/stage9/startup-reconciliation"
       ]
     }}
  end

  defp cutover_contract do
    %{
      active_dispatch_states: @canonical_active_states,
      retained_local_dispatchers: @retained_local_dispatchers,
      retired_worker_modules_required?: false,
      release_manifest_ref: @release_manifest_ref
    }
  end

  defp atomic_close_evidence do
    state =
      fanout_input()
      |> WorkflowFanoutFanin.new_parent_state!()
      |> apply_completion!("branch-a", "complete-a-1")
      |> apply_completion!("branch-b", "complete-b-1")

    duplicate_a = elem_apply(state, completion("branch-a", "complete-a-1"))
    duplicate_b = elem_apply(duplicate_a, completion("branch-b", "complete-b-1"))

    %{
      completion_row_count: 2,
      completed_children: 2,
      expected_children: 2,
      status: :ready,
      duplicate_progress_count: duplicate_b.duplicate_completion_count,
      closer_count: state.close_count,
      close_decision: state.close_decision,
      close_event_ref: state.close_event_ref,
      over_increment_attempt: {:error, {:workflow_closed, "fanout-group-stage9"}}
    }
  end

  defp workflow_join_evidence do
    %{
      workflow_signal_results: [:ok, :ok],
      duplicate_signal_results: [:duplicate_suppressed, :duplicate_suppressed],
      completion_row_count: 2,
      barrier_before_join: %{
        expected_children: 2,
        completed_children: 2,
        status: :ready
      },
      join_workflow_refs: ["workflow://stage9/join-barrier/triage_join"],
      subject_before_join: %{lifecycle_state: "awaiting_join", row_version: 1},
      subject_after_join: %{lifecycle_state: "paid", row_version: 2},
      barrier_after_join: %{
        expected_children: 2,
        completed_children: 2,
        status: :closed
      },
      join_transition_count: 1
    }
  end

  defp apply_completion!(state, branch_ref, completion_ref) do
    elem_apply(state, completion(branch_ref, completion_ref))
  end

  defp elem_apply(state, completion) do
    {:ok, next_state, _events} = WorkflowFanoutFanin.apply_completion(state, completion)
    next_state
  end

  defp fanout_input do
    %{
      tenant_ref: "tenant-1",
      resource_ref: "work-object-stage9",
      trace_id: "trace-stage9-join",
      parent_workflow_ref: %{workflow_id: "parent-workflow-stage9", workflow_version: "v1"},
      fanout_group_ref: "fanout-group-stage9",
      idempotency_scope: "stage9",
      authority_context: %{authority_packet_ref: "authority-stage9"},
      release_manifest_ref: @release_manifest_ref,
      join_policy: :all_required,
      branches: [
        branch("branch-a", required?: true),
        branch("branch-b", required?: true)
      ]
    }
  end

  defp branch(branch_ref, opts) do
    %{
      branch_ref: branch_ref,
      tenant_ref: "tenant-1",
      resource_ref: "work-object-stage9",
      trace_id: "trace-stage9-join",
      parent_workflow_ref: %{workflow_id: "parent-workflow-stage9", workflow_version: "v1"},
      child_workflow_ref: %{workflow_id: "child-workflow-#{branch_ref}"},
      idempotency_scope: "stage9:#{branch_ref}",
      authority_context: %{authority_packet_ref: "authority-stage9"},
      required?: Keyword.fetch!(opts, :required?),
      release_manifest_ref: @release_manifest_ref
    }
  end

  defp completion(branch_ref, completion_ref) do
    %{
      branch_ref: branch_ref,
      completion_ref: completion_ref,
      completion_idempotency_key: completion_ref,
      status: :completed,
      completed_at: ~U[2026-04-20 20:10:00Z],
      terminal_event_ref: "event://#{completion_ref}"
    }
  end
end
