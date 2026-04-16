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
end
