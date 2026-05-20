defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.EvidenceWriter do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support

  for {name, arity} <- [
        lower_backed_dispatch: 4,
        dispatch_through_citadel!: 5,
        acceptance_payload: 3,
        rejection_payload: 1,
        hydrate_run_intent!: 1,
        binding_snapshot_for: 2,
        validate_lower_backed_claim!: 5,
        await_transport_result!: 0,
        transport_acceptance: 2,
        transport_rejection: 2,
        rejection_reason: 1,
        lower_receipt_proof!: 4,
        handle_observability_telemetry: 4,
        attach_observability_telemetry!: 2,
        collect_observability_telemetry!: 0,
        collect_observability_telemetry!: 1,
        summarize_observability_telemetry!: 1,
        fetch_events!: 2,
        fetch_one_event!: 2,
        collect_lower_fetch_messages!: 0,
        collect_lower_fetch_messages!: 1,
        emit_execution_plane_backfill!: 2,
        emit_citadel_trace_failure!: 3,
        assert_archived_hot_reads!: 4,
        assert_archived_result!: 3,
        archived_surface_result!: 3,
        direct_submission_receipt_read!: 2,
        emit_stream_invalidation_burst!: 3,
        ensure_disconnect_window_elapsed!: 2,
        await_stream_attached!: 1,
        await_stream_attached!: 2,
        await_stream_invalidated!: 2,
        ensure_no_stream_attached!: 1,
        wait_for_stream_host_shutdown!: 1,
        contiguous_sequence?: 1,
        normalize_read_error: 1,
        lease_invalidated?: 1,
        leases_invalidated?: 1,
        execution_trace_step!: 2,
        trace_step_execution_id: 1
      ] do
    args = Macro.generate_arguments(arity, __MODULE__)
    defdelegate unquote(name)(unquote_splicing(args)), to: Support
  end
end
