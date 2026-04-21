defmodule StackLab.CitadelSpineHarness.MultiWriterStateAuditTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "scenario 203B classifies every multi-writer state surface with authority fields" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_multi_writer_state_audit(:multi_writer_state_audit)

    assert result.case == :multi_writer_state_audit
    assert result.scenario == "203B"
    assert result.runbook == "runbooks/multi_writer_state_audit.md"
    assert result.release_manifest_ref == "targeted_proofs[5]/stack_lab_runtime_envelopes[5]"
    assert result.runtime_envelope.runtime_class == :source_integration
    assert result.runtime_envelope.expected_local_max_ms == 20_000
    assert result.runtime_envelope.ci_timeout_ms == 30_000

    matrix = result.positive_path.writer_mode_matrix
    assert length(matrix) == 8

    assert Enum.all?(matrix, fn row ->
             Enum.all?(result.required_writer_fields, &Map.has_key?(row, &1))
           end)

    assert matrix |> Enum.map(& &1.state_class) |> Enum.uniq() |> Enum.sort() == [
             :append_only_multi_writer,
             :client_or_worker_local_ephemeral,
             :collaborative_document,
             :derived_projection_or_cache,
             :exclusive_lease_authoritative,
             :server_serialized_multi_participant
           ]

    assert Enum.find(matrix, &(&1.surface == :true_collaborative_document_state)).merge_mode ==
             :not_active
  end

  test "scenario 203B proves Jido Hive room truth stays server serialized" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_multi_writer_state_audit(:multi_writer_state_audit)

    server = result.positive_path.server_serialization
    assert server.room_server_uses_genserver?
    assert server.submit_contribution_enters_genserver_call?
    assert server.contribution_handle_call_reduces_before_persist?
    assert server.replay_uses_event_log_checkpoint?
    assert server.reducer_handles_multi_participant_events?
    assert server.reducer_advances_event_clock?

    event_log = result.positive_path.append_only_event_log
    assert event_log.transition_persists_events_in_transaction?
    assert event_log.snapshot_upsert_is_projection_of_compacted_truth?
    assert event_log.event_replay_reads_after_sequence?
    assert event_log.contribution_projection_filters_event_log?
  end

  test "scenario 203B rejects client, worker, projection, and OT/CRDT authority bypasses" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_multi_writer_state_audit(:multi_writer_state_audit)

    client = result.positive_path.client_local_ephemeral
    assert client.room_session_delegates_to_embedded_process?
    assert client.embedded_state_is_process_local?
    assert client.client_submits_through_room_api?
    assert client.session_state_has_local_metrics_and_error_only?
    assert client.client_boundary_has_no_server_persistence_import?
    assert client.room_api_boundary_is_http_operator_submission?

    worker = result.positive_path.worker_local_ephemeral
    assert worker.relay_worker_is_process_local?
    assert worker.relay_pushes_contribution_over_room_channel?
    assert worker.worker_runtime_state_is_status_cache?
    assert worker.worker_server_api_is_read_presence_boundary?
    assert worker.worker_has_no_server_persistence_import?

    projection = result.positive_path.derived_projection
    assert projection.context_graph_declares_no_authoritative_room_truth?
    assert projection.context_graph_responsibilities_are_projection_only?

    collaborative = result.positive_path.collaborative_document_absence
    refute collaborative.accepted?
    refute collaborative.source_contains_collaborative_document_terms?
    assert collaborative.state_class == :collaborative_document

    assert result.negative_failures.client_room_session_canonical_truth.safe_action ==
             :submit_to_room_server_and_refresh_from_server_projection

    assert result.negative_failures.worker_direct_room_truth.safe_action ==
             :submit_contribution_to_room_channel_or_record_local_failure

    assert result.negative_failures.direct_participant_persistence_bypass.safe_action ==
             :route_every_room_transition_through_room_server_reducer

    assert result.negative_failures.ot_crdt_claim_without_source_owner.safe_action ==
             :reject_until_source_owner_merge_mechanics_exist

    assert Enum.all?(Map.values(result.negative_failures), &(&1.accepted? == false))
  end
end
