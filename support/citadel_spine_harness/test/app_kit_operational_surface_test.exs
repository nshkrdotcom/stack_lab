defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurfaceTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 300_000

  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.MixProject, as: HarnessMixProject

  test "app-kit operational surface proof covers install, ingest, action, review, and unified trace" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_app_kit_operational_surface(
               :install_ingest_review_trace
             )

    assert result.case == :install_ingest_review_trace
    assert result.tenant_id == "tenant-app-kit-operational"

    assert result.installation.created_status == :created
    assert result.installation.fetched_status == :active
    assert result.installation.installation_id in result.installation.listed_ids

    assert result.work.subject_id in result.work.listed_ids
    assert result.work.pre_run_pending_obligation_ids != []
    assert result.work.pre_run_pending_decision_ref_ids == []
    assert result.work.pre_run_blocker_kinds == []
    assert result.work.pre_run_next_step_kind == "start_run"
    assert result.control.state == :waiting_review
    assert result.control.run_id == result.work.detail_active_run_id
    assert result.control.review_unit_id in result.work.detail_pending_reviews
    assert result.control.review_unit_id in result.work.detail_pending_decision_ref_ids
    assert result.work.detail_blocker_kinds == ["review_pending"]
    assert result.work.detail_next_step_kind == "record_review_decision"

    assert result.operator.current_run_id == result.control.run_id
    assert result.operator.chosen_action == result.operator.applied_action
    assert result.operator.pending_obligation_ids == result.work.detail_pending_obligation_ids
    assert result.operator.pending_decision_ref_ids == result.work.detail_pending_decision_ref_ids
    assert result.operator.blocker_kinds == ["review_pending"]
    assert result.operator.next_step_kind == "record_review_decision"
    assert "run_scheduled" in result.operator.timeline_kinds

    assert result.review.pending_ids_before == [result.control.review_unit_id]
    assert result.review.pending_ids_after == []
    assert result.review.status_before == "pending"
    assert result.review.status_after == "accepted"
    assert result.review.action_kind == "review_accept"
    assert result.review.blocker_kinds_after == ["operator_paused"]
    assert result.review.next_step_kind_after == "resume_subject"

    assert result.trace.execution_id
    assert result.trace.trace_id
    assert "audit_fact" in result.trace.step_sources
    assert "execution_record" in result.trace.step_sources
    assert "decision_record" in result.trace.step_sources
    assert "evidence_record" in result.trace.step_sources
    assert "lower_run_status" in result.trace.step_sources

    assert_received {:lower_fetch_run, "tenant-app-kit-operational", _run_id}
    assert_received {:lower_events, "tenant-app-kit-operational", _run_id}
    assert_received {:lower_attempts, "tenant-app-kit-operational", _run_id}
    assert_received {:lower_run_artifacts, "tenant-app-kit-operational", _run_id}
  end

  test "app-kit operational surface consumes the governed agent workload contract" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_app_kit_operational_surface(
               :governed_agent_workload_contract
             )

    assert result.case == :governed_agent_workload_contract
    assert result.tenant_id == "tenant-app-kit-governed-workload"

    assert result.governed_workload.contract_name == "GovernedAgentWorkloadContract.v1"
    assert result.governed_workload.ingress_ref == "app_kit_operator_surface_via_mezzanine_bridge"
    assert result.governed_workload.synthetic_operator_driver_ref == "operator_script_in_app_kit"

    assert result.governed_workload.work_class_ref ==
             "stack_lab/work_classes/service_operations"

    assert result.governed_workload.pack_ref == "mezzanine/packs/stack_lab_service_ops@1"
    assert result.governed_workload.subject_kind == "service_task"

    assert result.governed_workload.script_surfaces == [
             :app_kit_work_control,
             :app_kit_review_surface,
             :app_kit_operator_surface
           ]

    assert result.control.state == :waiting_review
    assert result.work.detail_blocker_kinds == ["review_pending"]
    assert result.review.status_before == "pending"
    assert result.review.status_after == "accepted"
    assert result.review.action_kind == "review_accept"

    assert result.lifecycle.transition_paths.rejection_path == [
             :submitted,
             :awaiting_review,
             :rejected
           ]

    assert result.scale_pressure_seed == %{
             contract_name: "ScalePressureProfile.v1",
             workload_contract_ref: "GovernedAgentWorkloadContract.v1",
             workload_ref: "workloads/stack-lab-service-ops",
             profile_id: "profiles/stack_lab/local_default",
             tenant_count: 1,
             agents_per_tenant: 1,
             work_items_per_agent: 1,
             max_concurrency: 1
           }

    assert result.bare_asm_substitute_rejection == :bare_asm_workload_forbidden
    refute result.task_async_stream_substitute?
  end

  test "app-kit operational surface proves one real lower-backed command path and receipt readback" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_app_kit_operational_surface(:lower_backed_command_trace)

    assert result.case == :lower_backed_command_trace
    assert result.tenant_id == "tenant-app-kit-lower-backed"

    assert result.installation.created_status == :created
    assert is_binary(result.installation.installation_id)

    assert is_binary(result.work.subject_id)
    assert is_binary(result.work.run_id)
    assert result.work.state == :scheduled

    assert is_binary(result.dispatch.execution_id)
    assert result.dispatch.classification == :accepted
    assert result.dispatch.job_status == :completed
    assert result.dispatch.submission_status == "accepted"
    assert String.starts_with?(result.dispatch.submission_key, "sha256:")
    assert String.starts_with?(result.dispatch.submission_receipt_ref, "submission://local/")
    assert result.receipt_proof.direct_submission_key == result.dispatch.submission_key
    assert result.receipt_proof.bridged_submission_key == result.dispatch.submission_key
    assert result.receipt_proof.receipt_ref == result.dispatch.submission_receipt_ref

    assert "audit_fact" in result.trace.step_sources
    assert "execution_record" in result.trace.step_sources
    assert "lower_run_status" in result.trace.step_sources
    assert result.trace.join_keys["execution_id"] == result.dispatch.execution_id
  end

  test "app-kit operational surface proves a terminal lower-backed rejection reaches the caller as a stable trace-visible rejection" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_app_kit_operational_surface(
               :lower_backed_command_terminal_rejection
             )

    assert result.case == :lower_backed_command_terminal_rejection
    assert result.tenant_id == "tenant-app-kit-lower-backed-reject"

    assert result.work.state == :scheduled
    assert result.dispatch.classification == :terminal_rejection
    assert result.dispatch.execution_state == :rejected
    assert result.dispatch.job_status == :terminal
    assert result.dispatch.terminal_rejection_reason == "terminal_rejection"
    assert result.dispatch.rejection_reason == "workspace_ref_unresolved"
    assert result.dispatch.rejection_family == "scope_unresolvable"

    assert "execution_record" in result.trace.step_sources
    assert result.trace.rejected_execution.dispatch_state == :rejected
    assert result.trace.rejected_execution.terminal_rejection_reason == "terminal_rejection"
  end

  test "app-kit operational surface routes one normalized semantic failure into deterministic operator recovery" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_app_kit_operational_surface(
               :lower_backed_command_semantic_failure
             )

    assert result.case == :lower_backed_command_semantic_failure
    assert result.tenant_id == "tenant-app-kit-lower-backed-semantic-failure"

    assert result.dispatch.classification == :semantic_failure
    assert result.dispatch.execution_state == :failed
    assert result.dispatch.failure_kind == :semantic_failure
    assert result.dispatch.job_status == :completed

    assert result.recovery.work_state == "awaiting_review"
    assert result.recovery.active_run_state == "failed"
    assert result.recovery.operator_lifecycle_state == "awaiting_review"
    assert result.recovery.review_status == "pending"
    assert result.recovery.review_recovery_kind == "semantic_failure"
    assert result.recovery.recovery_review_created?
    assert result.recovery.pending_review_ids == [result.recovery.review_id]
    assert result.recovery.operator_pending_decision_ids == [result.recovery.review_id]
    assert "run_failed" in result.recovery.timeline_kinds
    assert "review_created" in result.recovery.timeline_kinds

    assert "execution_record" in result.trace.step_sources
    assert "audit_fact" in result.trace.step_sources
    assert result.trace.failed_execution.dispatch_state == :failed
    assert result.trace.failed_execution.failure_kind == :semantic_failure
    assert result.trace.failed_execution.semantic_failure_kind == "semantic_insufficient_context"
    assert result.trace.failed_execution.semantic_failure_retry_class == "clarification_required"
    assert result.trace.failed_execution.semantic_failure_trace_id == result.trace.trace_id
  end

  test "app-kit operational surface proves Scenario 24 leased direct read and stream invalidation against the live substrate" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_app_kit_operational_surface(
               :leased_direct_read_and_stream_invalidation
             )

    assert result.case == :leased_direct_read_and_stream_invalidation
    assert result.scenario == 24
    assert result.tenant_id == "tenant-app-kit-leased-read-stream"
    assert result.disconnect_window_ms == 10_000

    assert result.concurrent_burst.invalidation_count == 100
    assert result.concurrent_burst.requested_connection_count == 10
    assert result.concurrent_burst.repo_pool_size == 10
    assert result.concurrent_burst.contiguous_sequences?
    assert length(Enum.uniq(result.concurrent_burst.sequence_numbers)) == 100

    assert result.disconnected_stream.attached_cursor == 0

    assert String.starts_with?(
             result.disconnected_stream.reconnect_invalidation_reason,
             "disconnect_burst_"
           )

    assert result.direct_read.submission_key
    assert result.direct_read.submission_receipt_ref

    assert result.live_stream.attached_cursor >=
             Enum.max(result.concurrent_burst.sequence_numbers)

    assert result.live_stream.invalidation_reason == "subject_paused"
    assert result.live_stream.invalidated_after_ms <= 4_000
    assert result.live_stream.post_pause_refusal_reason == "subject_paused"

    assert result.control_write.result_status == "paused"
    assert result.control_write.invalidated_live_leases?

    assert result.post_pause_read.code == :lease_invalidated
    assert result.post_pause_read.reason == "subject_paused"
  end

  test "app-kit operational surface returns an explicit authorization error for unauthorized lower-enriched trace reads" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_app_kit_operational_surface(
               :unauthorized_lower_trace_read
             )

    assert result.case == :unauthorized_lower_trace_read
    assert result.tenant_id == "tenant-app-kit-lower-backed-authz"
    assert result.error.code == "unauthorized_lower_read"
    assert result.error.kind == :authorization
    refute result.error.retryable
  end

  test "harness mix project does not depend on the deprecated mezzanine bridge package" do
    deps = HarnessMixProject.project()[:deps]

    refute Enum.any?(deps, fn
             {:mezzanine_app_kit_bridge, _opts} -> true
             {:mezzanine_app_kit_bridge, _requirement, _opts} -> true
             _other -> false
           end)
  end
end
