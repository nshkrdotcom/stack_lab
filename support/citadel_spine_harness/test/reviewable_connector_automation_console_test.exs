defmodule StackLab.CitadelSpineHarness.ReviewableConnectorAutomationConsoleTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 300_000

  alias StackLab.CitadelSpineHarness

  test "Scenario 42 proves a second synthetic product shape for reviewable connector automation" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_reviewable_connector_automation_console(
               :reviewable_connector_automation_console
             )

    assert result.case == :reviewable_connector_automation_console
    assert result.scenario == 42
    assert result.tenant_id == "tenant-reviewable-connector-automation"
    assert result.whitepaper_use_case == :"18.2_reviewable_connector_automation"

    assert result.synthetic_shape.surface_kind == :connector_automation_console
    assert result.synthetic_shape.differs_from == :single_product_operator_shell
    assert result.synthetic_shape.product_posture == :reviewable_connector_automation

    assert result.automation_case.subject_id in result.console.listed_subject_ids
    assert result.console.pending_review_ids_before == [result.review.decision_id]
    assert result.console.pending_review_ids_after == []
    assert result.console.recovery_review_created?

    assert result.automation_case.lifecycle_state_before_pause == "awaiting_review"
    assert result.automation_case.lifecycle_state_after_review == "awaiting_review"
    assert result.automation_case.blocker_kinds_before_pause == ["review_pending"]
    assert result.automation_case.blocker_kinds_after_review == ["operator_paused"]
    assert result.automation_case.next_step_kind_before_pause == "record_review_decision"
    assert result.automation_case.next_step_kind_after_review == "resume_subject"
    assert result.automation_case.pending_review_ids_before == [result.review.decision_id]
    assert result.automation_case.pending_review_ids_after == []
    assert is_binary(result.automation_case.lineage_execution_ref_before_pause)
    assert is_binary(result.automation_case.lineage_execution_ref_after_review)

    assert "pause" in result.operator.available_action_kinds
    assert result.operator.applied_action == "pause"
    assert result.operator.action_status == :completed
    assert result.operator.invalidated_live_leases?

    assert result.review.status_before == "pending"
    assert result.review.status_after == "accepted"
    assert result.review.recovery_kind == "semantic_failure"
    assert result.review.action_kind == "review_accept"

    assert result.lower_access.submission_key
    assert result.lower_access.submission_receipt_ref
    assert result.lower_access.stream_attached_cursor == 0
    assert result.lower_access.post_pause_read.code == :lease_invalidated
    assert result.lower_access.post_pause_read.reason == "subject_paused"
    assert result.lower_access.post_pause_stream.code == :lease_invalidated
    assert result.lower_access.post_pause_stream.reason == "subject_paused"

    assert result.trace.trace_id
    assert result.trace.lower_lineage.lower_run_id
    assert "audit_fact" in result.trace.step_sources
    assert "execution_record" in result.trace.step_sources
    assert "decision_record" in result.trace.step_sources
    assert "lower_run_status" in result.trace.step_sources
    assert result.trace.failed_execution.dispatch_state == :failed
    assert result.trace.failed_execution.failure_kind == :semantic_failure
  end
end
