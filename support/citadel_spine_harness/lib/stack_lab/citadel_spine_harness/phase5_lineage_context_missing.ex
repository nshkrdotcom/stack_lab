defmodule StackLab.CitadelSpineHarness.Phase5LineageContextMissing do
  @moduledoc false

  alias Citadel.Kernel.SignalIngress
  alias Citadel.RuntimeObservation
  alias Citadel.TraceBridge
  alias Citadel.TraceEnvelope
  alias ExecutionPlane.LaneSupport
  alias Jido.Integration.V2.SubjectRef
  alias Mezzanine.Audit.{ExecutionLineage, ExecutionLineageStore}
  alias Mezzanine.Idempotency
  alias OuterBrain.Contracts.SemanticFailure
  alias StackLab.CitadelSpineHarness.BoundedNames
  alias StackLab.CitadelSpineHarness.Timing

  @scenario 208
  @tenant_id "tenant-scenario-208"
  @installation_id "installation-scenario-208"
  @subject_id "subject-scenario-208"
  @authority_scope "authority-scenario-208"
  @authority_decision_ref "authority-decision/scenario-208"
  @causation_id "operator-request/scenario-208"
  @execution_id "execution-scenario-208"
  @source_position "cursor/208"
  @release_manifest_ref "phase5-v7-m5-lineage-context-missing"

  defmodule TestSignalSource do
    @moduledoc false
    @behaviour Citadel.Ports.SignalSource

    @impl true
    def normalize_signal(%RuntimeObservation{} = observation), do: {:ok, observation}
  end

  defmodule TestExporter do
    @moduledoc false

    @behaviour AITrace.Exporter

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def export(trace, state) do
      send(state.test_pid, {:scenario_208_exported_trace, trace})
      {:ok, state}
    end

    @impl true
    def shutdown(_state), do: :ok
  end

  @spec run_case(:lineage_context_missing) :: {:ok, map()}
  def run_case(:lineage_context_missing) do
    lineage = lineage_profile()
    canonical_attrs = canonical_idempotency_attrs(lineage)
    canonical_key = Idempotency.canonical_key!(canonical_attrs)
    {:ok, canonical_payload} = Idempotency.canonical_payload(canonical_attrs)
    correlation = Idempotency.correlation_evidence!(correlation_attrs(lineage, canonical_key))

    {:ok, signal_ingress} = prove_signal_ingress(lineage, canonical_key)
    execution_plane = prove_execution_plane(lineage, canonical_key)
    execution_lineage = prove_execution_lineage(lineage, correlation)
    semantic_failure = prove_semantic_failure(lineage, canonical_key)
    aitrace = prove_aitrace_envelope(lineage, canonical_key, execution_plane)

    {:ok,
     %{
       case: :lineage_context_missing,
       scenario: @scenario,
       runtime_envelope: %{
         runtime_class: :source_integration,
         expected_local_max_ms: 30_000,
         ci_timeout_ms: 60_000,
         measurement_scope:
           "lineage, idempotency correlation, and causal reconstruction ledger fixture after app boot"
       },
       tenant_id: @tenant_id,
       trace_id: lineage.trace_id,
       canonical_idempotency_key: canonical_key,
       positive: %{
         minimum_lineage: minimum_lineage(lineage, canonical_key),
         canonical_payload: canonical_payload,
         idempotency_correlation: correlation,
         signal_ingress: signal_ingress.accepted,
         execution_plane: execution_plane,
         execution_lineage_store: execution_lineage,
         semantic_failure: semantic_failure,
         aitrace: aitrace,
         causal_reconstruction_ledger:
           causal_reconstruction_ledger(
             lineage,
             canonical_key,
             correlation,
             signal_ingress.accepted,
             execution_plane,
             execution_lineage,
             semantic_failure,
             aitrace
           )
       },
       negative_failures: signal_ingress.negative_failures,
       stop_condition_evidence: %{
         aitrace_mandatory_runtime_backend?: false,
         release_manifest_required_for_runtime_acceptance?: false,
         missing_lineage_rejection_only?: false,
         silently_minted_causation_or_idempotency?: false
       }
     }}
  end

  defp lineage_profile do
    trace_id =
      "stack_lab_scenario_208"
      |> sha256()
      |> binary_part(0, 32)

    %{
      trace_id: trace_id,
      tenant_id: @tenant_id,
      installation_id: @installation_id,
      subject_id: @subject_id,
      authority_scope: @authority_scope,
      authority_decision_ref: @authority_decision_ref,
      causation_id: @causation_id,
      execution_id: @execution_id,
      source_position: @source_position,
      session_id: "session-scenario-208",
      semantic_session_id: "semantic-session-scenario-208",
      boundary_session_id: "boundary-session-scenario-208",
      route_id: "route-scenario-208",
      intent_id: "intent-scenario-208",
      activity_call_ref: "activity-call/scenario-208",
      lower_submission_ref: "lower-submission/scenario-208",
      provider_retry_ref: "provider-retry/scenario-208",
      workflow_id: "workflow-scenario-208",
      workflow_run_id: "workflow-run-scenario-208",
      client_retry_key: "client-retry/scenario-208",
      payload_hash: sha256_ref("scenario-208-preserved-command")
    }
  end

  defp canonical_idempotency_attrs(lineage) do
    %{
      tenant_id: lineage.tenant_id,
      installation_id: lineage.installation_id,
      operation_family: "lineage_context_missing",
      operation_ref: "stack_lab/scenario_208/envelope",
      causation_id: lineage.causation_id,
      authority_decision_ref: lineage.authority_decision_ref,
      subject_ref: lineage.subject_id,
      payload_hash: lineage.payload_hash,
      source_event_position: lineage.source_position
    }
  end

  defp correlation_attrs(lineage, canonical_key) do
    %{
      canonical_idempotency_key: canonical_key,
      tenant_id: lineage.tenant_id,
      trace_id: lineage.trace_id,
      causation_id: lineage.causation_id,
      client_retry_key: lineage.client_retry_key,
      platform_envelope_idempotency_key: canonical_key,
      temporal_workflow_id: lineage.workflow_id,
      temporal_workflow_run_id: lineage.workflow_run_id,
      temporal_start_idempotency_key: canonical_key,
      temporal_activity_call_ref: lineage.activity_call_ref,
      lower_submission_stable_ref: lineage.lower_submission_ref,
      lower_provider_retry_stable_ref: lineage.provider_retry_ref,
      execution_plane_intent_id: lineage.intent_id,
      execution_plane_route_id: lineage.route_id,
      execution_plane_envelope_idempotency_key: canonical_key,
      execution_plane_route_idempotency_key: canonical_key,
      release_manifest_ref: @release_manifest_ref
    }
  end

  defp prove_signal_ingress(lineage, canonical_key) do
    name = unique_name(:phase5_lineage_context_missing)

    {:ok, ingress_pid} =
      SignalIngress.start_link(
        name: name,
        signal_source: TestSignalSource,
        admission_policy: admission_policy()
      )

    try do
      :ok =
        SignalIngress.register_subscription(name, lineage.session_id,
          tenant_id: lineage.tenant_id,
          authority_scope: lineage.authority_scope
        )

      {:ok, acceptance} =
        SignalIngress.deliver_observation(
          name,
          observation(lineage, canonical_key, "signal-scenario-208-accepted")
        )

      :ok = wait_until(fn -> queue_empty?(SignalIngress.snapshot(name)) end)

      subscription = SignalIngress.subscription_state(name, lineage.session_id)

      negative_failures = %{
        missing_trace:
          rejection(
            name,
            observation(lineage, canonical_key, "signal-scenario-208-missing-trace",
              trace_id: nil
            )
          ),
        missing_canonical_root:
          rejection(
            name,
            observation(lineage, canonical_key, "signal-scenario-208-missing-root",
              canonical_idempotency_key: nil
            )
          ),
        missing_source_anchor:
          rejection(
            name,
            observation(lineage, canonical_key, "signal-scenario-208-missing-source",
              source_position: nil,
              signal_cursor: nil
            )
          ),
        regressed_source_anchor:
          rejection(
            name,
            observation(lineage, canonical_key, "signal-scenario-208-regressed-source",
              source_position: "cursor/207",
              signal_cursor: "cursor/207"
            )
          )
      }

      {:ok,
       %{
         accepted: %{
           accepted_ref: acceptance.accepted_ref,
           partition_ref: acceptance.partition_ref,
           tenant_scope_key: acceptance.tenant_scope_key,
           delivery_order_scope: acceptance.delivery_order_scope,
           dedupe_key: acceptance.dedupe_key,
           lineage: acceptance.lineage,
           source_anchor_recorded: get_in(subscription, [:extensions, "lineage_source_anchor"]),
           async_handoff?: acceptance.async_handoff?
         },
         negative_failures: negative_failures
       }}
    after
      stop_process(ingress_pid)
    end
  end

  defp prove_execution_plane(lineage, canonical_key) do
    plane_lineage =
      LaneSupport.build_lineage("scenario208",
        tenant_id: lineage.tenant_id,
        trace_id: lineage.trace_id,
        request_id: lineage.causation_id,
        decision_id: lineage.authority_decision_ref,
        boundary_session_id: lineage.boundary_session_id,
        attempt_ref: "attempt://scenario208/1",
        route_id: lineage.route_id,
        idempotency_key: canonical_key
      )

    envelope =
      LaneSupport.build_envelope(
        "scenario208",
        "process",
        "scenario208.preserved_behavior",
        plane_lineage,
        intent_id: lineage.intent_id,
        extensions: %{
          "source_position" => lineage.source_position,
          "release_manifest_ref" => @release_manifest_ref
        }
      )

    route =
      LaneSupport.build_route(
        "scenario208",
        "process",
        "local",
        "local",
        %{"execution_surface" => %{"surface_kind" => "local_subprocess"}},
        30_000,
        plane_lineage
      )

    %{
      lineage_trace_id: plane_lineage.trace_id,
      lineage_request_id: plane_lineage.request_id,
      lineage_route_id: plane_lineage.route_id,
      lineage_boundary_session_id: plane_lineage.boundary_session_id,
      lineage_idempotency_key: plane_lineage.idempotency_key,
      envelope_intent_id: envelope.intent_id,
      envelope_trace_id: envelope.trace_id,
      envelope_idempotency_key: envelope.idempotency_key,
      route_id: route.route_id,
      route_trace_id: route.lineage.trace_id,
      route_idempotency_key: route.lineage.idempotency_key,
      source_position: envelope.extensions["source_position"]
    }
  end

  defp prove_execution_lineage(lineage, correlation) do
    execution_lineage =
      ExecutionLineage.new!(%{
        trace_id: lineage.trace_id,
        causation_id: lineage.causation_id,
        tenant_id: lineage.tenant_id,
        installation_id: lineage.installation_id,
        subject_id: lineage.subject_id,
        execution_id: lineage.execution_id,
        citadel_request_id: lineage.causation_id,
        citadel_submission_id: "citadel-submission/scenario-208",
        ji_submission_key: correlation["jido_lower_submission_dedupe_key"],
        lower_run_id: "lower-run-scenario-208",
        lower_attempt_id: "lower-attempt-scenario-208",
        artifact_refs: ["artifact://scenario208/causal-reconstruction-ledger"]
      })

    %{
      owner_module: ExecutionLineageStore,
      owner_posture: :audit_owned_durable_lineage_ledger_lookup_index,
      public_lookup: ExecutionLineage.public_lookup(execution_lineage),
      lower_identifiers: ExecutionLineage.lower_identifiers(execution_lineage),
      lower_lookup_after_authorization?: true,
      tenant_authorization_override?: false,
      workflow_lifecycle_truth?: false,
      lower_runtime_truth?: false
    }
  end

  defp prove_semantic_failure(lineage, canonical_key) do
    {:ok, failure} =
      SemanticFailure.new(%{
        kind: :semantic_insufficient_context,
        retry_class: :terminal,
        tenant_id: lineage.tenant_id,
        semantic_session_id: lineage.semantic_session_id,
        causal_unit_id: lineage.causation_id,
        request_trace_id: lineage.trace_id,
        substrate_trace_id: lineage.trace_id,
        context_hash: sha256_ref("scenario-208-context"),
        canonical_idempotency_key: canonical_key,
        provenance: [
          %{
            "source_ref" => "stack_lab/scenario_208",
            "source_position" => lineage.source_position
          }
        ],
        provider_ref: %{"provider" => "not-called", "ref" => "scenario-208-proof-only"},
        operator_message: "scenario 208 semantic failure identity proof"
      })

    %{
      journal_entry_id: SemanticFailure.journal_entry_id(failure),
      journal_identity_payload: SemanticFailure.journal_identity_payload(failure),
      semantic_failure_payload_hash: SemanticFailure.semantic_failure_payload_hash(failure),
      legacy_alias_only?: true,
      delimiter_joined_write_key?: false
    }
  end

  defp prove_aitrace_envelope(lineage, canonical_key, execution_plane) do
    with_aitrace_exporter(fn aitrace_exporters ->
      envelope =
        TraceEnvelope.new!(%{
          trace_envelope_id: "scenario208-#{System.unique_integer([:positive])}",
          record_kind: :event,
          family: "scenario208",
          name: "citadel.scenario208.lineage_context_missing",
          phase: "post_commit",
          trace_id: lineage.trace_id,
          tenant_id: lineage.tenant_id,
          session_id: lineage.session_id,
          request_id: lineage.causation_id,
          decision_id: lineage.authority_decision_ref,
          snapshot_seq: 208,
          signal_id: "signal-scenario-208-accepted",
          outbox_entry_id: nil,
          boundary_ref: lineage.boundary_session_id,
          span_id: nil,
          parent_span_id: nil,
          occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
          started_at: nil,
          finished_at: nil,
          status: "ok",
          attributes: %{"scenario" => "208", "proof" => "lineage_context_missing"},
          extensions: %{
            "canonical_idempotency_key" => canonical_key,
            "source_position" => lineage.source_position,
            "platform_envelope_id" => execution_plane.envelope_intent_id,
            "execution_plane_route_id" => execution_plane.route_id,
            "release_manifest_ref" => @release_manifest_ref
          }
        })

      :ok = TraceBridge.publish_trace(envelope, legacy_exporters: aitrace_exporters)

      exported_trace =
        receive do
          {:scenario_208_exported_trace, trace} -> trace
        after
          5_000 -> raise "did not observe Scenario 208 AITrace export"
        end

      span = hd(exported_trace.spans)

      %{
        proof_export_ref: "aitrace://stack_lab/scenario208/#{lineage.trace_id}",
        trace_id: exported_trace.trace_id,
        trace_id_source: exported_trace.trace_id_source,
        span_id: span.span_id,
        span_id_source: span.span_id_source,
        start_time: span.start_time,
        start_wall_time: span.start_wall_time,
        clock_domain: span.clock_domain,
        lineage: exported_trace.metadata.lineage,
        aitrace_context: exported_trace.metadata.aitrace_context,
        platform_envelope_field_map: exported_trace.metadata.platform_envelope_field_map,
        mandatory_runtime_backend?: false
      }
    end)
  end

  defp minimum_lineage(lineage, canonical_key) do
    %{
      trace_id: lineage.trace_id,
      causation_id: lineage.causation_id,
      canonical_idempotency_key: canonical_key,
      tenant_id: lineage.tenant_id,
      authority_decision_ref: lineage.authority_decision_ref,
      source_position: lineage.source_position,
      workflow_id: :optional_extended_evidence,
      lower_id: :optional_extended_evidence,
      aitrace_span_id: :optional_extended_evidence,
      installation_id: :optional_extended_evidence,
      release_manifest_ref: :proof_export_metadata
    }
  end

  defp causal_reconstruction_ledger(
         lineage,
         canonical_key,
         correlation,
         signal_ingress,
         execution_plane,
         execution_lineage,
         semantic_failure,
         aitrace
       ) do
    %{
      product_or_operator_request_ref: lineage.causation_id,
      tenant_id: lineage.tenant_id,
      authority_decision_ref: lineage.authority_decision_ref,
      trace_id: lineage.trace_id,
      causation_id: lineage.causation_id,
      canonical_idempotency_key: canonical_key,
      source_ordering_anchor: lineage.source_position,
      idempotency_alias_map_ref: correlation["contract_name"],
      workflow_ref: correlation["temporal_workflow_id"],
      lower_submission_ref: correlation["jido_lower_submission_dedupe_key"],
      execution_plane_route_ref: execution_plane.route_id,
      signal_ingress_accepted_ref: signal_ingress.accepted_ref,
      audit_lineage_lookup: execution_lineage.public_lookup,
      semantic_failure_journal_entry_id: semantic_failure.journal_entry_id,
      aitrace_export_ref: aitrace.proof_export_ref,
      release_manifest_ref: @release_manifest_ref,
      preserved_behavior: :lineage_context_reconstructable
    }
  end

  defp observation(lineage, canonical_key, signal_id, opts \\ []) do
    trace_id = Keyword.get(opts, :trace_id, lineage.trace_id)
    source_position = Keyword.get(opts, :source_position, lineage.source_position)

    signal_cursor =
      Keyword.get(opts, :signal_cursor, source_position || "cursor/#{signal_id}")

    canonical_idempotency_key =
      Keyword.get(opts, :canonical_idempotency_key, canonical_key)

    RuntimeObservation.new!(%{
      observation_id: "obs/#{signal_id}",
      request_id: lineage.causation_id,
      session_id: lineage.session_id,
      signal_id: signal_id,
      signal_cursor: signal_cursor,
      runtime_ref_id: "runtime/#{lineage.session_id}",
      event_kind: "scenario_208_signal",
      event_at: DateTime.utc_now(),
      status: "ok",
      output: %{},
      artifacts: [],
      payload: %{"status" => "ok"},
      subject_ref: SubjectRef.new!(%{kind: :run, id: lineage.subject_id, metadata: %{}}),
      evidence_refs: [],
      governance_refs: [],
      extensions:
        compact(%{
          "tenant_id" => lineage.tenant_id,
          "authority_scope" => lineage.authority_scope,
          "trace_id" => trace_id,
          "causation_id" => lineage.causation_id,
          "canonical_idempotency_key" => canonical_idempotency_key,
          "source_position" => source_position,
          "boundary_session_id" => lineage.boundary_session_id
        })
    })
  end

  defp rejection(name, observation) do
    before_snapshot = SignalIngress.snapshot(name)
    {:error, rejection} = SignalIngress.deliver_observation(name, observation)
    after_snapshot = SignalIngress.snapshot(name)

    rejection
    |> Map.take([
      :reason,
      :missing_fields,
      :previous_source_anchor,
      :current_source_anchor,
      :safe_action,
      :retry_after_ms,
      :resource_exhaustion?,
      :delivery_order_scope
    ])
    |> Map.merge(%{
      partition_queue_depths_unchanged?:
        before_snapshot.partition_queue_depths == after_snapshot.partition_queue_depths,
      accepted?: false
    })
  end

  defp with_aitrace_exporter(fun) when is_function(fun, 1) do
    fun.([{TestExporter, test_pid: self()}])
  end

  defp admission_policy do
    [
      bucket_capacity: 16,
      refill_rate_per_second: 16,
      max_queue_depth_per_partition: 16,
      max_in_flight_per_tenant_scope: 16,
      retry_after_ms: 100,
      delivery_order_scope: :partition_fifo
    ]
  end

  defp queue_empty?(%{partition_queue_depths: queue_depths}) do
    Enum.all?(queue_depths, fn {_partition, depth} -> depth == 0 end)
  end

  defp wait_until(fun, attempts \\ 40)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Timing.retry_delay(:phase5_lineage_wait_until, 10)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: {:error, :timeout}

  defp compact(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp sha256_ref(bytes), do: "sha256:" <> sha256(bytes)

  defp sha256(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end

  defp unique_name(prefix), do: BoundedNames.global_name(prefix)

  defp stop_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1_000)
    end
  catch
    :exit, _reason -> :ok
  end
end
