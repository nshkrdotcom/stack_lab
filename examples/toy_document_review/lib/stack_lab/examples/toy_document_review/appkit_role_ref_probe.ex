defmodule StackLab.Examples.ToyDocumentReview.AppKitRoleRefProbe do
  @moduledoc false

  alias AppKit.Core.{ActorRef, Context, InstallationRef, TenantRef}
  alias AppKit.{Evidence, Reviews, RuntimeGateway, Sources, Traces}
  alias StackLab.Examples.ToyDocumentReview.{Pack, ProductHost}

  defmodule Backend do
    @moduledoc false

    def fetch_candidates(%AppKit.Core.Context{} = context, source_role_ref, query, _opts) do
      ok(:source_candidates, context, source_role_ref, nil, query)
    end

    def publish(%AppKit.Core.Context{} = context, publication_role_ref, request, _opts) do
      ok(:source_publication, context, publication_role_ref, nil, request)
    end

    def invoke_runtime_operation(
          %AppKit.Core.Context{} = context,
          runtime_role_ref,
          operation_role_ref,
          request,
          _opts
        ) do
      ok(:runtime_operation, context, runtime_role_ref, operation_role_ref, request)
    end

    def invoke_runtime_tool(
          %AppKit.Core.Context{} = context,
          tool_role_ref,
          operation_role_ref,
          request,
          _opts
        ) do
      ok(:runtime_tool, context, tool_role_ref, operation_role_ref, request)
    end

    def collect_evidence(%AppKit.Core.Context{} = context, evidence_role_ref, request, _opts) do
      ok(:evidence_collection, context, evidence_role_ref, nil, request)
    end

    def invoke_resource_effect(
          %AppKit.Core.Context{} = context,
          resource_effect_role_ref,
          request,
          _opts
        ) do
      ok(:resource_effect, context, resource_effect_role_ref, nil, request)
    end

    def open_review(%AppKit.Core.Context{} = context, subject_ref, request, _opts) do
      ok(:review_opened, context, subject_ref, nil, request)
    end

    def replay_trace(%AppKit.Core.Context{} = context, trace_ref, _opts) do
      ok(:trace_replay, context, trace_ref, nil, %{trace_ref: trace_ref})
    end

    defp ok(surface, context, role_ref, operation_role_ref, request) do
      {:ok,
       %{
         surface: surface,
         trace_ref: context.trace_ref,
         role_ref: role_ref,
         operation_role_ref: operation_role_ref,
         request: request
       }}
    end
  end

  def run do
    opts = [generic_backend: Backend]

    with {:ok, context} <- appkit_context(),
         {:ok, source} <-
           Sources.fetch_candidates(context, :incoming_documents, %{state: :submitted}, opts),
         {:ok, publication} <-
           Sources.publish(
             context,
             :review_queue_publication,
             %{subject_ref: "subject://toy-document-review/doc-001"},
             opts
           ),
         {:ok, runtime} <-
           RuntimeGateway.invoke_runtime_operation(
             context,
             :document_reviewer,
             :run,
             %{input_ref: "input://toy-document-review/doc-001"},
             opts
           ),
         {:ok, tool} <-
           RuntimeGateway.invoke_runtime_tool(
             context,
             :document_classifier,
             :lookup,
             %{input_ref: "input://toy-document-review/doc-001/extract"},
             opts
           ),
         {:ok, evidence} <-
           Evidence.collect(
             context,
             :review_report,
             %{subject_ref: "subject://toy-document-review/doc-001"},
             opts
           ),
         {:ok, effect} <-
           RuntimeGateway.invoke_resource_effect(
             context,
             :document_archive,
             %{subject_ref: "subject://toy-document-review/doc-001"},
             opts
           ),
         {:ok, review} <-
           Reviews.open(
             context,
             "subject://toy-document-review/doc-001",
             %{review_role_ref: :operator_summary},
             opts
           ),
         {:ok, trace} <- Traces.replay(context, "trace://toy-document-review/foundation", opts) do
      calls = [source, publication, runtime, tool, evidence, effect, review, trace]

      {:ok,
       %{
         accepted?: Enum.all?(calls, &role_ref_only?/1),
         surfaces: Enum.map(calls, & &1.surface),
         role_refs: Enum.map(calls, & &1.role_ref),
         operation_role_refs:
           calls |> Enum.map(& &1.operation_role_ref) |> Enum.reject(&is_nil/1),
         concrete_binding_refs_seen?: Enum.any?(calls, &concrete_binding_ref?/1)
       }}
    end
  end

  defp appkit_context do
    with {:ok, actor_ref} <-
           ActorRef.new(%{
             id: "actor://toy-document-review/operator",
             kind: :operator,
             roles: ["toy_document_review_operator"]
           }),
         {:ok, tenant_ref} <-
           TenantRef.new(%{id: "tenant-toy-document-review", slug: "toy-document-review"}),
         {:ok, installation_ref} <-
           InstallationRef.new(%{
             id: "installation://toy-document-review/local",
             pack_slug: Pack.pack_slug(),
             pack_version: Pack.version(),
             status: :active
           }) do
      Context.new(%{
        actor_ref: actor_ref,
        tenant_ref: tenant_ref,
        installation_ref: installation_ref,
        trace_ref: "trace://toy-document-review/appkit-role-ref-probe",
        request_ref: "request://toy-document-review/appkit-role-ref-probe",
        idempotency_key: "toy-document-review-appkit-role-ref-probe",
        authority_ref: "authority://toy-document-review/appkit-role-ref-probe",
        release_manifest_ref: "release://toy-document-review/local",
        metadata: %{proof: :toy_document_review}
      })
    end
  end

  defp role_ref_only?(%{role_ref: role_ref}) when is_atom(role_ref), do: true
  defp role_ref_only?(%{role_ref: role_ref}) when is_binary(role_ref), do: true
  defp role_ref_only?(_call), do: false

  defp concrete_binding_ref?(%{role_ref: role_ref}) when is_atom(role_ref) do
    role_ref
    |> Atom.to_string()
    |> concrete_binding_ref?()
  end

  defp concrete_binding_ref?(%{role_ref: role_ref}) when is_binary(role_ref),
    do: concrete_binding_ref?(role_ref)

  defp concrete_binding_ref?(role_ref) when is_binary(role_ref) do
    Enum.any?(ProductHost.operation_bindings(), fn {_key, binding} ->
      binding.binding_ref == role_ref
    end)
  end
end
