defmodule StackLab.CitadelSpineHarness.TemporalPostgresProjectionDriftTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "scenario 201 proves compact Temporal/Postgres drift classification and safe actions" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_temporal_postgres_projection_drift(
               :temporal_postgres_projection_drift
             )

    assert result.case == :temporal_postgres_projection_drift
    assert result.scenario == 201
    assert result.runbook == "runbooks/temporal_postgres_projection_drift.md"
    assert result.release_manifest_ref == "targeted_proofs[0]/stack_lab_runtime_envelopes[0]"
    assert result.runtime_envelope.runtime_class == :temporal_postgres_integration
    assert result.runtime_envelope.expected_local_max_ms == 120_000
    assert result.runtime_envelope.ci_timeout_ms == 180_000

    assert result.positive_path.compact_temporal_lookup.lookup_operations == [
             :describe_workflow,
             :query_workflow
           ]

    refute result.positive_path.compact_temporal_lookup.raw_history?
    assert result.positive_path.compact_temporal_lookup.query_name == "execution.lifecycle_state"
    assert result.positive_path.active_projection.safe_operator_action == :projection_only

    assert result.positive_path.temporal_terminal_projection.safe_operator_action ==
             :project_temporal_terminal

    assert result.positive_path.temporal_terminal_projection.terminal_event_ref ==
             "event-terminal"

    assert result.positive_path.outbox_drain_plan.start_authority ==
             :mezzanine_workflow_runtime_idempotency

    assert result.positive_path.outbox_drain_plan.legacy_worker_allowed? == false

    assert result.positive_path.outbox_drain_plan.evidence_only_states == [
             "started",
             "duplicate_started"
           ]

    refute result.positive_path.dispatch_state_reduction.new_legacy_writes_allowed?

    assert result.positive_path.dispatch_state_reduction.active_targets == [
             :queued,
             :in_flight,
             :accepted_active
           ]

    assert result.positive_path.dispatch_state_reduction.legacy_aliases.dispatching_retry ==
             :in_flight

    assert result.positive_path.dispatch_state_reduction.legacy_aliases.running ==
             :accepted_active
  end

  test "scenario 201 negative fixtures cover every required drift stop condition" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_temporal_postgres_projection_drift(
               :temporal_postgres_projection_drift
             )

    assert Enum.map(result.negative_failures.drift_actions, & &1.drift_class) == [
             :projection_lag,
             :orphan_projection,
             :orphan_workflow,
             :conflicting_terminal,
             :version_skew
           ]

    assert Enum.all?(result.negative_failures.drift_actions, &Map.has_key?(&1, :automatic_repair))
    assert Enum.all?(result.negative_failures.drift_actions, &Map.has_key?(&1, :operator_repair))

    assert Enum.all?(
             result.negative_failures.drift_actions,
             &Map.has_key?(&1, :safe_operator_action)
           )

    assert result.negative_failures.conflicting_terminal.reason ==
             :postgres_terminal_closes_active_workflow

    assert result.negative_failures.conflicting_terminal.safe_operator_action ==
             :signal_or_quarantine

    assert result.negative_failures.missing_terminal_event_ref.reason ==
             :missing_temporal_terminal_event_ref

    assert result.negative_failures.missing_terminal_event_ref.safe_operator_action ==
             :quarantine_projection

    assert result.negative_failures.workflow_start_outbox_bypass.legacy_direct_enqueue ==
             %{
               accepted?: false,
               forbidden_worker_authority: :workflow_lifecycle_decision,
               safe_action: :quarantine_or_dead_letter
             }

    assert result.negative_failures.workflow_start_outbox_bypass.oban_lifecycle_worker.accepted? ==
             false

    assert result.negative_failures.workflow_start_outbox_bypass.workflow_runtime_adapter.accepted?

    assert result.negative_failures.workflow_start_outbox_bypass.started_state_authority ==
             :delivery_evidence_only

    assert Enum.all?(result.negative_failures.unreduced_dispatch_states, fn
             {_legacy_state, evidence} ->
               evidence.writable? == false and
                 evidence.safe_action == :read_through_alias_until_live_rows_drain
           end)
  end

  test "scenario 201 fanout/fanin evidence keeps one close decision under duplicate and late completions" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_temporal_postgres_projection_drift(
               :temporal_postgres_projection_drift
             )

    assert result.positive_path.fanout_fanin.status == :closed
    assert result.positive_path.fanout_fanin.close_count == 1
    assert result.positive_path.fanout_fanin.close_decision == :succeeded
    assert result.positive_path.fanout_fanin.duplicate_close_count == 1
    assert result.positive_path.fanout_fanin.duplicate_completion_count == 1
    refute Map.fetch!(result.positive_path.fanout_fanin.operator_query, :raw_payload?)

    assert result.negative_failures.fanout_late_duplicate_close.close_count == 1
    assert result.negative_failures.fanout_late_duplicate_close.close_decision == :succeeded
    assert result.negative_failures.fanout_late_duplicate_close.duplicate_completion_count == 1
    assert result.negative_failures.fanout_late_duplicate_close.late_completion_count == 1

    assert %{
             event_type: :late_completion_evidence,
             branch_ref: "branch-b",
             attempted_status: :failed,
             close_decision: :succeeded,
             close_count: 1
           } = result.negative_failures.fanout_late_duplicate_close.late_event
  end
end
