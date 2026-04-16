defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurfaceTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness

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
    assert result.control.state == :waiting_review
    assert result.control.run_id == result.work.detail_active_run_id
    assert result.control.review_unit_id in result.work.detail_pending_reviews

    assert result.operator.current_execution_ref == result.control.run_id
    assert result.operator.chosen_action == result.operator.applied_action
    assert "run_scheduled" in result.operator.timeline_kinds

    assert result.review.pending_ids_before == [result.control.review_unit_id]
    assert result.review.pending_ids_after == []
    assert result.review.status_before == "pending"
    assert result.review.status_after == "accepted"
    assert result.review.action_kind == "review_accept"

    assert result.trace.execution_id
    assert result.trace.trace_id
    assert "audit_fact" in result.trace.step_sources
    assert "execution_record" in result.trace.step_sources
    assert "decision_record" in result.trace.step_sources
    assert "evidence_record" in result.trace.step_sources
    assert "lower_run_status" in result.trace.step_sources

    assert_received {:lower_fetch_run, _run_id}
    assert_received {:lower_events, _run_id}
    assert_received {:lower_attempts, _run_id}
    assert_received {:lower_run_artifacts, _run_id}
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
    assert result.dispatch.outbox_status == :completed
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
end
