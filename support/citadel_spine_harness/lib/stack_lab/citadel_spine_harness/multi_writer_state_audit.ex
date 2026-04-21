defmodule StackLab.CitadelSpineHarness.MultiWriterStateAudit do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  @scenario "203B"
  @runbook "runbooks/multi_writer_state_audit.md"
  @release_manifest_ref "targeted_proofs[5]/stack_lab_runtime_envelopes[5]"
  @required_writer_fields [
    :surface,
    :owner_repo,
    :owner_module,
    :canonical_owner,
    :state_class,
    :participant_roles,
    :writer_roles,
    :authorized_mutation_path,
    :read_projection_paths,
    :coordinator_ref,
    :idempotency_or_source_position,
    :merge_mode,
    :conflict_policy,
    :late_result_policy,
    :projection_rebuild_source,
    :local_ephemeral_boundary,
    :authority_refs,
    :tenant_ref,
    :trace_ref,
    :release_manifest_ref
  ]

  @runtime_envelope %{
    runtime_class: :source_integration,
    expected_local_max_ms: 20_000,
    ci_timeout_ms: 30_000,
    measurement_scope: :jido_hive_source_surface_audit_under_stack_lab_harness,
    timeout_safe_action: :fail_milestone_and_capture_jido_hive_surface_sources
  }

  @spec run_case(:multi_writer_state_audit) :: {:ok, map()} | {:error, term()}
  def run_case(:multi_writer_state_audit) do
    roots = CitadelSpineHarness.repo_roots()

    with {:ok, sources} <- load_sources(roots.jido_hive) do
      {:ok,
       %{
         case: :multi_writer_state_audit,
         scenario: @scenario,
         runbook: @runbook,
         release_manifest_ref: @release_manifest_ref,
         runtime_envelope: @runtime_envelope,
         source_root: roots.jido_hive,
         required_writer_fields: @required_writer_fields,
         positive_path: %{
           writer_mode_matrix: writer_mode_matrix(),
           server_serialization: server_serialization_evidence(sources),
           append_only_event_log: append_only_event_log_evidence(sources),
           client_local_ephemeral: client_local_ephemeral_evidence(sources),
           worker_local_ephemeral: worker_local_ephemeral_evidence(sources),
           derived_projection: derived_projection_evidence(sources),
           collaborative_document_absence: collaborative_document_absence_evidence(sources)
         },
         negative_failures: negative_failure_evidence()
       }}
    end
  end

  defp load_sources(jido_hive_root) do
    files = %{
      room_server: "jido_hive_server/lib/jido_hive_server/collaboration/room_server.ex",
      event_reducer: "jido_hive_server/lib/jido_hive_server/collaboration/event_reducer.ex",
      persistence: "jido_hive_server/lib/jido_hive_server/persistence.ex",
      client_room_session: "jido_hive_client/lib/jido_hive_client/room_session.ex",
      client_embedded: "jido_hive_client/lib/jido_hive_client/embedded.ex",
      client_session_state: "jido_hive_client/lib/jido_hive_client/session_state.ex",
      client_room_api: "jido_hive_client/lib/jido_hive_client/boundary/room_api.ex",
      worker_relay: "jido_hive_worker_runtime/lib/jido_hive_worker_runtime/relay_worker.ex",
      worker_runtime_state:
        "jido_hive_worker_runtime/lib/jido_hive_worker_runtime/runtime/state.ex",
      worker_server_api:
        "jido_hive_worker_runtime/lib/jido_hive_worker_runtime/boundary/server_api.ex",
      context_graph_readme: "jido_hive_context_graph/README.md"
    }

    files
    |> Enum.reduce_while({:ok, %{}}, fn {key, relative_path}, {:ok, acc} ->
      path = Path.join(jido_hive_root, relative_path)

      case File.read(path) do
        {:ok, body} -> {:cont, {:ok, Map.put(acc, key, body)}}
        {:error, reason} -> {:halt, {:error, {:missing_jido_hive_source, relative_path, reason}}}
      end
    end)
  end

  defp writer_mode_matrix do
    [
      writer_row(%{
        surface: :platform_session_boundary_attach_approval_run_lease_aggregates,
        owner_repo: :mezzanine,
        owner_module: :platform_owner_modules,
        canonical_owner: :exclusive_lease_or_temporal_workflow_owner,
        state_class: :exclusive_lease_authoritative,
        participant_roles: [:operator, :workflow_worker, :runtime_worker],
        writer_roles: [:lease_holder, :workflow_owner],
        authorized_mutation_path: :owner_command_with_lease_fence_epoch_or_workflow_signal,
        read_projection_paths: [:postgres_projection, :workflow_query],
        coordinator_ref: :lease_fence_epoch_or_workflow_id,
        idempotency_or_source_position: :owner_command_idempotency_key,
        merge_mode: :none,
        conflict_policy: :reject_without_matching_owner_fence_epoch_or_workflow_ref,
        late_result_policy: :evidence_only_or_compensation_after_owner_close,
        projection_rebuild_source: :temporal_or_owner_event_source,
        local_ephemeral_boundary: :none,
        authority_refs: [:m2aa, :m2ab, :m2ac, :m2ad, :m2ae, :m2ag, :m2ah],
        tenant_ref: :tenant_authority_scope,
        trace_ref: :phase5_trace_id
      }),
      writer_row(%{
        surface: :jido_hive_canonical_room_truth,
        owner_repo: :jido_hive,
        owner_module: JidoHiveServer.Collaboration.RoomServer,
        canonical_owner: :room_server_genserver,
        state_class: :server_serialized_multi_participant,
        participant_roles: [:human_operator, :worker_runtime, :server_policy],
        writer_roles: [:room_server],
        authorized_mutation_path: :room_server_call_to_event_reducer_and_persistence,
        read_projection_paths: [:room_snapshot_api, :room_events_api],
        coordinator_ref: :room_id_registry_name,
        idempotency_or_source_position: :room_id_event_sequence_and_contribution_id,
        merge_mode: :server_serialized_reduce,
        conflict_policy: :server_reducer_rejects_invalid_or_unsupported_transition,
        late_result_policy: :late_result_must_enter_server_as_contribution_or_remain_evidence,
        projection_rebuild_source: :room_event_log,
        local_ephemeral_boundary: :client_and_worker_snapshots_not_authoritative,
        authority_refs: [:phase5_m2e_source_static_proof, :scenario_203b],
        tenant_ref: :room_workspace_scope,
        trace_ref: :room_event_sequence
      }),
      writer_row(%{
        surface: :jido_hive_room_event_log,
        owner_repo: :jido_hive,
        owner_module: JidoHiveServer.Persistence,
        canonical_owner: :room_server_persistence_transaction,
        state_class: :append_only_multi_writer,
        participant_roles: [:human_operator, :worker_runtime, :server_policy],
        writer_roles: [:room_server],
        authorized_mutation_path: :persist_room_transition_after_room_server_reduce,
        read_projection_paths: [:list_room_events_after, :list_contributions],
        coordinator_ref: :room_server_genserver,
        idempotency_or_source_position: :room_id_and_monotonic_event_sequence,
        merge_mode: :append_after_server_serialization,
        conflict_policy: :database_insert_conflict_or_reducer_rejection,
        late_result_policy: :append_only_evidence_after_server_acceptance_only,
        projection_rebuild_source: :room_event_log,
        local_ephemeral_boundary: :none,
        authority_refs: [:phase5_m2e_source_static_proof, :scenario_203b],
        tenant_ref: :room_workspace_scope,
        trace_ref: :room_event_sequence
      }),
      writer_row(%{
        surface: :participant_session_availability_registry,
        owner_repo: :jido_hive,
        owner_module: JidoHiveServer.Collaboration.ParticipantSessionRegistry,
        canonical_owner: :server_registry_for_availability_only,
        state_class: :server_serialized_multi_participant,
        participant_roles: [:human_operator, :worker_runtime],
        writer_roles: [:server_presence_path],
        authorized_mutation_path: :server_registry_update_not_room_truth_mutation,
        read_projection_paths: [:room_dispatch_context],
        coordinator_ref: :server_registry_process,
        idempotency_or_source_position: :participant_target_id,
        merge_mode: :last_seen_availability_only,
        conflict_policy: :cannot_override_room_event_truth,
        late_result_policy: :stale_presence_does_not_mutate_room_truth,
        projection_rebuild_source: :current_server_presence,
        local_ephemeral_boundary: :availability_not_canonical_room_state,
        authority_refs: [:phase5_m2e_source_static_proof, :scenario_203b],
        tenant_ref: :room_workspace_scope,
        trace_ref: :participant_id
      }),
      writer_row(%{
        surface: :jido_hive_client_room_session_state,
        owner_repo: :jido_hive,
        owner_module: JidoHiveClient.RoomSession,
        canonical_owner: :client_process_only,
        state_class: :client_or_worker_local_ephemeral,
        participant_roles: [:human_operator],
        writer_roles: [:client_session_process],
        authorized_mutation_path: :room_api_submit_contribution_to_server,
        read_projection_paths: [:client_snapshot, :polling_room_events],
        coordinator_ref: :server_room_api,
        idempotency_or_source_position: :operation_id,
        merge_mode: :local_view_refresh_from_server,
        conflict_policy: :client_local_state_cannot_override_server_truth,
        late_result_policy: :async_submit_failure_remains_local_until_server_accepts,
        projection_rebuild_source: :server_room_snapshot_and_events,
        local_ephemeral_boundary: :session_state_and_operation_cache,
        authority_refs: [:phase5_m2e_source_static_proof, :scenario_203b],
        tenant_ref: :client_workspace_scope,
        trace_ref: :operation_id
      }),
      writer_row(%{
        surface: :jido_hive_worker_runtime_state,
        owner_repo: :jido_hive,
        owner_module: JidoHiveWorkerRuntime.RelayWorker,
        canonical_owner: :worker_process_only,
        state_class: :client_or_worker_local_ephemeral,
        participant_roles: [:worker_runtime],
        writer_roles: [:worker_runtime_process],
        authorized_mutation_path: :phoenix_channel_contribution_submit_to_server,
        read_projection_paths: [:worker_runtime_snapshot, :server_room_events_api],
        coordinator_ref: :server_room_channel,
        idempotency_or_source_position: :assignment_id_and_contribution_id,
        merge_mode: :local_status_refresh_from_server,
        conflict_policy: :worker_local_state_cannot_override_server_truth,
        late_result_policy: :late_assignment_result_submits_to_server_or_records_local_failure,
        projection_rebuild_source: :server_room_events,
        local_ephemeral_boundary: :runtime_status_and_recent_assignment_cache,
        authority_refs: [:phase5_m2e_source_static_proof, :scenario_203b],
        tenant_ref: :worker_workspace_scope,
        trace_ref: :assignment_id
      }),
      writer_row(%{
        surface: :jido_hive_context_graph_provenance_views,
        owner_repo: :jido_hive,
        owner_module: JidoHiveContextGraph,
        canonical_owner: :derived_projection_package,
        state_class: :derived_projection_or_cache,
        participant_roles: [:operator, :web_surface, :tui_surface],
        writer_roles: [:projection_builder],
        authorized_mutation_path: :rebuild_from_authoritative_room_truth,
        read_projection_paths: [:graph_helpers, :workflow_summary],
        coordinator_ref: :authoritative_room_server_source,
        idempotency_or_source_position: :room_event_sequence,
        merge_mode: :derived_dedupe_only,
        conflict_policy: :projection_cannot_create_room_truth,
        late_result_policy: :projection_rebuild_after_source_event_arrives,
        projection_rebuild_source: :jido_hive_server_room_truth,
        local_ephemeral_boundary: :operator_facing_projection_only,
        authority_refs: [:phase5_m2e_source_static_proof, :scenario_203b],
        tenant_ref: :room_workspace_scope,
        trace_ref: :room_event_sequence
      }),
      writer_row(%{
        surface: :true_collaborative_document_state,
        owner_repo: :none_active,
        owner_module: nil,
        canonical_owner: :not_enabled_in_phase5,
        state_class: :collaborative_document,
        participant_roles: [],
        writer_roles: [],
        authorized_mutation_path: :forbidden_until_source_owner_and_merge_mechanics_exist,
        read_projection_paths: [],
        coordinator_ref: :missing_by_design,
        idempotency_or_source_position: :required_before_enablement,
        merge_mode: :not_active,
        conflict_policy: :reject_ot_crdt_or_collaborative_claims_without_source_mechanics,
        late_result_policy: :not_applicable,
        projection_rebuild_source: :not_applicable,
        local_ephemeral_boundary: :not_applicable,
        authority_refs: [:scenario_203b_stop_condition],
        tenant_ref: :not_applicable,
        trace_ref: :not_applicable
      })
    ]
  end

  defp writer_row(row) do
    Map.put(row, :release_manifest_ref, @release_manifest_ref)
  end

  defp server_serialization_evidence(sources) do
    %{
      room_server_uses_genserver?: contains?(sources.room_server, "use GenServer"),
      submit_contribution_enters_genserver_call?:
        contains?(
          sources.room_server,
          "GenServer.call(server, {:submit_contribution, attrs})"
        ),
      contribution_handle_call_reduces_before_persist?:
        contains_all?(sources.room_server, [
          "def handle_call({:submit_contribution, attrs}",
          "apply_requests(state.snapshot",
          "persist_and_broadcast(snapshot, events)"
        ]),
      replay_uses_event_log_checkpoint?:
        contains_all?(sources.room_server, [
          "Persistence.list_room_events_after",
          "snapshot.replay.checkpoint_event_sequence",
          "apply_event_with_policy"
        ]),
      reducer_handles_multi_participant_events?:
        contains_all?(sources.event_reducer, [
          ":participant_joined",
          ":participant_left",
          ":assignment_completed",
          ":contribution_submitted"
        ]),
      reducer_advances_event_clock?:
        contains_all?(sources.event_reducer, [
          "defp advance_event_clock",
          "snapshot.clocks.next_event_sequence"
        ])
    }
  end

  defp append_only_event_log_evidence(sources) do
    %{
      transition_persists_events_in_transaction?:
        contains_all?(sources.persistence, [
          "def persist_room_transition",
          "Repo.transaction(fn ->",
          "Enum.each(events",
          "insert_room_event_record()"
        ]),
      snapshot_upsert_is_projection_of_compacted_truth?:
        contains_all?(sources.persistence, [
          "compact_snapshot(snapshot)",
          "RoomSnapshotRecord.changeset(snapshot_attrs)",
          "conflict_target: :room_id"
        ]),
      event_replay_reads_after_sequence?:
        contains_all?(sources.persistence, [
          "def list_room_events_after",
          "record.sequence > ^checkpoint_sequence",
          "order_by([record], asc: record.sequence)"
        ]),
      contribution_projection_filters_event_log?:
        contains_all?(sources.persistence, [
          "def list_contributions",
          "list_room_events_after(room_id, after_sequence",
          "&(&1.type == :contribution_submitted)"
        ])
    }
  end

  defp client_local_ephemeral_evidence(sources) do
    %{
      room_session_delegates_to_embedded_process?:
        contains_all?(sources.client_room_session, [
          "alias JidoHiveClient.Embedded",
          "def start_link(opts), do: Embedded.start_link(opts)",
          "def snapshot(session), do: Embedded.snapshot(session)"
        ]),
      embedded_state_is_process_local?:
        contains_all?(sources.client_embedded, [
          "use GenServer",
          "defstruct",
          "session_state:",
          "submit_operations:"
        ]),
      client_submits_through_room_api?:
        contains_all?(sources.client_embedded, [
          "state.room_api.submit_contribution",
          "room_api_submit_opts"
        ]),
      session_state_has_local_metrics_and_error_only?:
        contains_all?(sources.client_session_state, [
          "connection_status:",
          "metrics:",
          "last_error:",
          "def snapshot"
        ]),
      client_boundary_has_no_server_persistence_import?:
        not_contains_any?(sources.client_room_session <> sources.client_embedded, [
          "JidoHiveServer.Persistence",
          "RoomServer",
          "persist_room_transition"
        ]),
      room_api_boundary_is_http_operator_submission?:
        contains_all?(sources.client_room_api, ["@callback submit_contribution"]) and
          contains?(sources.client_embedded, "state.room_api.submit_contribution")
    }
  end

  defp worker_local_ephemeral_evidence(sources) do
    %{
      relay_worker_is_process_local?:
        contains_all?(sources.worker_relay, [
          "use GenServer",
          "room_channels:",
          "connection_state:",
          "current_event_sequence"
        ]),
      relay_pushes_contribution_over_room_channel?:
        contains_all?(sources.worker_relay, [
          "defp push_contribution",
          "\"contribution.submit\"",
          "%{\"data\" => contribution}"
        ]),
      worker_runtime_state_is_status_cache?:
        contains_all?(sources.worker_runtime_state, [
          "connection_status:",
          "current_assignment:",
          "recent_assignments:",
          "last_error:"
        ]),
      worker_server_api_is_read_presence_boundary?:
        contains_all?(sources.worker_server_api, [
          "@callback list_rooms",
          "@callback list_room_events",
          "@callback upsert_target",
          "@callback mark_target_offline"
        ]),
      worker_has_no_server_persistence_import?:
        not_contains_any?(sources.worker_relay <> sources.worker_runtime_state, [
          "JidoHiveServer.Persistence",
          "JidoHiveServer.Collaboration.RoomServer",
          "persist_room_transition"
        ])
    }
  end

  defp derived_projection_evidence(sources) do
    %{
      context_graph_declares_no_authoritative_room_truth?:
        contains?(
          sources.context_graph_readme,
          "It does not own authoritative room truth. That remains in `jido_hive_server`."
        ),
      context_graph_responsibilities_are_projection_only?:
        contains_all?(sources.context_graph_readme, [
          "materialize graph objects from room contributions",
          "build adjacency and provenance projections",
          "rebuild duplicate/staleness annotations",
          "derive workflow summary data from the graph projection"
        ])
    }
  end

  defp collaborative_document_absence_evidence(sources) do
    inspected =
      sources.room_server <>
        sources.event_reducer <>
        sources.persistence <>
        sources.client_embedded <>
        sources.worker_relay <>
        sources.context_graph_readme

    %{
      accepted?: false,
      state_class: :collaborative_document,
      absent_terms: ["collaborative_document", "CRDT", "operation log", "causal metadata"],
      source_contains_collaborative_document_terms?:
        contains_any?(inspected, [
          "collaborative_document",
          "CRDT",
          "operation log",
          "causal metadata"
        ]),
      safe_action: :reject_until_owner_merge_mechanics_and_conflict_policy_are_source_owned
    }
  end

  defp negative_failure_evidence do
    %{
      exclusive_lease_multi_writer_conflation:
        rejected(
          :exclusive_lease_multi_writer_conflation,
          :exclusive_lease_authoritative,
          :server_serialized_multi_participant,
          :split_surface_or_require_single_owner_fence_epoch
        ),
      client_room_session_canonical_truth:
        rejected(
          :client_room_session_canonical_truth,
          :client_or_worker_local_ephemeral,
          :server_serialized_multi_participant,
          :submit_to_room_server_and_refresh_from_server_projection
        ),
      worker_direct_room_truth:
        rejected(
          :worker_direct_room_truth,
          :client_or_worker_local_ephemeral,
          :server_serialized_multi_participant,
          :submit_contribution_to_room_channel_or_record_local_failure
        ),
      direct_participant_persistence_bypass:
        rejected(
          :direct_participant_persistence_bypass,
          :append_only_multi_writer,
          :server_serialized_multi_participant,
          :route_every_room_transition_through_room_server_reducer
        ),
      late_worker_result_direct_mutation:
        rejected(
          :late_worker_result_direct_mutation,
          :client_or_worker_local_ephemeral,
          :append_only_multi_writer,
          :server_acceptance_or_evidence_only_late_result
        ),
      ot_crdt_claim_without_source_owner:
        rejected(
          :ot_crdt_claim_without_source_owner,
          :collaborative_document,
          :collaborative_document,
          :reject_until_source_owner_merge_mechanics_exist
        ),
      projection_as_canonical_truth:
        rejected(
          :projection_as_canonical_truth,
          :derived_projection_or_cache,
          :server_serialized_multi_participant,
          :rebuild_projection_from_authoritative_room_truth
        )
    }
  end

  defp rejected(reason, claimed_class, required_class, safe_action) do
    %{
      accepted?: false,
      reason: reason,
      claimed_state_class: claimed_class,
      required_state_class: required_class,
      safe_action: safe_action,
      release_manifest_ref: @release_manifest_ref
    }
  end

  defp contains_all?(body, patterns), do: Enum.all?(patterns, &contains?(body, &1))
  defp contains_any?(body, patterns), do: Enum.any?(patterns, &contains?(body, &1))
  defp not_contains_any?(body, patterns), do: not contains_any?(body, patterns)
  defp contains?(body, pattern), do: String.contains?(body, pattern)
end
