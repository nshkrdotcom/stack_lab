defmodule StackLab.CitadelSpineHarness.Stage12LoadReadiness do
  @moduledoc false

  alias Ecto.Adapters.SQL
  alias Mezzanine.Execution.Repo
  alias Mezzanine.RepoTelemetryBridge

  alias StackLab.CitadelSpineHarness.{
    AITraceClaimCheckTraceContinuity,
    AppKitOperationalSurface,
    MezzanineSubstrate,
    Stage9OrchestrationRecovery
  }

  @pool_query_concurrency 20
  @pool_query_sql "SELECT pg_sleep(0.05)"

  @spec run_case(
          :same_subject_callback_storm
          | :shared_repo_pressure_posture
          | :claim_check_degradation_and_compactness
        ) :: {:ok, map()}
  def run_case(:same_subject_callback_storm) do
    with {:ok, result} <- Stage9OrchestrationRecovery.run_case(:parallel_join_closure) do
      {:ok,
       %{
         case: :same_subject_callback_storm,
         callback_storm: %{
           subject_state: result.worker_integration.subject_after_join.lifecycle_state,
           barrier_status: result.worker_integration.barrier_after_join.status,
           completion_row_count: result.worker_integration.completion_row_count,
           duplicate_callback_count: length(result.worker_integration.duplicate_signal_results),
           duplicate_short_circuit_count: result.atomic_close.duplicate_progress_count,
           join_workflow_count: length(result.worker_integration.join_workflow_refs),
           join_transition_count: result.worker_integration.join_transition_count,
           trace_explainable?:
             result.worker_integration.join_transition_count == 1 and
               result.worker_integration.barrier_after_join.status == :closed and
               result.worker_integration.subject_after_join.lifecycle_state == "paid"
         }
       }}
    end
  end

  def run_case(:shared_repo_pressure_posture) do
    {:ok, pool_pressure} = prove_shared_repo_pool_pressure()
    {:ok, pause} = Stage9OrchestrationRecovery.run_case(:operator_pause_during_active_execution)
    {:ok, outage} = Stage9OrchestrationRecovery.run_case(:lower_gateway_outage_recovery)

    {:ok, startup} =
      Stage9OrchestrationRecovery.run_case(:startup_reconciliation_deduplication)

    {:ok, ambiguity} =
      Stage9OrchestrationRecovery.run_case(:restart_during_dispatch_ambiguity)

    {:ok, streams} =
      AppKitOperationalSurface.run_case(:leased_direct_read_and_stream_invalidation)

    oban_config = Application.fetch_env!(:mezzanine_execution_engine, Oban)
    queue_limits = normalize_queue_limits(oban_config[:queues] || [])

    {:ok,
     %{
       case: :shared_repo_pressure_posture,
       pool_pressure: pool_pressure,
       pause_saturation: %{
         paused_temporal_handoff_count: pause.saturation.paused_temporal_handoff_count,
         peer_dispatch_ok?: pause.saturation.peer_dispatch.worker_result == :ok,
         temporal_handoff_schedule_restored?: pause.resume.temporal_handoff_schedule_restored?
       },
       lower_dispatch_ambiguity: %{
         recovered_count: ambiguity.recovered_count,
         duplicate_replay_count: ambiguity.final_dispatch.duplicate_replay_count,
         unique_submission_count: ambiguity.final_dispatch.unique_submission_count
       },
       lower_gateway_outage: %{
         circuit_state_before_probe: outage.circuit_before_probe.state,
         circuit_state_after_probe: outage.circuit_after_probe.state,
         probe_results: outage.probe_results
       },
       startup_reconciliation: %{
         launcher_count: startup.launcher_count,
         reconcile_handoff_count: length(startup.reconcile_handoff_refs),
         summary_execution_ids: startup.summary_execution_ids
       },
       leased_stream_invalidation: %{
         invalidation_count: streams.concurrent_burst.invalidation_count,
         requested_connection_count: streams.concurrent_burst.requested_connection_count,
         repo_pool_size: streams.concurrent_burst.repo_pool_size,
         invalidated_after_ms: streams.live_stream.invalidated_after_ms
       },
       notifier_posture: %{
         notifier: inspect(oban_config[:notifier]),
         peer: oban_config[:peer],
         testing_mode: oban_config[:testing],
         queue_processing_enabled?: oban_config[:queues] != false,
         queue_limits: queue_limits,
         total_queue_limit: queue_limits |> Map.values() |> Enum.sum(),
         repo_pool_size: pool_pressure.repo_pool_size,
         session_semantics_required?: oban_config[:notifier] == Oban.Notifiers.Postgres
       },
       adr_0008: %{
         keep_shared_repo_joboutbox?: pool_pressure.checkout_timeout_count == 0,
         measured_evidence: %{
           queue_time_event_count: pool_pressure.queue_time_event_count,
           max_queue_time_ms: pool_pressure.max_queue_time_ms,
           checkout_timeout_count: pool_pressure.checkout_timeout_count,
           observed_handoff_rows: pause.saturation.paused_temporal_handoff_count
         },
         unmeasured_reopen_triggers: [
           "single tenant exceeds 1,000 executions per minute sustained",
           "Postgres primary CPU attributable to job traffic exceeds 40% sustained",
           "a second Postgres cluster comes online"
         ]
       }
     }}
  end

  def run_case(:claim_check_degradation_and_compactness) do
    {:ok, degradation} = AITraceClaimCheckTraceContinuity.run_case(:claim_check_degradation)

    {:ok, continuity} =
      AITraceClaimCheckTraceContinuity.run_case(:claim_check_trace_continuity)

    {:ok, observability} = AppKitOperationalSurface.run_case(:observability_trace_join_continuity)

    {:ok,
     %{
       case: :claim_check_degradation_and_compactness,
       degradation: degradation,
       compactness: %{
         hot_rows_claim_checked?:
           continuity.claim_check.run_input_claim_checked? and
             continuity.claim_check.run_result_claim_checked? and
             continuity.claim_check.attempt_output_claim_checked? and
             continuity.claim_check.terminal_event_claim_checked?,
         hot_rows_omit_large_payloads?:
           "request" not in continuity.claim_check.hot_row_shapes.input_keys and
             "inference_result" not in continuity.claim_check.hot_row_shapes.result_keys and
             "inference_result" not in continuity.claim_check.hot_row_shapes.output_keys,
         live_reference_counts: continuity.claim_check.live_reference_counts,
         archived_manifest_ref: observability.archival.manifest_ref,
         archived_hot_read_errors: observability.archival.hot_read_errors,
         archived_rows_removed_count:
           observability.telemetry.archival_rows_removed.measurements.count
       }
     }}
  end

  def handle_pool_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:stage12_pool_telemetry, event, measurements, metadata})
  end

  defp prove_shared_repo_pool_pressure do
    MezzanineSubstrate.with_store(:stage12_shared_repo_pool_pressure, fn _repo_config ->
      handler_id = "stack-lab-stage12-pool-#{System.unique_integer([:positive])}"
      bridge_handler_id = {RepoTelemetryBridge, Repo}

      :telemetry.detach(bridge_handler_id)

      :ok =
        :telemetry.attach_many(
          handler_id,
          [
            [:mezzanine, :db, :pool, :queue_time],
            [:mezzanine, :db, :pool, :checkout_timeout]
          ],
          &__MODULE__.handle_pool_telemetry/4,
          self()
        )

      {:ok, bridge_pid} =
        RepoTelemetryBridge.start_link(
          repo: Repo,
          repo_name: "execution",
          query_event: [:mezzanine_execution_engine, :repo, :query]
        )

      try do
        query_results =
          1..@pool_query_concurrency
          |> Task.async_stream(
            fn _index ->
              SQL.query!(Repo, @pool_query_sql, [])
              :ok
            end,
            ordered: false,
            timeout: 5_000,
            max_concurrency: @pool_query_concurrency
          )
          |> Enum.map(fn {:ok, result} -> result end)

        telemetry = collect_pool_telemetry!()

        {:ok,
         %{
           requested_connection_count: @pool_query_concurrency,
           repo_pool_size: Repo.config()[:pool_size],
           all_queries_succeeded?: Enum.all?(query_results, &(&1 == :ok)),
           queue_time_event_count:
             Enum.count(telemetry, &(&1.event == [:mezzanine, :db, :pool, :queue_time])),
           max_queue_time_ms:
             telemetry
             |> Enum.filter(&(&1.event == [:mezzanine, :db, :pool, :queue_time]))
             |> Enum.map(& &1.measurements.queue_time_ms)
             |> case do
               [] -> nil
               queue_times -> Enum.max(queue_times)
             end,
           checkout_timeout_count:
             Enum.count(telemetry, &(&1.event == [:mezzanine, :db, :pool, :checkout_timeout]))
         }}
      after
        :ok = GenServer.stop(bridge_pid)
        :telemetry.detach(handler_id)
      end
    end)
  end

  defp collect_pool_telemetry!(acc \\ []) do
    receive do
      {:stage12_pool_telemetry, event, measurements, metadata} ->
        collect_pool_telemetry!([
          %{event: event, measurements: measurements, metadata: metadata} | acc
        ])
    after
      100 -> Enum.reverse(acc)
    end
  end

  defp normalize_queue_limits(queues) do
    Map.new(queues, fn
      {queue, limit} when is_integer(limit) ->
        {queue, limit}

      {queue, opts} when is_list(opts) ->
        {queue, Keyword.get(opts, :limit, 0)}
    end)
  end
end
