defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.LeasedDirectReadAndStreamInvalidation do
  @moduledoc false

  alias AppKit.Core.ExecutionRef
  alias AppKit.OperatorSurface
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.Leasing
  alias Mezzanine.OperatorCommands
  alias Mezzanine.StreamAttachHost

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.{
    Environment,
    EvidenceWriter
  }

  alias StackLab.CitadelSpineHarness.TransportRuntime

  @scenario_24_disconnect_window_ms 10_000
  @scenario_24_poll_interval_ms 250
  @scenario_24_burst_count 100
  @scenario_24_burst_concurrency 10
  @scenario_24_reconnect_timeout_ms 4_000

  import Environment
  import EvidenceWriter

  def run do
    with_lower_backed_runtime(
      :app_kit_leased_direct_read_and_stream_invalidation,
      "tenant-app-kit-leased-read-stream",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:ok, disconnected_stream_lease} =
          OperatorSurface.issue_stream_attach_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              poll_interval_ms: @scenario_24_poll_interval_ms,
              scope: %{"mode" => "disconnect_catchup"}
            )
          )

        disconnected_stream_lease_id = disconnected_stream_lease.lease_ref.id

        {:ok, disconnected_host} =
          StreamAttachHost.start_link(
            lease_id: disconnected_stream_lease_id,
            token: disconnected_stream_lease.attach_token,
            authorization_scope: authorization_scope!(disconnected_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        disconnected_attach_cursor = await_stream_attached!(disconnected_stream_lease_id)

        disconnect_started_at_ms = System.monotonic_time(:millisecond)
        :ok = GenServer.stop(disconnected_host, :normal)

        burst_rows =
          emit_stream_invalidation_burst!(
            disconnected_stream_lease_id,
            @scenario_24_burst_count,
            @scenario_24_burst_concurrency
          )

        ensure_disconnect_window_elapsed!(
          disconnect_started_at_ms,
          @scenario_24_disconnect_window_ms
        )

        {:ok, reconnect_host} =
          StreamAttachHost.start_link(
            lease_id: disconnected_stream_lease_id,
            token: disconnected_stream_lease.attach_token,
            authorization_scope: authorization_scope!(disconnected_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        reconnect_invalidation =
          await_stream_invalidated!(
            disconnected_stream_lease_id,
            @scenario_24_reconnect_timeout_ms
          )

        ensure_no_stream_attached!(disconnected_stream_lease_id)
        wait_for_stream_host_shutdown!(reconnect_host)

        {:ok, read_lease} =
          OperatorSurface.issue_read_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              allowed_operations: [:fetch_submission_receipt],
              scope: %{"mode" => "direct_receipt_read"}
            )
          )

        {:ok, live_stream_lease} =
          OperatorSurface.issue_stream_attach_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              poll_interval_ms: @scenario_24_poll_interval_ms,
              scope: %{"mode" => "live_stream"}
            )
          )

        live_stream_lease_id = live_stream_lease.lease_ref.id

        {:ok, live_host} =
          StreamAttachHost.start_link(
            lease_id: live_stream_lease_id,
            token: live_stream_lease.attach_token,
            authorization_scope: authorization_scope!(live_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        live_attach_cursor = await_stream_attached!(live_stream_lease_id)

        direct_read_before =
          direct_submission_receipt_read!(
            read_lease,
            lower_dispatch.acceptance.submission_key
          )

        pause_started_at_ms = System.monotonic_time(:millisecond)

        {:ok, pause_result} =
          OperatorCommands.pause(env.subject_ref.id,
            reason: "leased stream shutdown",
            trace_id: "trace-stage24-pause",
            causation_id: "cause-stage24-pause",
            actor_ref: %{kind: :operator}
          )

        live_stream_invalidation =
          await_stream_invalidated!(
            live_stream_lease_id,
            @scenario_24_reconnect_timeout_ms
          )

        live_stream_invalidated_after_ms =
          System.monotonic_time(:millisecond) - pause_started_at_ms

        wait_for_stream_host_shutdown!(live_host)

        post_pause_read_error =
          Leasing.authorize_read(
            authorization_scope!(read_lease),
            read_lease.lease_ref.id,
            read_lease.lease_token,
            :fetch_submission_receipt,
            repo: ExecutionRepo
          )

        {:ok, refused_live_host} =
          StreamAttachHost.start_link(
            lease_id: live_stream_lease_id,
            token: live_stream_lease.attach_token,
            authorization_scope: authorization_scope!(live_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        refused_live_invalidation =
          await_stream_invalidated!(
            live_stream_lease_id,
            @scenario_24_reconnect_timeout_ms
          )

        ensure_no_stream_attached!(live_stream_lease_id)
        wait_for_stream_host_shutdown!(refused_live_host)

        burst_sequence_numbers = Enum.map(burst_rows, & &1.sequence_number)
        pause_invalidated_ids = Map.get(pause_result.details, :invalidated_lease_ids, [])

        {:ok,
         %{
           case: :leased_direct_read_and_stream_invalidation,
           scenario: 24,
           tenant_id: env.tenant_id,
           installation_id: env.installation_ref.id,
           execution_id: lower_dispatch.execution.id,
           disconnect_window_ms: @scenario_24_disconnect_window_ms,
           direct_read: %{
             submission_key: direct_read_before.submission_key,
             submission_receipt_ref: direct_read_before.submission_receipt_ref
           },
           disconnected_stream: %{
             lease_id: disconnected_stream_lease_id,
             attached_cursor: disconnected_attach_cursor,
             reconnect_invalidation_reason: reconnect_invalidation.reason,
             reconnect_invalidation_sequence: reconnect_invalidation.sequence_number
           },
           concurrent_burst: %{
             invalidation_count: length(burst_rows),
             requested_connection_count: @scenario_24_burst_concurrency,
             repo_pool_size: ExecutionRepo.config()[:pool_size],
             sequence_numbers: burst_sequence_numbers,
             contiguous_sequences?:
               burst_sequence_numbers
               |> Enum.sort()
               |> contiguous_sequence?()
           },
           live_stream: %{
             lease_id: live_stream_lease_id,
             attached_cursor: live_attach_cursor,
             invalidation_reason: live_stream_invalidation.reason,
             invalidated_after_ms: live_stream_invalidated_after_ms,
             post_pause_refusal_reason: refused_live_invalidation.reason
           },
           control_write: %{
             result_status: pause_result.status,
             invalidated_lease_ids: pause_invalidated_ids,
             invalidated_live_leases?:
               Enum.all?(
                 [read_lease.lease_ref.id, live_stream_lease_id],
                 &(&1 in pause_invalidated_ids)
               )
           },
           post_pause_read: normalize_read_error(post_pause_read_error)
         }}
      end
    )
  end
end
