defmodule StackLab.CitadelSpineHarness.Stage12LoadReadinessTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness

  test "Stage 12 proves same-subject callback storms stay idempotent and trace explainable" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage12_load_readiness(:same_subject_callback_storm)

    assert result.case == :same_subject_callback_storm
    assert result.callback_storm.subject_state == "paid"
    assert result.callback_storm.barrier_status == :closed
    assert result.callback_storm.completion_row_count == 2
    assert result.callback_storm.duplicate_callback_count == 2
    assert result.callback_storm.duplicate_short_circuit_count == 2
    assert result.callback_storm.join_job_count == 1
    assert result.callback_storm.join_transition_count == 1
    assert result.callback_storm.trace_explainable?
  end

  test "Stage 12 records shared-repo pressure evidence without checkout timeouts or replay storms" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage12_load_readiness(:shared_repo_pressure_posture)

    assert result.case == :shared_repo_pressure_posture
    assert result.pool_pressure.requested_connection_count == 20
    assert result.pool_pressure.repo_pool_size == 10
    assert result.pool_pressure.all_queries_succeeded?
    assert result.pool_pressure.checkout_timeout_count == 0
    assert result.pause_saturation.paused_dispatch_job_count == 10_000
    assert result.pause_saturation.peer_dispatch_ok?
    assert result.pause_saturation.dispatch_schedule_restored?

    assert result.lower_dispatch_ambiguity.recovered_count == 1
    assert result.lower_dispatch_ambiguity.unique_submission_count == 1
    assert result.lower_dispatch_ambiguity.duplicate_replay_count == 1

    assert result.lower_gateway_outage.circuit_state_before_probe == :open
    assert result.lower_gateway_outage.circuit_state_after_probe == :half_open
    assert length(result.lower_gateway_outage.probe_results) == 3

    assert result.startup_reconciliation.launcher_count == 3
    assert result.startup_reconciliation.reconcile_job_count == 1
    assert length(result.startup_reconciliation.summary_execution_ids) == 3

    assert result.leased_stream_invalidation.invalidation_count == 100
    assert result.leased_stream_invalidation.requested_connection_count == 10
    assert result.leased_stream_invalidation.repo_pool_size == 10
    assert result.leased_stream_invalidation.invalidated_after_ms <= 4_000

    assert result.notifier_posture.notifier == inspect(Oban.Notifiers.Isolated)
    refute result.notifier_posture.session_semantics_required?
    assert result.notifier_posture.testing_mode == :manual
    refute result.notifier_posture.queue_processing_enabled?
    assert result.notifier_posture.total_queue_limit == 0
    assert result.notifier_posture.repo_pool_size == 10

    assert result.adr_0008.keep_shared_repo_joboutbox?
    assert result.adr_0008.measured_evidence.checkout_timeout_count == 0
    assert result.adr_0008.measured_evidence.observed_job_rows == 10_000
  end

  test "Stage 12 keeps claim-check degradation, hot-row compactness, and archived reads explicit" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage12_load_readiness(
               :claim_check_degradation_and_compactness
             )

    assert result.case == :claim_check_degradation_and_compactness
    assert result.degradation.failure.result == {:error, :claim_check_unavailable}
    assert result.degradation.failure.run_count_unchanged?
    assert result.degradation.failure.stage_failure_reason == "claim_check_unavailable"
    assert result.degradation.cleanup.orphaned_staged_payload_count == 1
    assert result.degradation.cleanup.blob_gc_skipped_live_reference_count >= 4

    assert result.compactness.hot_rows_claim_checked?
    assert result.compactness.hot_rows_omit_large_payloads?
    assert result.compactness.live_reference_counts == %{input: 1, result: 1, output: 1, event: 1}

    assert result.compactness.archived_hot_read_errors.work_query ==
             {:error, :archived, result.compactness.archived_manifest_ref}

    assert result.compactness.archived_hot_read_errors.operator_status ==
             {:error, :archived, result.compactness.archived_manifest_ref}

    assert result.compactness.archived_rows_removed_count >= 4
  end
end
