defmodule StackLab.CitadelSpineHarness.AITraceClaimCheckTraceContinuity do
  @moduledoc false

  alias Citadel.TraceBridge
  alias Citadel.TraceEnvelope
  alias Ecto.Migrator
  alias ExecutionPlane.LaneSupport

  alias Jido.Integration.V2.{
    CompatibilityResult,
    ConsumerManifest,
    ControlPlane,
    InferenceExecutionContext,
    InferenceRequest,
    InferenceResult
  }

  alias Jido.Integration.V2.ControlPlane.{ClaimCheck, ClaimCheckTelemetry}

  alias Jido.Integration.V2.StorePostgres

  alias Jido.Integration.V2.StorePostgres.{
    AttemptStore,
    ClaimCheckStore,
    EventStore,
    Repo,
    RunStore,
    TestSupport
  }

  alias StackLab.CitadelSpineHarness.{AppKitOperationalSurface, PostgresContainer}

  @control_plane_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :claim_check_store,
    :target_store,
    :ingress_store
  ]
  @auth_keys [
    :credential_store,
    :lease_store,
    :connection_store,
    :install_store,
    :keyring,
    :refresh_handler,
    :external_secret_resolver
  ]
  @brain_ingress_keys [:submission_ledger]
  @store_postgres_keys [
    :ecto_repos,
    Repo,
    :claim_check_root,
    :claim_check_probe_pid,
    :claim_check_probe_delay_ms,
    :claim_check_probe_failure
  ]
  @claim_check_probe_count 4
  @claim_check_probe_delay_ms 200

  defmodule ClaimCheckStoreProbe do
    @moduledoc false

    @behaviour Jido.Integration.V2.ControlPlane.ClaimCheckStore

    alias Jido.Integration.V2.StorePostgres.ClaimCheckStore
    alias Jido.Integration.V2.StorePostgres.Repo

    def stage_blob(payload_ref, encoded, metadata) do
      maybe_send_probe({:claim_check_stage_in_transaction?, Repo.in_transaction?()})
      maybe_sleep_before_stage()

      case Application.get_env(:jido_integration_v2_store_postgres, :claim_check_probe_failure) do
        nil ->
          ClaimCheckStore.stage_blob(payload_ref, encoded, metadata)

        reason ->
          {:error, reason}
      end
    end

    def fetch_blob(payload_ref), do: ClaimCheckStore.fetch_blob(payload_ref)

    def register_reference(payload_ref, attrs),
      do: ClaimCheckStore.register_reference(payload_ref, attrs)

    def fetch_blob_metadata(payload_ref), do: ClaimCheckStore.fetch_blob_metadata(payload_ref)
    def count_live_references(payload_ref), do: ClaimCheckStore.count_live_references(payload_ref)
    def sweep_staged_payloads(opts \\ []), do: ClaimCheckStore.sweep_staged_payloads(opts)
    def garbage_collect(opts \\ []), do: ClaimCheckStore.garbage_collect(opts)
    def reset!, do: ClaimCheckStore.reset!()

    defp maybe_sleep_before_stage do
      delay_ms =
        Application.get_env(:jido_integration_v2_store_postgres, :claim_check_probe_delay_ms, 0)

      if is_integer(delay_ms) and delay_ms > 0 do
        maybe_send_probe({:claim_check_stage_delay_started, System.monotonic_time(:millisecond)})
        Process.sleep(delay_ms)
      end

      :ok
    end

    defp maybe_send_probe(message) do
      case Application.get_env(:jido_integration_v2_store_postgres, :claim_check_probe_pid) do
        pid when is_pid(pid) ->
          send(pid, message)

        _other ->
          send(self(), message)
      end
    end
  end

  defmodule TestExporter do
    @moduledoc false

    @behaviour AITrace.Exporter

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def export(trace, state) do
      send(state.test_pid, {:exported_trace, trace})
      {:ok, state}
    end

    @impl true
    def shutdown(_state), do: :ok
  end

  @spec run_case(:claim_check_trace_continuity | :claim_check_degradation) :: {:ok, map()}
  def run_case(:claim_check_trace_continuity) do
    {:ok, lower_backed_result} =
      AppKitOperationalSurface.run_case(:lower_backed_command_trace)

    trace_id = lower_backed_result.trace.trace_id

    {:ok, proof} =
      prove_trace_surfaces(
        trace_id,
        lower_backed_result.tenant_id,
        lower_backed_result.dispatch.execution_id,
        label: :claim_check_trace_continuity
      )

    {:ok,
     %{
       case: :claim_check_trace_continuity,
       scenario: 25,
       trace_id: trace_id,
       app_kit_to_lower: %{
         tenant_id: lower_backed_result.tenant_id,
         execution_id: lower_backed_result.dispatch.execution_id,
         submission_key: lower_backed_result.dispatch.submission_key,
         step_sources: lower_backed_result.trace.step_sources,
         join_keys: lower_backed_result.trace.join_keys
       },
       inline_threshold: proof.inline_threshold,
       claim_check: proof.claim_check,
       staged_orphan: proof.staged_orphan,
       execution_plane: proof.execution_plane,
       aitrace: proof.aitrace
     }}
  end

  def run_case(:claim_check_degradation) do
    trace_id = Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

    with_claim_check_store(:claim_check_degradation, trace_id, fn ->
      handler_id = "stack-lab-stage12-claim-check-#{System.unique_integer([:positive])}"

      flush_claim_check_telemetry_messages()
      attach_claim_check_telemetry!(handler_id, self())

      Application.put_env(:jido_integration_v2_store_postgres, :claim_check_probe_pid, self())

      Application.put_env(
        :jido_integration_v2_store_postgres,
        :claim_check_probe_delay_ms,
        @claim_check_probe_delay_ms
      )

      Application.delete_env(:jido_integration_v2_store_postgres, :claim_check_probe_failure)

      try do
        delayed = record_large_inference(trace_id)
        delayed_telemetry = collect_claim_check_telemetry!() |> summarize_claim_check_telemetry!()
        runs_before_failure = length(ControlPlane.runs())

        Application.put_env(
          :jido_integration_v2_store_postgres,
          :claim_check_probe_delay_ms,
          0
        )

        Application.put_env(
          :jido_integration_v2_store_postgres,
          :claim_check_probe_failure,
          :claim_check_unavailable
        )

        failure_spec =
          failed_inference_spec("claim-check-failure", trace_id, large_text(), large_text())

        failure_result = ControlPlane.record_inference_attempt(failure_spec)
        runs_after_failure = length(ControlPlane.runs())
        failure_telemetry = collect_claim_check_telemetry!() |> summarize_claim_check_telemetry!()

        Application.delete_env(:jido_integration_v2_store_postgres, :claim_check_probe_failure)

        orphan_cleanup = stage_duplicate_orphan(trace_id)
        cleanup_telemetry = collect_claim_check_telemetry!() |> summarize_claim_check_telemetry!()

        {:ok,
         %{
           case: :claim_check_degradation,
           trace_id: trace_id,
           delayed_stage: %{
             stage_upload_in_transaction?: delayed.stage_upload_in_transaction?,
             stage_event_count: delayed_telemetry.stage.count,
             max_stage_latency_ms: delayed_telemetry.stage.max_latency_ms
           },
           failure: %{
             result: failure_result,
             run_count_before: runs_before_failure,
             run_count_after: runs_after_failure,
             run_count_unchanged?: runs_before_failure == runs_after_failure,
             stage_failure_count: failure_telemetry.stage_failure.count,
             stage_failure_reason: failure_telemetry.stage_failure.reason
           },
           cleanup: %{
             orphaned_staged_payload_count: cleanup_telemetry.orphaned_staged_payload.count,
             blob_gc_skipped_live_reference_count:
               delayed_telemetry.blob_gc_skipped_live_reference.count +
                 cleanup_telemetry.blob_gc_skipped_live_reference.count,
             orphaned_sweep_deleted_count: orphan_cleanup.sweep_deleted_count,
             orphaned_blob_deleted?: orphan_cleanup.blob_deleted?
           }
         }}
      after
        Application.delete_env(:jido_integration_v2_store_postgres, :claim_check_probe_pid)
        Application.delete_env(:jido_integration_v2_store_postgres, :claim_check_probe_delay_ms)
        Application.delete_env(:jido_integration_v2_store_postgres, :claim_check_probe_failure)
        flush_claim_check_probe_messages()
        flush_claim_check_telemetry_messages()
        :telemetry.detach(handler_id)
      end
    end)
  end

  @spec prove_trace_surfaces(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()}
  def prove_trace_surfaces(trace_id, tenant_id, execution_id, opts \\ [])
      when is_binary(trace_id) and is_binary(tenant_id) and is_binary(execution_id) do
    label = Keyword.get(opts, :label, :trace_surfaces)

    with_aitrace_exporter(fn ->
      with_claim_check_store(label, trace_id, fn ->
        inline_result = record_inline_inference(trace_id)
        large_result = record_large_inference(trace_id)
        orphan_result = stage_duplicate_orphan(trace_id)
        execution_plane_result = execution_plane_lineage(trace_id, execution_id)

        aitrace_result =
          publish_aitrace_trace(trace_id, tenant_id, execution_id, execution_plane_result)

        {:ok,
         %{
           inline_threshold: inline_result,
           claim_check: large_result,
           staged_orphan: orphan_result,
           execution_plane: execution_plane_result,
           aitrace: aitrace_result
         }}
      end)
    end)
  end

  defp record_inline_inference(trace_id) do
    spec = failed_inference_spec("inline", trace_id, "short prompt", "provider timeout")

    recorded = assert_ok(ControlPlane.record_inference_attempt(spec))
    stored_run = assert_ok(RunStore.fetch_run(recorded.run.run_id))
    stored_attempt = assert_ok(AttemptStore.fetch_attempt(recorded.attempt.attempt_id))
    terminal_event = ControlPlane.events(recorded.run.run_id) |> List.last()

    %{
      run_id: stored_run.run_id,
      attempt_id: stored_attempt.attempt_id,
      run_input_claim_checked?: ClaimCheck.claim_checked?(stored_run.input),
      run_result_claim_checked?: ClaimCheck.claim_checked?(stored_run.result),
      attempt_output_claim_checked?: ClaimCheck.claim_checked?(stored_attempt.output),
      terminal_event_claim_checked?: ClaimCheck.claim_checked?(terminal_event.payload),
      input_payload_ref: normalize_payload_ref(stored_run.input_payload_ref),
      result_payload_ref: normalize_payload_ref(stored_run.result_payload_ref),
      output_payload_ref: normalize_payload_ref(stored_attempt.output_payload_ref),
      event_payload_ref: normalize_payload_ref(terminal_event.payload_ref),
      inline_prompt: get_in(stored_run.input, ["request", "messages", Access.at(0), "content"])
    }
  end

  defp record_large_inference(trace_id) do
    large_text = large_text()
    spec = failed_inference_spec("claim-check", trace_id, large_text, large_text)

    recorded = assert_ok(ControlPlane.record_inference_attempt(spec))

    transaction_flags =
      Enum.map(1..@claim_check_probe_count, fn _index ->
        receive do
          {:claim_check_stage_in_transaction?, value} -> value
        after
          5_000 -> raise "did not observe claim-check stage probe"
        end
      end)

    stored_run = assert_ok(RunStore.fetch_run(recorded.run.run_id))
    stored_attempt = assert_ok(AttemptStore.fetch_attempt(recorded.attempt.attempt_id))
    terminal_event = EventStore.list_events(recorded.run.run_id) |> List.last()

    input_metadata = assert_ok(ClaimCheckStore.fetch_blob_metadata(stored_run.input_payload_ref))

    result_metadata =
      assert_ok(ClaimCheckStore.fetch_blob_metadata(stored_run.result_payload_ref))

    output_metadata =
      assert_ok(ClaimCheckStore.fetch_blob_metadata(stored_attempt.output_payload_ref))

    event_metadata = assert_ok(ClaimCheckStore.fetch_blob_metadata(terminal_event.payload_ref))

    resolved_input =
      assert_ok(ClaimCheck.resolve_json(stored_run.input, stored_run.input_payload_ref))

    resolved_terminal_payload =
      ClaimCheck.resolve_json(terminal_event.payload, terminal_event.payload_ref)
      |> assert_ok()

    gc_result = assert_ok(ClaimCheckStore.garbage_collect(older_than_s: 0))

    %{
      run_id: stored_run.run_id,
      attempt_id: stored_attempt.attempt_id,
      stage_upload_in_transaction?: transaction_flags,
      run_input_claim_checked?: ClaimCheck.claim_checked?(stored_run.input),
      run_result_claim_checked?: ClaimCheck.claim_checked?(stored_run.result),
      attempt_output_claim_checked?: ClaimCheck.claim_checked?(stored_attempt.output),
      terminal_event_claim_checked?: ClaimCheck.claim_checked?(terminal_event.payload),
      input_payload_ref: normalize_payload_ref(stored_run.input_payload_ref),
      result_payload_ref: normalize_payload_ref(stored_run.result_payload_ref),
      output_payload_ref: normalize_payload_ref(stored_attempt.output_payload_ref),
      event_payload_ref: normalize_payload_ref(terminal_event.payload_ref),
      live_reference_counts: %{
        input: ClaimCheckStore.count_live_references(stored_run.input_payload_ref),
        result: ClaimCheckStore.count_live_references(stored_run.result_payload_ref),
        output: ClaimCheckStore.count_live_references(stored_attempt.output_payload_ref),
        event: ClaimCheckStore.count_live_references(terminal_event.payload_ref)
      },
      metadata_statuses: %{
        input: %{status: input_metadata.status, trace_id: input_metadata.trace_id},
        result: %{status: result_metadata.status, trace_id: result_metadata.trace_id},
        output: %{status: output_metadata.status, trace_id: output_metadata.trace_id},
        event: %{status: event_metadata.status, trace_id: event_metadata.trace_id}
      },
      hot_row_shapes: %{
        input_keys: Map.keys(stored_run.input) |> Enum.sort(),
        result_keys: Map.keys(stored_run.result) |> Enum.sort(),
        output_keys: Map.keys(stored_attempt.output) |> Enum.sort(),
        event_keys: Map.keys(terminal_event.payload) |> Enum.sort()
      },
      resolved_prompt_length:
        resolved_input
        |> get_in(["request", "messages", Access.at(0), "content"])
        |> String.length(),
      resolved_error_length:
        resolved_terminal_payload |> get_in(["error", "message"]) |> String.length(),
      gc: gc_result
    }
  end

  defp stage_duplicate_orphan(trace_id) do
    payload = %{
      "contract_version" => "scenario_25",
      "messages" => [%{"role" => "user", "content" => large_text()}]
    }

    first =
      ClaimCheck.prepare_json(payload,
        payload_kind: :scenario_25_payload,
        trace_id: trace_id,
        redaction_class: "scenario_25_payload"
      )
      |> assert_ok()

    second =
      ClaimCheck.prepare_json(payload,
        payload_kind: :scenario_25_payload,
        trace_id: trace_id,
        redaction_class: "scenario_25_payload"
      )
      |> assert_ok()

    staged_metadata = assert_ok(ClaimCheckStore.fetch_blob_metadata(first.payload_ref))
    sweep_result = assert_ok(ClaimCheckStore.sweep_staged_payloads(older_than_s: 0))
    swept_metadata = assert_ok(ClaimCheckStore.fetch_blob_metadata(first.payload_ref))

    %{
      payload_ref: normalize_payload_ref(first.payload_ref),
      duplicate_payload_ref?:
        normalize_payload_ref(first.payload_ref) == normalize_payload_ref(second.payload_ref),
      staged_status: staged_metadata.status,
      payload_kind: staged_metadata.payload_kind,
      live_reference_count: ClaimCheckStore.count_live_references(first.payload_ref),
      sweep_deleted_count: sweep_result.deleted_count,
      swept_status: swept_metadata.status,
      blob_deleted?: ClaimCheckStore.fetch_blob(first.payload_ref) == :error
    }
  end

  defp execution_plane_lineage(trace_id, request_id) do
    lineage =
      LaneSupport.build_lineage("scenario25",
        tenant_id: "tenant-scenario-25",
        trace_id: trace_id,
        request_id: request_id
      )

    envelope =
      LaneSupport.build_envelope(
        "scenario25",
        "process",
        "scenario25.execute",
        lineage,
        requested_capabilities: ["scenario25.execute"]
      )

    route =
      LaneSupport.build_route(
        "scenario25",
        "process",
        "process",
        "local",
        %{"execution_surface" => %{"surface_kind" => "local_subprocess"}},
        30_000,
        lineage
      )

    %{
      lineage_trace_id: lineage.trace_id,
      envelope_trace_id: envelope.trace_id,
      route_trace_id: route.lineage.trace_id,
      request_id: lineage.request_id,
      idempotency_key: lineage.idempotency_key,
      boundary_session_id: lineage.boundary_session_id
    }
  end

  defp publish_aitrace_trace(trace_id, tenant_id, request_id, execution_lineage) do
    envelope =
      TraceEnvelope.new!(%{
        trace_envelope_id: "scenario25-#{System.unique_integer([:positive])}",
        record_kind: :event,
        family: "scenario25",
        name: "citadel.scenario25.claim_check_continuity",
        phase: "post_commit",
        trace_id: trace_id,
        tenant_id: tenant_id,
        session_id: "scenario25/session",
        request_id: request_id,
        decision_id: nil,
        snapshot_seq: 1,
        signal_id: nil,
        outbox_entry_id: nil,
        boundary_ref: "scenario25-boundary",
        span_id: nil,
        parent_span_id: nil,
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
        started_at: nil,
        finished_at: nil,
        status: "ok",
        attributes: %{"scenario" => "25"},
        extensions: %{
          "canonical_idempotency_key" => execution_lineage.idempotency_key,
          "platform_envelope_id" => request_id,
          "route_boundary_session_id" => execution_lineage.boundary_session_id
        }
      })

    :ok = TraceBridge.publish_trace(envelope)

    exported_trace =
      receive do
        {:exported_trace, trace} -> trace
      after
        5_000 -> raise "did not observe AITrace export"
      end

    span = hd(exported_trace.spans)

    %{
      trace_id: exported_trace.trace_id,
      trace_id_source: exported_trace.trace_id_source,
      span_count: length(exported_trace.spans),
      span_id: span.span_id,
      span_id_source: span.span_id_source,
      start_time: span.start_time,
      start_wall_time: span.start_wall_time,
      clock_domain: span.clock_domain,
      lineage: exported_trace.metadata.lineage,
      aitrace_context: exported_trace.metadata.aitrace_context,
      platform_envelope_field_map: exported_trace.metadata.platform_envelope_field_map
    }
  end

  defp with_aitrace_exporter(fun) when is_function(fun, 0) do
    previous_exporters = Application.get_env(:aitrace, :exporters)
    Application.put_env(:aitrace, :exporters, [{TestExporter, test_pid: self()}])

    try do
      fun.()
    after
      Application.put_env(:aitrace, :exporters, previous_exporters)
    end
  end

  defp with_claim_check_store(label, trace_id, fun) when is_function(fun, 0) do
    container = PostgresContainer.start!("scenario25_#{label}")
    previous_env = snapshot_env()
    claim_check_root = claim_check_root(label, trace_id)

    try do
      ensure_jido_apps_started!()
      configure_claim_check_env!(container.port, claim_check_root)
      start_store_postgres!()
      migrate_store_postgres!()
      TestSupport.reset_database!()
      ControlPlane.reset!()
      fun.()
    after
      stop_store_postgres()
      restore_env(previous_env)
      File.rm_rf!(claim_check_root)
      PostgresContainer.stop!(container)
    end
  end

  defp ensure_jido_apps_started! do
    {:ok, _apps} = Application.ensure_all_started(:jido_integration_v2)
    :ok
  end

  defp configure_claim_check_env!(port, claim_check_root) do
    TestSupport.configure_defaults!()

    Application.put_env(
      :jido_integration_v2_control_plane,
      :claim_check_store,
      ClaimCheckStoreProbe
    )

    Application.put_env(
      :jido_integration_v2_store_postgres,
      Repo,
      PostgresContainer.repo_config(port)
    )

    Application.put_env(:jido_integration_v2_store_postgres, :claim_check_root, claim_check_root)
  end

  defp start_store_postgres! do
    stop_store_postgres()

    case Jido.Integration.V2.StorePostgres.Application.start(:normal, []) do
      {:ok, pid} ->
        Process.unlink(pid)
        :ok

      {:error, {:already_started, pid}} ->
        Process.unlink(pid)
        :ok

      {:error, reason} ->
        raise "store_postgres application did not start: #{inspect(reason)}"
    end
  end

  defp stop_store_postgres do
    case Process.whereis(Jido.Integration.V2.StorePostgres.Supervisor) do
      nil ->
        :ok

      pid ->
        try do
          GenServer.stop(pid)
        catch
          :exit, _reason -> :ok
        end
    end
  end

  defp migrate_store_postgres! do
    {:ok, _, _} =
      Migrator.with_repo(Repo, fn repo ->
        Migrator.run(repo, StorePostgres.migrations_path(), :up, all: true, log: false)
      end)

    :ok
  end

  defp claim_check_root(label, trace_id) do
    Path.join(
      System.tmp_dir!(),
      "stack_lab_scenario25_#{label}_#{String.slice(trace_id, 0, 8)}"
    )
  end

  defp snapshot_env do
    %{
      control_plane: snapshot_keys(:jido_integration_v2_control_plane, @control_plane_keys),
      auth: snapshot_keys(:jido_integration_v2_auth, @auth_keys),
      brain_ingress: snapshot_keys(:jido_integration_v2_brain_ingress, @brain_ingress_keys),
      store_postgres: snapshot_keys(:jido_integration_v2_store_postgres, @store_postgres_keys)
    }
  end

  defp restore_env(previous_env) do
    restore_keys(:jido_integration_v2_control_plane, previous_env.control_plane)
    restore_keys(:jido_integration_v2_auth, previous_env.auth)
    restore_keys(:jido_integration_v2_brain_ingress, previous_env.brain_ingress)
    restore_keys(:jido_integration_v2_store_postgres, previous_env.store_postgres)
    :ok
  end

  defp snapshot_keys(app, keys) do
    Map.new(keys, fn key -> {key, Application.get_env(app, key, :__missing__)} end)
  end

  defp restore_keys(app, snapshot) do
    Enum.each(snapshot, fn
      {key, :__missing__} -> Application.delete_env(app, key)
      {key, value} -> Application.put_env(app, key, value)
    end)
  end

  def handle_claim_check_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:claim_check_telemetry, event, measurements, metadata})
  end

  defp attach_claim_check_telemetry!(handler_id, test_pid) do
    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          ClaimCheckTelemetry.event(:stage),
          ClaimCheckTelemetry.event(:stage_failure),
          ClaimCheckTelemetry.event(:orphaned_staged_payload),
          ClaimCheckTelemetry.event(:blob_gc_skipped_live_reference)
        ],
        &__MODULE__.handle_claim_check_telemetry/4,
        test_pid
      )

    :ok
  end

  defp collect_claim_check_telemetry!(acc \\ []) do
    receive do
      {:claim_check_telemetry, event, measurements, metadata} ->
        collect_claim_check_telemetry!([
          %{event: event, measurements: measurements, metadata: metadata} | acc
        ])
    after
      100 -> Enum.reverse(acc)
    end
  end

  defp summarize_claim_check_telemetry!(events) do
    %{
      stage:
        summarize_claim_check_events(
          events,
          ClaimCheckTelemetry.event(:stage)
        ),
      stage_failure:
        summarize_claim_check_events(
          events,
          ClaimCheckTelemetry.event(:stage_failure)
        ),
      orphaned_staged_payload:
        summarize_claim_check_events(
          events,
          ClaimCheckTelemetry.event(:orphaned_staged_payload)
        ),
      blob_gc_skipped_live_reference:
        summarize_claim_check_events(
          events,
          ClaimCheckTelemetry.event(:blob_gc_skipped_live_reference)
        )
    }
  end

  defp summarize_claim_check_events(events, event_name) do
    matched = Enum.filter(events, &(&1.event == event_name))

    %{
      count: length(matched),
      max_latency_ms:
        matched
        |> Enum.map(&Map.get(&1.measurements, :latency_ms))
        |> Enum.reject(&is_nil/1)
        |> case do
          [] -> nil
          latencies -> Enum.max(latencies)
        end,
      reason:
        matched
        |> Enum.map(&Map.get(&1.metadata, :reason))
        |> Enum.reject(&is_nil/1)
        |> List.first()
    }
  end

  defp flush_claim_check_probe_messages do
    receive do
      {:claim_check_stage_in_transaction?, _value} ->
        flush_claim_check_probe_messages()

      {:claim_check_stage_delay_started, _started_at_ms} ->
        flush_claim_check_probe_messages()
    after
      0 -> :ok
    end
  end

  defp flush_claim_check_telemetry_messages do
    receive do
      {:claim_check_telemetry, _event, _measurements, _metadata} ->
        flush_claim_check_telemetry_messages()
    after
      0 -> :ok
    end
  end

  defp failed_inference_spec(suffix, trace_id, prompt_text, error_text) do
    token = System.unique_integer([:positive])
    request_id = "req-#{suffix}-#{token}"
    run_id = "run-#{suffix}-#{token}"
    attempt_id = "#{run_id}:1"

    %{
      request:
        InferenceRequest.new!(%{
          request_id: request_id,
          operation: :generate_text,
          messages: [%{role: "user", content: prompt_text}],
          prompt: nil,
          model_preference: %{provider: "openai", id: "gpt-4o-mini"},
          target_preference: %{target_class: "cloud_provider"},
          stream?: false,
          tool_policy: %{},
          output_constraints: %{format: "text"},
          metadata: %{tenant_id: "tenant-scenario-25"}
        }),
      context:
        InferenceExecutionContext.new!(%{
          run_id: run_id,
          attempt_id: attempt_id,
          authority_source: :jido_integration,
          decision_ref: "decision-#{suffix}",
          authority_ref: nil,
          boundary_ref: nil,
          credential_scope: %{scopes: ["model:invoke"]},
          network_policy: %{egress: "restricted"},
          observability: %{trace_id: trace_id},
          streaming_policy: %{checkpoint_policy: :disabled},
          replay: %{replayable?: false, recovery_class: nil},
          metadata: %{phase: "phase_2"}
        }),
      consumer_manifest:
        ConsumerManifest.new!(%{
          consumer: "jido_integration_req_llm",
          accepted_runtime_kinds: [:client],
          accepted_management_modes: [:provider_managed],
          accepted_protocols: [:openai_chat_completions],
          required_capabilities: %{},
          optional_capabilities: %{tool_calling?: false},
          constraints: %{checkpoint_policy: :disabled},
          metadata: %{phase: "phase_2"}
        }),
      compatibility_result:
        CompatibilityResult.new!(%{
          compatible?: true,
          reason: :protocol_match,
          resolved_runtime_kind: :client,
          resolved_management_mode: :provider_managed,
          resolved_protocol: nil,
          warnings: [],
          missing_requirements: [],
          metadata: %{route: "cloud"}
        }),
      result:
        InferenceResult.new!(%{
          run_id: run_id,
          attempt_id: attempt_id,
          status: :error,
          streaming?: false,
          endpoint_id: nil,
          stream_id: nil,
          finish_reason: :error,
          usage: nil,
          error: %{message: error_text, reason: :timeout},
          metadata: %{provider: "openai"}
        })
    }
  end

  defp large_text do
    String.duplicate("scenario-25-claim-check-payload-", 3_000)
  end

  defp normalize_payload_ref(nil), do: nil

  defp normalize_payload_ref(payload_ref) when is_map(payload_ref) do
    %{
      store: Map.get(payload_ref, :store) || Map.get(payload_ref, "store"),
      key: Map.get(payload_ref, :key) || Map.get(payload_ref, "key"),
      checksum: Map.get(payload_ref, :checksum) || Map.get(payload_ref, "checksum"),
      size_bytes: Map.get(payload_ref, :size_bytes) || Map.get(payload_ref, "size_bytes"),
      ttl_s: Map.get(payload_ref, :ttl_s) || Map.get(payload_ref, "ttl_s"),
      access_control:
        Map.get(payload_ref, :access_control) || Map.get(payload_ref, "access_control")
    }
  end

  defp assert_ok({:ok, value}), do: value
  defp assert_ok(other), do: raise("expected {:ok, value}, got: #{inspect(other)}")
end
