defmodule StackLab.Examples.ToyDocumentReview.ContentShapeGate do
  @moduledoc """
  Deterministic content shape measurement for Gate 2.

  The gate deliberately measures plain data samples. It does not make
  production content-addressed or streaming storage load-bearing; it records the
  storage shape needed before that later implementation is finalized.
  """

  @inline_threshold_bytes 65_536

  @sample_specs [
    {:source_read, :payload, :product_authored_content, :write_once_read_once,
     %{document_id: "doc-001", cursor: nil, page_size: 25}},
    {:source_read, :result, :provider_response, :write_once_read_many,
     %{
       documents: [
         %{document_id: "doc-001", title: "Vendor contract", state: "ready_for_review"}
       ],
       next_cursor: nil
     }},
    {:source_publication, :payload, :product_authored_content, :write_once_read_once,
     %{document_id: "doc-001", channel: "review_queue", reviewer_refs: ["operator://reviewer"]}},
    {:source_publication, :result, :provider_response, :write_once_read_many,
     %{
       publication_ref: "publication://toy-document-review/doc-001",
       provider_object_refs: ["local-http://reviews/doc-001"],
       status: "published"
     }},
    {:runtime, :payload, :product_authored_content, :write_once_read_once,
     %{document_id: "doc-001", task: "summarize_risks", constraints: ["neutral", "redacted"]}},
    {:runtime, :result, :normalized_platform_record, :replay_only,
     %{
       run_ref: "runtime-run://toy-document-review/doc-001",
       summary_ref: "summary://toy-document-review/doc-001",
       token_count: 512
     }},
    {:runtime_tool, :payload, :product_authored_content, :write_once_read_once,
     %{document_id: "doc-001", query_ref: "query://toy-document-review/extract-clauses"}},
    {:runtime_tool, :result, :normalized_platform_record, :replay_only,
     %{clauses: ["termination", "data_processing"], confidence: "deterministic"}},
    {:evidence, :payload, :product_authored_content, :write_once_read_once,
     %{document_id: "doc-001", evidence_policy_ref: "policy://toy-document-review/evidence"}},
    {:evidence, :result, :operator_visible_output, :write_once_read_many,
     %{
       evidence_refs: ["evidence://toy-document-review/doc-001/risk-summary"],
       redacted_excerpt_class: "contract_clause_summary"
     }},
    {:resource_effect, :payload, :product_authored_content, :write_once_read_once,
     %{document_id: "doc-001", archive_policy_ref: "archive://toy-document-review/final"}},
    {:resource_effect, :result, :provider_response, :write_once_read_many,
     %{
       archive_ref: "archive://toy-document-review/doc-001",
       provider_object_refs: ["local-http://archive/doc-001"],
       status: "archived"
     }},
    {:projection, :result, :operator_visible_output, :write_once_read_many,
     %{
       subject_ref: "subject://toy-document-review/doc-001",
       lifecycle_state: "reviewed",
       operation_receipt_refs: ["receipt://toy-document-review/review_runtime"]
     }},
    {:replay, :result, :normalized_platform_record, :replay_only,
     %{
       trace_ref: "trace://toy-document-review/foundation",
       predecessor_event_refs: ["lineage://toy-document-review/review_runtime"],
       replay_mode: "core_lineage"
     }}
  ]

  @spec run() :: map()
  def run do
    samples = Enum.map(@sample_specs, &sample/1)
    measurements = Enum.map(samples, &measure_sample/1)

    %{
      gate: :content_store_shape,
      fixture: :toy_document_review,
      encoded_byte_size_kind: :erlang_external_term_for_elixir_fixture,
      inline_threshold_bytes: @inline_threshold_bytes,
      sample_count: length(measurements),
      payload_count: count_kind(measurements, :payload),
      result_count: count_kind(measurements, :result),
      largest_observed_byte_size: measurements |> Enum.map(& &1.byte_size) |> Enum.max(),
      storage_modes_observed:
        measurements |> Enum.map(& &1.storage_mode) |> Enum.uniq() |> Enum.sort(),
      streaming_occurrence_count: Enum.count(measurements, &(&1.storage_mode == :stream)),
      readback_patterns: counts_by(measurements, :readback_pattern),
      source_categories: counts_by(measurements, :source_category),
      source_category_basis_points: basis_points_by(measurements, :source_category),
      operation_role_byte_sizes: byte_sizes_by_role(measurements),
      redaction_schema_requirements: redaction_schema_requirements(measurements),
      acceptance: acceptance(measurements)
    }
  end

  defp sample({operation_role, item_kind, source_category, readback_pattern, data}) do
    %{
      operation_role: operation_role,
      item_kind: item_kind,
      source_category: source_category,
      readback_pattern: readback_pattern,
      storage_mode: :inline,
      schema_ref: "schema://toy-document-review/#{operation_role}/#{item_kind}.v1",
      redaction_ref: "redaction://toy-document-review/#{operation_role}/#{item_kind}.v1",
      data: data
    }
  end

  defp measure_sample(sample) do
    Map.put(sample, :byte_size, sample.data |> :erlang.term_to_binary() |> byte_size())
  end

  defp count_kind(measurements, item_kind) do
    Enum.count(measurements, &(&1.item_kind == item_kind))
  end

  defp counts_by(measurements, key) do
    measurements
    |> Enum.map(&Map.fetch!(&1, key))
    |> Enum.frequencies()
  end

  defp basis_points_by(measurements, key) do
    total = length(measurements)

    measurements
    |> counts_by(key)
    |> Map.new(fn {value, count} -> {value, div(count * 10_000, total)} end)
  end

  defp byte_sizes_by_role(measurements) do
    measurements
    |> Enum.group_by(& &1.operation_role)
    |> Map.new(fn {role, samples} ->
      sizes = Enum.map(samples, & &1.byte_size)

      {role,
       %{
         sample_count: length(samples),
         min_byte_size: Enum.min(sizes),
         max_byte_size: Enum.max(sizes),
         total_byte_size: Enum.sum(sizes)
       }}
    end)
  end

  defp redaction_schema_requirements(measurements) do
    measurements
    |> Enum.map(fn measurement ->
      %{
        operation_role: measurement.operation_role,
        item_kind: measurement.item_kind,
        schema_ref: measurement.schema_ref,
        redaction_ref: measurement.redaction_ref,
        source_category: measurement.source_category
      }
    end)
  end

  defp acceptance(measurements) do
    largest = measurements |> Enum.map(& &1.byte_size) |> Enum.max()

    %{
      default_inline_threshold_accepted?: largest < @inline_threshold_bytes,
      production_content_addressed_load_bearing?: false,
      production_streaming_load_bearing?: false,
      backend_decision: :inline_until_real_payloads_exceed_threshold,
      retention_refs_required: [
        :run_snapshot,
        :operation_receipt,
        :projection,
        :replay_bundle
      ],
      gc_batch_size_decision: :blocked_until_content_addressed_storage_is_load_bearing,
      lower_payload_normalization_owner: :mezzanine_lower_boundary
    }
  end
end
