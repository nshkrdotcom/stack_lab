defmodule StackLab.Examples.ToyDocumentReview.LocalHttpConnector do
  @moduledoc false

  alias Jido.Integration.V2.{
    AuthSpec,
    CatalogSpec,
    GovernedLowerReceipt,
    Manifest,
    ManifestRegistry,
    Manifests,
    OperationLookupRequest,
    OperationSpec
  }

  alias StackLab.Examples.ToyDocumentReview.LocalHttpService

  @connector_ref "connector://toy-document-review/local-http"
  @manifest_ref "manifest://toy-document-review/local-http/v1"
  @credential_scope_ref "credential-scope://toy-document-review/local-http"
  @connector_version "1.0.0"

  defmodule Handler do
    @moduledoc false

    def run(input, _context), do: {:ok, input}
  end

  def connector_ref, do: @connector_ref
  def manifest_ref, do: @manifest_ref
  def credential_scope_ref, do: @credential_scope_ref

  def manifest_entry do
    ManifestRegistry.Entry.new!(
      connector_ref: @connector_ref,
      manifest_ref: @manifest_ref,
      manifest: manifest(),
      provider_family: "local_http_fixture",
      adapter_ref: "adapter://toy-document-review/local-http",
      connector_version: @connector_version,
      metadata: %{credential_scope_ref: @credential_scope_ref}
    )
  end

  def manifest do
    Manifest.new!(%{
      connector: "toy_document_review_local_http",
      auth:
        AuthSpec.new!(%{
          binding_kind: :connection_id,
          auth_type: :api_token,
          install: %{required: true},
          reauth: %{supported: true},
          requested_scopes: [
            "documents:read",
            "documents:write",
            "reviews:run",
            "evidence:read",
            "effects:write"
          ],
          lease_fields: ["credential_lease_ref"],
          secret_names: []
        }),
      catalog:
        CatalogSpec.new!(%{
          display_name: "Toy Document Review Local HTTP",
          description: "Deterministic local document review connector",
          category: "documents",
          tags: ["documents", "review", "local-http"],
          docs_refs: [],
          maturity: :experimental,
          publication: :internal
        }),
      operations: [
        operation(
          "toy.documents.read",
          :source_read,
          :source,
          :read,
          ["documents:read"],
          :get,
          "/documents"
        ),
        operation(
          "toy.reviews.publish",
          :source_write,
          :source_publication,
          :write,
          ["documents:write"],
          :post,
          "/reviews"
        ),
        operation(
          "toy.review.run",
          :runtime_session,
          :runtime,
          :write,
          ["reviews:run"],
          :post,
          "/runtime/review"
        ),
        operation(
          "toy.review.extract",
          :runtime_tool_invocation,
          :runtime_tool,
          :read,
          ["documents:read"],
          :post,
          "/tools/extract"
        ),
        operation(
          "toy.evidence.collect",
          :evidence_collection,
          :evidence,
          :read,
          ["evidence:read"],
          :post,
          "/evidence/collect"
        ),
        operation(
          "toy.document.archive",
          :resource_effect,
          :resource_effect,
          :write,
          ["effects:write"],
          :post,
          "/effects/archive"
        )
      ],
      triggers: [],
      runtime_families: [:direct],
      metadata: %{schema_version: LocalHttpService.schema_version()}
    })
  end

  def resolve_operation(request_attrs) when is_map(request_attrs) do
    with {:ok, request} <- OperationLookupRequest.new(request_attrs) do
      Manifests.resolve_operation(request, manifest_entries: [manifest_entry()])
    end
  end

  def invoke(server, lower_envelope, input, opts \\ []) when is_list(opts) do
    operation_ref = Map.fetch!(lower_envelope.extensions, "operation_ref")
    request_opts = request_opts(input, opts)

    case LocalHttpService.request(
           server,
           method(operation_ref),
           path(operation_ref),
           request_opts
         ) do
      {:ok, response} ->
        {:ok, lower_receipt(lower_envelope, :succeeded, response.body)}

      {:error, %{reason: :timeout} = response} ->
        {:ok, lower_receipt(lower_envelope, :timed_out, response)}

      {:error, %{reason: :auth_rejected} = response} ->
        {:ok, lower_receipt(lower_envelope, :denied, response)}

      {:error, response} ->
        {:ok, lower_receipt(lower_envelope, :failed, response)}
    end
  end

  defp operation(
         operation_id,
         operation_class,
         binding_kind,
         side_effect_class,
         scopes,
         method,
         path
       ) do
    OperationSpec.new!(%{
      operation_id: operation_id,
      name: operation_id,
      display_name: operation_id,
      description: operation_id,
      runtime_class: :direct,
      transport_mode: :http,
      handler: Handler,
      input_schema: Zoi.object(%{document_id: Zoi.string() |> Zoi.optional()}),
      output_schema:
        Zoi.object(%{
          document_id: Zoi.string() |> Zoi.optional(),
          event_ref: Zoi.string() |> Zoi.optional(),
          receipt_ref: Zoi.string() |> Zoi.optional(),
          status: Zoi.string() |> Zoi.optional()
        }),
      permissions: %{required_scopes: scopes},
      runtime: %{},
      policy: %{},
      upstream: %{method: Atom.to_string(method), path: path},
      consumer_surface: %{
        mode: :common,
        normalized_id: operation_id,
        action_name: operation_id
      },
      schema_policy: %{input: :defined, output: :defined},
      jido: %{action: %{name: operation_id}},
      metadata: %{
        operation_class: operation_class,
        binding_kind: binding_kind,
        side_effect_class: side_effect_class,
        provider_operation_id: operation_id,
        input_schema_ref: "schema://toy-document-review/#{operation_id}/input",
        output_schema_ref: "schema://toy-document-review/#{operation_id}/output"
      }
    })
  end

  defp request_opts(input, opts) do
    [
      credential_lease_ref: Keyword.fetch!(opts, :credential_lease_ref),
      schema_version: Keyword.get(opts, :schema_version, LocalHttpService.schema_version()),
      lease_expires_at: Keyword.get(opts, :lease_expires_at),
      now: Keyword.get(opts, :now, ~U[2026-05-17 00:01:00Z]),
      timeout_ms: Keyword.get(opts, :timeout_ms, 250),
      failure_mode: Keyword.get(opts, :failure_mode),
      input: input
    ]
  end

  defp lower_receipt(envelope, status, result) do
    GovernedLowerReceipt.new!(%{
      lower_receipt_ref: envelope.lower_request_ref <> "/receipt",
      lower_request_ref: envelope.lower_request_ref,
      lower_runtime_kind: envelope.lower_runtime_kind,
      runtime_profile_ref: envelope.runtime_profile_ref,
      runtime_profile_kind: envelope.runtime_profile_kind,
      status: status,
      tenant_ref: envelope.tenant_ref,
      subject_ref: envelope.subject_ref,
      run_ref: envelope.run_ref,
      trace_id: envelope.trace_id,
      idempotency_key: envelope.idempotency_key,
      authority_ref: envelope.authority_ref,
      authority_decision_hash: envelope.authority_decision_hash,
      allowed_operations: envelope.allowed_operations,
      capability_id: envelope.capability_id,
      action_id: envelope.action_id,
      connector_ref: envelope.connector_ref,
      connector_manifest_ref: envelope.connector_manifest_ref,
      connector_manifest_hash: envelope.connector_manifest_hash,
      connector_manifest_state: :active,
      artifact_refs: artifact_refs(result),
      event_refs: [],
      observed_at: ~U[2026-05-17 00:01:30Z],
      extensions: %{"result" => result}
    })
  end

  defp method("toy.documents.read"), do: :get
  defp method(_operation_ref), do: :post

  defp path("toy.documents.read"), do: "/documents"
  defp path("toy.reviews.publish"), do: "/reviews"
  defp path("toy.review.run"), do: "/runtime/review"
  defp path("toy.review.extract"), do: "/tools/extract"
  defp path("toy.evidence.collect"), do: "/evidence/collect"
  defp path("toy.document.archive"), do: "/effects/archive"

  defp artifact_refs(%{artifacts: artifacts}) when is_list(artifacts), do: artifacts
  defp artifact_refs(_result), do: []
end
