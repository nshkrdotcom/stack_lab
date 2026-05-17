defmodule StackLab.Examples.ToyDocumentReview.ContentStoreAcceptance do
  @moduledoc """
  Executable Phase 5 acceptance for payload/result envelope storage boundaries.

  This proof intentionally keeps production content-addressed and streaming
  storage non-load-bearing while proving the deterministic content-store
  contract, retention denial, cross-tenant denial, and projection-safe readback
  behavior used by the generic substrate.
  """

  alias Mezzanine.ContentStore
  alias Mezzanine.Projections.EnvelopeAccessSummary
  alias Mezzanine.Substrate.{PayloadEnvelope, ResultEnvelope}
  alias StackLab.Examples.ToyDocumentReview.ContentShapeGate

  @tenant_ref "tenant://toy-document-review"
  @installation_ref "installation://toy-document-review/foundation"
  @owner_ref "operation-context://toy-document-review/content-store-acceptance"
  @store_ref "content-store://toy-document-review/deterministic"
  @retention_ref "receipt://toy-document-review/content-store-acceptance"

  @spec run() :: map()
  def run do
    shape = ContentShapeGate.run()
    body = "redacted review summary"
    {hash, hex} = content_hash(body)
    content_ref = "content://toy-document-review/#{hex}"

    {:ok, inline_payload} =
      PayloadEnvelope.new(%{
        payload_ref: "payload://toy-document-review/content-store-inline",
        storage_mode: :inline,
        schema_ref: "schema://toy-document-review/content-store/payload.v1",
        redaction_ref: "redaction://toy-document-review/content-store/payload.v1",
        data: %{document_id: "doc-001", title: "Redacted review summary"},
        retention_refs: [@retention_ref],
        metadata: projection_metadata()
      })

    {:ok, content_result} =
      ResultEnvelope.new(%{
        result_ref: "result://toy-document-review/content-store-content-addressed",
        storage_mode: :content_addressed,
        schema_ref: "schema://toy-document-review/content-store/result.v1",
        redaction_ref: "redaction://toy-document-review/content-store/result.v1",
        content_ref: content_ref,
        content_hash: hash,
        byte_size: byte_size(body),
        store_ref: @store_ref,
        retention_refs: [@retention_ref],
        metadata: projection_metadata()
      })

    {:ok, stream_payload} =
      PayloadEnvelope.new(%{
        payload_ref: "payload://toy-document-review/content-store-stream",
        storage_mode: :stream,
        schema_ref: "schema://toy-document-review/content-store/stream-payload.v1",
        redaction_ref: "redaction://toy-document-review/content-store/stream-payload.v1",
        stream_ref: "stream://toy-document-review/content-store/stream-payload",
        store_ref: "stream-store://toy-document-review/deterministic",
        data: %{raw_stream_body: "must-not-project"},
        retention_refs: [@retention_ref],
        metadata: projection_metadata()
      })

    {:ok, store, entry} =
      ContentStore.put(%{}, %{
        content_ref: content_ref,
        owner_ref: @owner_ref,
        tenant_ref: @tenant_ref,
        installation_ref: @installation_ref,
        schema_ref: content_result.schema_ref,
        redaction_ref: content_result.redaction_ref,
        content_hash: hash,
        byte_size: byte_size(body),
        body: body,
        retention_refs: [@retention_ref],
        metadata: %{source: :toy_document_review_content_store_acceptance}
      })

    authorized_fetch = ContentStore.fetch(store, content_ref, authorized_context())
    cross_tenant_fetch = ContentStore.fetch(store, content_ref, cross_tenant_context())
    retained_delete = ContentStore.delete(store, content_ref)

    inline_access = EnvelopeAccessSummary.from_payload(inline_payload)
    content_access = EnvelopeAccessSummary.from_result(content_result)
    stream_access = EnvelopeAccessSummary.from_payload(stream_payload)

    %{
      gate: :content_store_acceptance,
      fixture: :toy_document_review,
      content_shape_gate: %{
        storage_modes_observed: shape.storage_modes_observed,
        largest_observed_byte_size: shape.largest_observed_byte_size,
        inline_threshold_bytes: shape.inline_threshold_bytes,
        inline_threshold_accepted?: shape.acceptance.default_inline_threshold_accepted?,
        production_content_addressed_load_bearing?:
          shape.acceptance.production_content_addressed_load_bearing?,
        production_streaming_load_bearing?: shape.acceptance.production_streaming_load_bearing?,
        backend_decision: shape.acceptance.backend_decision
      },
      envelope_contracts: %{
        inline_payload_storage_mode: inline_payload.storage_mode,
        content_addressed_result_storage_mode: content_result.storage_mode,
        stream_payload_storage_mode: stream_payload.storage_mode,
        content_result_hash: content_result.content_hash,
        content_result_ref: content_result.content_ref,
        stream_payload_ref: stream_payload.stream_ref
      },
      projection_access: %{
        inline_readback_mode: inline_access.readback_mode,
        inline_data_visible?: inline_access.data == inline_payload.data,
        content_addressed_readback_mode: content_access.readback_mode,
        content_addressed_data_visible?: not is_nil(content_access.data),
        stream_readback_mode: stream_access.readback_mode,
        stream_data_visible?: not is_nil(stream_access.data)
      },
      content_store_contract: %{
        deterministic_content_ref: entry.content_ref,
        deterministic_content_hash: entry.content_hash,
        deterministic_content_ref_resolved?: resolved?(authorized_fetch),
        cross_tenant_denied?: cross_tenant_fetch == {:error, :unauthorized_content_access},
        retained_delete_denied?:
          retained_delete == {:error, {:content_retained, [@retention_ref]}}
      },
      final_decision:
        :content_addressed_and_streaming_backend_blocked_until_measured_payloads_require_it
    }
  end

  defp projection_metadata do
    %{
      content_owner_ref: @owner_ref,
      read_scope_ref: "read-scope://toy-document-review/projection",
      projection_readback: :inline_redacted
    }
  end

  defp authorized_context do
    %{
      tenant_ref: @tenant_ref,
      installation_ref: @installation_ref
    }
  end

  defp cross_tenant_context do
    %{
      tenant_ref: "tenant://other",
      installation_ref: @installation_ref
    }
  end

  defp content_hash(body) do
    hex =
      :crypto.hash(:sha256, body)
      |> Base.encode16(case: :lower)

    {"sha256:" <> hex, hex}
  end

  defp resolved?({:ok, %ContentStore.Entry{}}), do: true
  defp resolved?(_result), do: false
end
