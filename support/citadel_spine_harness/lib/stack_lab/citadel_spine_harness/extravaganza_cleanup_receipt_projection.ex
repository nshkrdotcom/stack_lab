defmodule StackLab.CitadelSpineHarness.ExtravaganzaCleanupReceiptProjection do
  @moduledoc """
  Builds the generic receipt/projection proof for Extravaganza cleanup output.

  The proof consumes the product readback envelope returned by Extravaganza and
  reduces its lower operation receipts through Mezzanine's generic receipt
  reducer. This keeps the destructive product proof from passing on product-only
  output.
  """

  alias Mezzanine.Projections.ReceiptReducer
  alias Mezzanine.Substrate.OperationGroupReceipt
  alias Mezzanine.Substrate.OperationReceipt
  alias Mezzanine.Substrate.ResultEnvelope

  @schema_name "extravaganza_cleanup_generic_receipt_projection_v1"
  @base_time ~U[2026-05-17 00:00:00Z]
  @result_schema_ref "schema://extravaganza/github-pr-cleanup/operation-result/v1"
  @redaction_ref "redaction://extravaganza/github-pr-cleanup/ref-only"
  @succeeded_statuses [:succeeded, :completed, :receipt_recorded, :skipped]
  @failed_statuses [:failed]
  @blocked_statuses [:denied]
  @string_statuses %{
    "succeeded" => :succeeded,
    "completed" => :succeeded,
    "receipt_recorded" => :succeeded,
    "skipped" => :succeeded,
    "failed" => :failed,
    "denied" => :blocked
  }

  @spec build(map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(first_cleanup, idempotent_cleanup, opts \\ [])

  def build(first_cleanup, idempotent_cleanup, opts)
      when is_map(first_cleanup) and is_map(idempotent_cleanup) and is_list(opts) do
    with {:ok, first} <- reduce_product_cleanup(:product_cleanup, first_cleanup, opts),
         {:ok, idempotent} <- reduce_product_cleanup(:idempotent_rerun, idempotent_cleanup, opts) do
      {:ok,
       %{
         schema_name: @schema_name,
         reducer_module: "Mezzanine.Projections.ReceiptReducer",
         proof_scope: "destructive_cleanup_product_readback",
         product_cleanup: first,
         idempotent_rerun: idempotent,
         assertions: assertions([first, idempotent])
       }}
    end
  end

  def build(_first_cleanup, _idempotent_cleanup, _opts),
    do: {:error, :invalid_cleanup_projection_inputs}

  defp reduce_product_cleanup(label, envelope, opts) do
    effect = provider_effect(envelope)

    with {:ok, operation_maps} <- operation_maps(effect),
         {:ok, receipts} <- operation_receipts(label, envelope, effect, operation_maps, opts),
         {:ok, group} <- operation_group_receipt(label, envelope, effect, receipts),
         {:ok, reduced} <-
           ReceiptReducer.reduce(group,
             operation_receipts: receipts,
             lineage_event_contract: :full_execution,
             review_state: :skipped
           ) do
      {:ok, summarize(label, envelope, effect, group, receipts, reduced)}
    end
  end

  defp operation_maps(effect) do
    case Map.get(effect, "operation_receipts") do
      receipts when is_list(receipts) and receipts != [] ->
        if Enum.all?(receipts, &is_map/1) do
          {:ok, receipts}
        else
          {:error, {:invalid_generic_operation_receipts, receipts}}
        end

      receipts ->
        {:error, {:missing_generic_operation_receipts, receipts}}
    end
  end

  defp operation_receipts(label, envelope, effect, operation_maps, opts) do
    operation_maps
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {operation, index}, {:ok, acc} ->
      case operation_receipt(label, envelope, effect, operation, index, opts) do
        {:ok, receipt} -> {:cont, {:ok, [receipt | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, receipts} -> {:ok, Enum.reverse(receipts)}
      error -> error
    end
  end

  defp operation_receipt(label, envelope, effect, operation, index, opts) do
    status = operation_status(operation, effect)
    receipt_ref = receipt_ref(label, operation, index)

    case result_envelope(label, effect, operation, receipt_ref) do
      {:ok, result} ->
        OperationReceipt.new(%{
          receipt_ref: receipt_ref,
          operation_context_ref: operation_context_ref(label, envelope),
          operation_plan_ref: operation_plan_ref(label, operation, index),
          trace_ref: trace_ref(envelope, operation),
          status: status,
          started_at: DateTime.add(base_time(opts), index * 2, :second),
          completed_at: DateTime.add(base_time(opts), index * 2 + 1, :second),
          result: result,
          lineage_event_refs: [
            "lineage://extravaganza/github-cleanup/#{label_name(label)}/#{index}/effect-receipted",
            "lineage://extravaganza/github-cleanup/#{label_name(label)}/#{index}/receipt-reduced"
          ],
          metadata: operation_metadata(label, envelope, effect, operation)
        })

      error ->
        error
    end
  end

  defp operation_group_receipt(label, envelope, effect, receipts) do
    OperationGroupReceipt.new(%{
      group_receipt_ref:
        "operation-group-receipt://extravaganza/github-cleanup/#{label_name(label)}",
      operation_context_ref: operation_context_ref(label, envelope),
      receipt_refs: Enum.map(receipts, & &1.receipt_ref),
      status: group_status(receipts),
      metadata: %{
        group_kind: :resource_effect,
        subject_ref: subject_ref(envelope),
        product_operation: operation(envelope),
        resource_effect_role_ref: Map.get(effect, "resource_effect_role_ref")
      }
    })
  end

  defp result_envelope(label, effect, operation, receipt_ref) do
    ResultEnvelope.new(%{
      result_ref: "result://#{receipt_ref}",
      storage_mode: :inline,
      schema_ref: @result_schema_ref,
      redaction_ref: @redaction_ref,
      data: %{
        capability_id: map_value(operation, :capability_id),
        lower_request_ref: map_value(operation, :lower_request_ref),
        lower_receipt_ref: map_value(operation, :lower_receipt_ref),
        provider_request_sent?: Map.get(effect, "provider_request_sent?"),
        provider_response_received?: Map.get(effect, "provider_response_received?"),
        product_readback_confirmed?: Map.get(effect, "product_readback_confirmed?"),
        proof_label: label_name(label)
      },
      metadata: %{
        projection_readback: :inline_redacted,
        content_owner_ref: "operation://extravaganza/github-cleanup/#{label_name(label)}"
      }
    })
  end

  defp operation_metadata(label, envelope, effect, operation) do
    %{
      operation_role: :resource_effect,
      operation_class: map_value(operation, :capability_id) || Map.get(effect, "operation"),
      subject_ref: subject_ref(envelope),
      provider_object_refs: provider_object_refs(effect),
      provider_facts: provider_facts(effect, operation),
      connector_manifest_ref: map_value(operation, :connector_manifest_ref),
      credential_lease_ref: map_value(operation, :credential_lease_ref),
      effect_request_ref:
        map_value(operation, :effect_request_ref) || map_value(operation, :lower_request_ref),
      connector_binding_ref: map_value(operation, :connector_binding_ref),
      extensions:
        %{
          product_operation: operation(envelope),
          execution_route_ref: Map.get(envelope, "execution_route_ref"),
          proof_label: label_name(label),
          status: Map.get(effect, "status"),
          write_operations: Map.get(effect, "write_operations") || [],
          closed_pull_numbers: Map.get(effect, "closed_pull_numbers") || []
        }
        |> compact()
    }
    |> compact()
  end

  defp summarize(label, envelope, effect, group, receipts, reduced) do
    %{
      proof_label: label,
      product_operation: operation(envelope),
      operation_context_ref: group.operation_context_ref,
      operation_group_receipt_ref: group.group_receipt_ref,
      operation_group_status: group.status,
      operation_receipt_refs: Enum.map(receipts, & &1.receipt_ref),
      operation_capability_ids:
        receipts
        |> Enum.map(&metadata_value(&1.metadata, :operation_class))
        |> Enum.reject(&is_nil/1),
      reducer_module: inspect(reduced.reducer_module),
      projection_ref: reduced.projection.projection_ref,
      projection_status: reduced.projection.status,
      resource_effect_receipt_refs:
        Enum.map(reduced.projection.resource_effects, & &1.receipt_ref),
      lower_receipt_summary_ref: reduced.lower_receipt_summary.summary_ref,
      lower_receipt_summary_status: reduced.lower_receipt_summary.status,
      operation_dispositions: Enum.map(reduced.operation_dispositions, & &1.disposition),
      lineage_event_outbox_ref: reduced.lineage_event_outbox.outbox_ref,
      lineage_event_count: length(reduced.lineage_events),
      lineage_event_kinds: Enum.map(reduced.lineage_events, & &1.event_kind),
      replay_exported?: Enum.any?(reduced.lineage_events, &(&1.event_kind == :replay_exported)),
      provider_object_refs: reduced.projection.provider_object_refs,
      product_readback:
        %{
          provider_effect_operation_receipts_present?:
            Map.get(effect, "operation_receipts") != [],
          provider_effect_receipt_refs_present?:
            map_size(Map.get(effect, "receipt_refs") || %{}) > 0,
          lower_request_ref: Map.get(effect, "lower_request_ref"),
          lower_receipt_ref: Map.get(effect, "lower_receipt_ref")
        }
        |> compact()
    }
  end

  defp assertions(reductions) do
    event_kinds = Enum.flat_map(reductions, & &1.lineage_event_kinds)

    %{
      operation_receipt_emitted?: Enum.all?(reductions, &(&1.operation_receipt_refs != [])),
      operation_group_receipt_emitted?:
        Enum.all?(reductions, &is_binary(&1.operation_group_receipt_ref)),
      reduced_through_receipt_reducer?:
        Enum.all?(reductions, &(&1.reducer_module == "Mezzanine.Projections.ReceiptReducer")),
      lineage_outbox_emitted?: Enum.all?(reductions, &(&1.lineage_event_count > 0)),
      projection_readback_emitted?: Enum.all?(reductions, &is_binary(&1.projection_ref)),
      replay_exported?: Enum.all?(reductions, & &1.replay_exported?),
      product_readback_wraps_generic_receipts?:
        Enum.all?(reductions, & &1.product_readback.provider_effect_operation_receipts_present?),
      required_lineage_event_kinds_present?:
        Enum.all?(
          [
            :command_recorded,
            :workflow_started,
            :operation_requested,
            :jido_manifest_resolved,
            :credential_lease_materialized,
            :effect_requested,
            :effect_receipted,
            :receipt_reduced,
            :projection_updated,
            :replay_exported
          ],
          &(&1 in event_kinds)
        )
    }
  end

  defp receipt_ref(label, operation, index) do
    map_value(operation, :lower_receipt_ref) ||
      "operation-receipt://extravaganza/github-cleanup/#{label_name(label)}/#{index}"
  end

  defp operation_plan_ref(label, operation, index) do
    map_value(operation, :operation_plan_ref) ||
      "operation-plan://extravaganza/github-cleanup/#{label_name(label)}/#{index}"
  end

  defp operation_context_ref(label, envelope) do
    "operation-context://extravaganza/github-cleanup/#{trace_slug(trace_ref(envelope, %{}))}/#{label_name(label)}"
  end

  defp trace_ref(envelope, operation) do
    map_value(operation, :trace_id) || Map.get(envelope, "trace_id") ||
      "trace://extravaganza/cleanup"
  end

  defp subject_ref(envelope) do
    "subject://extravaganza/#{operation(envelope) || "live.github-pr-cleanup"}"
  end

  defp operation(envelope),
    do: Map.get(envelope, "operation") || get_in(envelope, ["data", "operation"])

  defp operation_status(operation, effect) do
    operation
    |> map_value(:status)
    |> Kernel.||(Map.get(effect, "status"))
    |> normalized_status()
  end

  defp normalized_status(status) when status in @succeeded_statuses, do: :succeeded
  defp normalized_status(status) when status in @failed_statuses, do: :failed
  defp normalized_status(status) when status in @blocked_statuses, do: :blocked

  defp normalized_status(status) when is_binary(status),
    do: Map.get(@string_statuses, status, :succeeded)

  defp normalized_status(_status), do: :succeeded

  defp group_status(receipts) do
    statuses = Enum.map(receipts, & &1.status)

    cond do
      Enum.all?(statuses, &(&1 == :succeeded)) -> :succeeded
      Enum.any?(statuses, &(&1 == :failed)) -> :failed
      Enum.any?(statuses, &(&1 == :blocked)) -> :blocked
      true -> :partial_success
    end
  end

  defp provider_effect(envelope) do
    envelope
    |> Map.get("data", %{})
    |> Map.get("provider_effect", %{})
  end

  defp provider_object_refs(effect) do
    pull_refs =
      effect
      |> Map.get("provider_refs", %{})
      |> map_value(:pull_requests)
      |> List.wrap()
      |> Enum.filter(&present?/1)

    pull_numbers =
      effect
      |> Map.get("pull_numbers")
      |> List.wrap()
      |> Enum.filter(&is_integer/1)
      |> Enum.map(&Integer.to_string/1)

    %{}
    |> put_nonempty("github.pull_request_refs", pull_refs)
    |> put_nonempty("github.pull_request_numbers", pull_numbers)
  end

  defp provider_facts(effect, operation) do
    [
      %{
        fact_ref:
          "provider-fact://extravaganza/github-cleanup/#{trace_slug(Map.get(effect, "lower_receipt_ref") || map_value(operation, :lower_receipt_ref) || "unknown")}",
        fact_kind: :resource_effect,
        operation: Map.get(effect, "operation"),
        capability_id: map_value(operation, :capability_id)
      }
      |> compact()
    ]
  end

  defp base_time(opts) do
    case Keyword.get(opts, :base_time) do
      %DateTime{} = value -> value
      _other -> @base_time
    end
  end

  defp label_name(:product_cleanup), do: "product-cleanup"
  defp label_name(:idempotent_rerun), do: "idempotent-rerun"

  defp metadata_value(%{} = metadata, key) do
    case Map.fetch(metadata, key) do
      {:ok, value} -> value
      :error -> Map.get(metadata, Atom.to_string(key))
    end
  end

  defp map_value(%{} = map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
  defp map_value(_value, _key), do: nil

  defp put_nonempty(map, _key, []), do: map
  defp put_nonempty(map, key, value), do: Map.put(map, key, value)

  defp compact(map), do: Map.reject(map, fn {_key, value} -> value in [nil, "", [], %{}] end)

  defp present?(value), do: value not in [nil, "", []]

  defp trace_slug(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.to_charlist()
    |> Enum.map(fn
      byte when byte in ?a..?z -> byte
      byte when byte in ?0..?9 -> byte
      ?. -> ?.
      ?_ -> ?_
      ?- -> ?-
      _other -> ?-
    end)
    |> List.to_string()
    |> String.trim("-")
  end
end
