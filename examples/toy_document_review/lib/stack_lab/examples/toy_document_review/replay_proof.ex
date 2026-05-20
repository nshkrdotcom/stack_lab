defmodule StackLab.Examples.ToyDocumentReview.ReplayProof do
  @moduledoc false

  alias AITrace.ReplayEngine
  alias Mezzanine.Projections.{LineageEventOutbox, ReceiptReducer, SubjectRuntimeProjection}
  alias StackLab.Examples.ToyDocumentReview.{FoundationProof, ProductHost}

  def preflight do
    components = %{
      generic_receipt_reduction: module_function_exported?(ReceiptReducer, :reduce, 2),
      production_projection_mapping:
        module_function_exported?(SubjectRuntimeProjection, :from_operation_receipts, 2),
      mezzanine_execution_record_emission:
        module_function_exported?(LineageEventOutbox, :events_for_projection, 3),
      aitrace_causal_replay: module_function_exported?(ReplayEngine, :replay_lineage_events, 2)
    }

    blocked =
      components
      |> Enum.reject(fn {_component, present?} -> present? end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    %{
      gate: :phase5_toy_receipt_projection_replay_preflight,
      accepted?: blocked == [],
      components: components,
      blocked_components: blocked,
      required_path: ProductHost.phase5_components()
    }
  end

  def run(opts \\ []) when is_list(opts) do
    with {:ok, evidence} <- replay_evidence(opts) do
      preflight = evidence.preflight
      foundation = evidence.foundation
      reduced = evidence.reduced
      replay_events = evidence.replay_events
      replay = evidence.replay

      {:ok,
       %{
         scenario: ProductHost.scenario(),
         preflight: preflight,
         component_path: ProductHost.phase5_components(),
         reducer_module: reduced.reducer_module,
         projection_module: reduced.projection.__struct__,
         projection: projection_summary(reduced),
         lower_receipt_summary: lower_receipt_summary(reduced),
         lineage: lineage_summary(replay_events),
         aitrace_replay: replay_summary(replay),
         product_shape_comparison: product_shape_comparison(reduced),
         foundation_component_path: foundation.component_path
       }}
    end
  end

  def run_gate3(opts \\ []) when is_list(opts) do
    with {:ok, evidence} <- replay_evidence(opts),
         out_of_order_events <- out_of_order_events(evidence.replay_events),
         {:ok, out_of_order_replay} <- replay_stacklab_events(out_of_order_events),
         retry_events <- retry_out_of_order_events(evidence.replay_events),
         {:ok, retry_replay} <- replay_stacklab_events(retry_events) do
      missing_predecessor = missing_predecessor_negative_control(evidence.replay_events)
      delayed_export = delayed_export_proof(evidence.replay_events)

      accepted? =
        evidence.replay.replay_complete? and out_of_order_replay.replay_complete? and
          out_of_order_replay.order_diverged? and not out_of_order_replay.projection_diverged? and
          retry_replay.replay_complete? and retry_replay.order_diverged? and
          not retry_replay.projection_diverged? and missing_predecessor.accepted? and
          delayed_export.accepted?

      {:ok,
       %{
         gate: :aitrace_replay_fidelity,
         proof_app: :toy_document_review,
         accepted?: accepted?,
         event_count: length(evidence.replay_events),
         emit_order_replay: replay_summary(evidence.replay),
         out_of_order_replay: replay_summary(out_of_order_replay),
         missing_predecessor_negative_control: missing_predecessor,
         delayed_export_proof: delayed_export,
         retry_out_of_order_receipt_proof: replay_summary(retry_replay),
         projection_output_comparison: %{
           baseline_diverged?: evidence.replay.projection_diverged?,
           out_of_order_diverged?: out_of_order_replay.projection_diverged?,
           retry_out_of_order_diverged?: retry_replay.projection_diverged?
         },
         required_traces: %{
           proof_app_trace: "trace://toy-document-review/foundation",
           extravaganza_trace:
             "trace:phase11-live-smoke-dryrun-publication from Phase 11 product parity evidence"
         }
       }}
    end
  end

  def summary(proof) do
    %{
      projection: proof.projection,
      lower_receipt_summary: proof.lower_receipt_summary,
      lineage: proof.lineage,
      aitrace_replay: proof.aitrace_replay,
      product_shape_comparison: proof.product_shape_comparison
    }
  end

  defp replay_evidence(opts) do
    preflight = preflight()

    with :ok <- preflight_accepted(preflight),
         {:ok, foundation} <- FoundationProof.run(opts),
         {:ok, reduced} <- reduce_foundation_receipts(foundation),
         replay_events <- stacklab_replay_events(reduced.lineage_events),
         {:ok, replay} <- replay_stacklab_events(replay_events) do
      {:ok,
       %{
         preflight: preflight,
         foundation: foundation,
         reduced: reduced,
         replay_events: replay_events,
         replay: replay
       }}
    end
  end

  defp preflight_accepted(%{accepted?: true}), do: :ok

  defp preflight_accepted(%{blocked_components: blocked}),
    do: {:error, {:blocked_phase5_proof, blocked}}

  defp reduce_foundation_receipts(%{operations: operations}) do
    receipts = Enum.map(operations, &Map.fetch!(&1, :operation_receipt))

    ReceiptReducer.reduce(receipts,
      operation_context_ref: FoundationProof.operation_context().operation_context_ref,
      subject_ref: "subject://toy-document-review/doc-001",
      lineage_event_contract: :full_execution,
      review_state: :opened
    )
  end

  defp replay_stacklab_events(events) do
    ReplayEngine.replay_lineage_events(events,
      trace_profile: :stacklab_proof,
      required_event_kinds: ProductHost.phase5_replay_event_kinds()
    )
  end

  defp stacklab_replay_events(events) do
    Enum.map(events, fn event ->
      Map.merge(event, %{
        trace_level: trace_level_for_event(event.event_kind),
        metadata_refs: Map.merge(event.metadata_refs || %{}, trace_metadata_refs(event))
      })
    end)
  end

  defp trace_level_for_event(:replay_exported), do: :replay_minimum

  defp trace_level_for_event(event_kind) do
    if event_kind in ProductHost.stacklab_detailed_event_kinds(),
      do: :detailed_proof,
      else: :core_lineage
  end

  defp trace_metadata_refs(event) do
    %{
      retention_policy_ref: "retention://stacklab/toy-document-review/phase5",
      ttl_seconds: 86_400,
      emission_mode: :inline,
      emission_expectation_ref: "trace-expectation://toy-document-review/#{event.event_kind}"
    }
  end

  defp out_of_order_events(events) do
    {first_half, second_half} = Enum.split(events, div(length(events), 2))
    second_half ++ first_half
  end

  defp missing_predecessor_negative_control(events) do
    target = Enum.find(events, &(&1.predecessor_event_refs != []))
    missing_ref = "lineage://toy-document-review/missing-predecessor"

    incomplete_events =
      Enum.map(events, fn
        %{event_ref: event_ref} = event when event_ref == target.event_ref ->
          %{event | predecessor_event_refs: [missing_ref]}

        event ->
          event
      end)

    case replay_stacklab_events(incomplete_events) do
      {:error, {:missing_predecessor_events, missing}} ->
        %{
          accepted?: true,
          removed_event_ref: missing_ref,
          failing_event_ref: target.event_ref,
          missing_predecessors: missing
        }

      {:error, reason} ->
        %{accepted?: false, removed_event_ref: missing_ref, unexpected_error: reason}

      {:ok, replay} ->
        %{
          accepted?: false,
          removed_event_ref: missing_ref,
          unexpected_replay: replay_summary(replay)
        }
    end
  end

  defp delayed_export_proof(events) do
    {catchup_events, committed_events} =
      Enum.split_with(events, &(&1.trace_level == :detailed_proof))

    prefix_result = replay_stacklab_events(committed_events)
    catchup_result = replay_stacklab_events(committed_events ++ catchup_events)

    %{
      accepted?: delayed_export_accepted?(prefix_result, catchup_result),
      committed_event_count: length(committed_events),
      catchup_event_count: length(catchup_events),
      prefix_replay: replay_result_summary(prefix_result),
      catchup_replay: replay_result_summary(catchup_result)
    }
  end

  defp delayed_export_accepted?({:error, _reason}, {:ok, replay}),
    do: replay.replay_complete? and not replay.projection_diverged?

  defp delayed_export_accepted?(_prefix_result, _catchup_result), do: false

  defp retry_out_of_order_events(events) do
    effect_requested = Enum.find(events, &(&1.event_kind == :effect_requested))

    effect_receipted =
      Enum.find(events, fn event ->
        event.event_kind == :effect_receipted and
          effect_requested.event_ref in event.predecessor_event_refs
      end)

    retry_event_ref = effect_requested.event_ref <> "/retry-scheduled"

    retry =
      effect_requested
      |> Map.merge(%{
        event_ref: retry_event_ref,
        event_kind: :retry_scheduled,
        predecessor_event_refs: [effect_requested.event_ref],
        projection_key: nil,
        projection_visible?: false,
        causal_order: effect_requested.causal_order + 1,
        projection_order_key:
          replay_projection_order_key(effect_requested.causal_order + 1, retry_event_ref),
        trace_level: :core_lineage,
        metadata_refs:
          Map.merge(effect_requested.metadata_refs || %{}, %{
            retry_policy_ref: "retry://toy-document-review/gate3",
            retry_reason_ref: "retry-reason://toy-document-review/out-of-order-receipt"
          })
      })

    updated_receipted = %{effect_receipted | predecessor_event_refs: [retry.event_ref]}

    events
    |> Enum.map(fn
      %{event_ref: event_ref} when event_ref == effect_receipted.event_ref -> updated_receipted
      event -> event
    end)
    |> insert_after(updated_receipted.event_ref, retry)
  end

  defp insert_after(events, event_ref, inserted) do
    {before, after_including_match} = Enum.split_while(events, &(&1.event_ref != event_ref))

    case after_including_match do
      [matched | rest] -> before ++ [matched, inserted | rest]
      [] -> events ++ [inserted]
    end
  end

  defp replay_projection_order_key(causal_order, event_ref) do
    causal_order
    |> Integer.to_string()
    |> String.pad_leading(8, "0")
    |> Kernel.<>(":#{event_ref}")
  end

  defp replay_result_summary({:ok, replay}), do: replay_summary(replay)
  defp replay_result_summary({:error, reason}), do: %{error: reason}

  defp projection_summary(%{projection: projection}) do
    %{
      projection_ref: projection.projection_ref,
      operation_context_ref: projection.operation_context_ref,
      subject_ref: projection.subject_ref,
      status: projection.status,
      operation_roles: Enum.map(projection.operations, & &1.operation_role),
      operation_classes: Enum.map(projection.operations, & &1.operation_class),
      operation_count: length(projection.operations),
      evidence_count: length(projection.evidence),
      source_publication_count: length(projection.source_publications),
      resource_effect_count: length(projection.resource_effects),
      provider_object_refs: projection.provider_object_refs,
      provider_fact_count: length(projection.provider_facts),
      lineage_event_ref_count: length(projection.lineage_event_refs)
    }
  end

  defp lower_receipt_summary(%{lower_receipt_summary: summary}) do
    %{
      summary_ref: summary.summary_ref,
      status: summary.status,
      operation_count: length(summary.operations),
      provider_object_refs: summary.provider_object_refs,
      metadata: summary.metadata
    }
  end

  defp lineage_summary(events) do
    %{
      event_count: length(events),
      event_kinds: events |> Enum.map(& &1.event_kind) |> Enum.uniq() |> Enum.sort(),
      trace_levels: events |> Enum.map(& &1.trace_level) |> Enum.uniq() |> Enum.sort(),
      projection_visible_event_refs:
        events
        |> Enum.filter(& &1.projection_visible?)
        |> Enum.map(& &1.event_ref)
    }
  end

  defp replay_summary(replay) do
    %{
      replay_complete?: replay.replay_complete?,
      order_diverged?: replay.order_diverged?,
      projection_diverged?: replay.projection_diverged?,
      trace_profile: replay.trace_level_policy.profile,
      required_trace_level: replay.trace_level_policy.required_trace_level,
      proof_event_kinds: replay.trace_level_policy.required_event_kinds,
      emit_order_event_count: length(replay.emit_order_event_refs),
      causal_order_event_count: length(replay.causal_order_event_refs)
    }
  end

  defp product_shape_comparison(%{projection: projection, lower_receipt_summary: summary}) do
    coverage = %{
      operation_roles_complete?: complete_operation_roles?(projection),
      provider_object_refs_present?: map_size(projection.provider_object_refs) > 0,
      provider_facts_present?: projection.provider_facts != [],
      lower_receipt_summary_present?:
        present?(summary.summary_ref) and summary.status == :succeeded and
          summary.operations != [],
      result_access_summaries_present?:
        Enum.all?(projection.operations, &present?(&1.result_ref)),
      lineage_refs_present?: projection.lineage_event_refs != []
    }

    %{
      accepted?: Enum.all?(Map.values(coverage)),
      checked_against: :deterministic_output_migration_table,
      extravaganza_required_field_groups: ProductHost.extravaganza_required_field_groups(),
      generic_fact_coverage: coverage,
      mapping: %{
        standard_envelope: :product_presenter_over_generic_projection,
        refs: :headless_json_refs_from_generic_projection_and_lower_receipt_summary,
        run_detail_runtime_row: :product_run_presenter_over_subject_runtime_projection,
        provider_request_response: :product_provider_facts_from_projection_metadata,
        lower_receipt: :terminal_lower_receipt_shape_and_lower_receipt_summary,
        event_page_entry: :lineage_event_outbox_with_product_presenter
      }
    }
  end

  defp complete_operation_roles?(projection) do
    roles = Enum.map(projection.operations, & &1.operation_role)

    Enum.all?(
      [:source, :publication, :runtime, :tool, :evidence, :resource_effect],
      &(&1 in roles)
    )
  end

  defp module_function_exported?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(nil), do: false
  defp present?(_value), do: true
end
