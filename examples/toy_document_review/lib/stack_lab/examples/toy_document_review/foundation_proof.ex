defmodule StackLab.Examples.ToyDocumentReview.FoundationProof do
  @moduledoc false

  alias Citadel.Authority
  alias Citadel.ConnectorBinding.CredentialLease
  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Mezzanine.ConfigRegistry.{ActiveBindingSet, PackRegistration, RunBindingSnapshot}

  alias Mezzanine.Substrate.{
    BindingResolver,
    ExecutionInstruction,
    OperationContext,
    OperationReceipt,
    OperationRequest,
    PayloadEnvelope,
    ResolvedOperationPlan,
    ResultEnvelope
  }

  alias StackLab.Examples.ToyDocumentReview.{
    LocalHttpConnector,
    LocalHttpService,
    Pack,
    ProductHost
  }

  def run(opts \\ []) when is_list(opts) do
    service = Keyword.fetch!(opts, :service)
    manifest_entry = LocalHttpConnector.manifest_entry()
    pack_manifest = Pack.manifest(manifest_entry.manifest_digest, unique_pack_version())

    with {:ok, compiled_pack} <- compile_pack(pack_manifest),
         {:ok, registry} <- activate_registry(compiled_pack, opts),
         {:ok, operations} <- resolve_operations(service, registry, manifest_entry, opts) do
      {:ok,
       %{
         scenario: ProductHost.scenario(),
         pack: %{
           compiled?: true,
           pack_slug: compiled_pack.pack_slug,
           version: compiled_pack.version,
           binding_count: map_size(compiled_pack.bindings_by_ref)
         },
         registry: registry_summary(registry),
         operations: operations,
         local_http_fixture: fixture_summary(service),
         component_path: ProductHost.required_components()
       }}
    end
  end

  def bypass_rejections(opts \\ []) do
    context = operation_context()
    request = operation_request(:source_read)
    resolution = minimal_resolution()
    descriptor = minimal_descriptor()

    %{
      binding_resolver_missing_authority:
        BindingResolver.resolve_plan(context, request,
          operation_role: "read",
          binding_resolution: resolution,
          operation_descriptor: descriptor,
          credential_lease_ref: LocalHttpService.default_lease_ref()
        ),
      binding_resolver_missing_credential_lease:
        BindingResolver.resolve_plan(context, request,
          operation_role: "read",
          binding_resolution: resolution,
          operation_descriptor: descriptor,
          authority_decision_ref: "authority://toy-document-review/read"
        ),
      manifest_lookup_missing_connector:
        LocalHttpConnector.resolve_operation(%{
          connector_ref: "connector://toy-document-review/missing",
          manifest_ref: LocalHttpConnector.manifest_ref(),
          operation_ref: "toy.documents.read",
          operation_role: :source_read,
          operation_class: :source_read,
          binding_kind: :source,
          required_runtime_family: :direct,
          binding_ref: "document_source",
          pack_ref: Pack.pack_slug(),
          pack_revision: Pack.version(),
          credential_scope_ref: LocalHttpConnector.credential_scope_ref()
        }),
      missing_required_component: require_components([:pack_compiler], opts)
    }
  end

  def summary(proof) do
    %{
      pack: proof.pack,
      registry: proof.registry,
      operation_count: length(proof.operations),
      component_path: proof.component_path,
      local_http_fixture: proof.local_http_fixture
    }
  end

  def bypass_summary(rejections) do
    %{
      missing_authority_fail_closed?: fail_closed?(rejections.binding_resolver_missing_authority),
      missing_lease_fail_closed?:
        fail_closed?(rejections.binding_resolver_missing_credential_lease),
      missing_manifest_fail_closed?:
        match?(
          {:error, {:connector_manifest_missing, _}},
          rejections.manifest_lookup_missing_connector
        ),
      missing_component_fail_closed?:
        match?(
          {:error, {:missing_required_components, [_ | _]}},
          rejections.missing_required_component
        )
    }
  end

  def operation_context do
    struct!(
      OperationContext,
      operation_context_ref: "operation-context://toy-document-review/1",
      actor_ref: "actor://toy-document-review/operator",
      tenant_ref: "tenant://tenant-toy-document-review",
      installation_ref: "installation://toy-document-review/local",
      trace_ref: "trace://toy-document-review/foundation",
      request_ref: "request://toy-document-review/foundation",
      idempotency_key: "toy-document-review-foundation",
      metadata: %{}
    )
  end

  defp compile_pack(pack_manifest) do
    MezzaninePackCompiler.compile(pack_manifest,
      manifest_resolver: &LocalHttpConnector.resolve_operation/1
    )
  end

  defp activate_registry(compiled_pack, opts) do
    tenant_id = Keyword.get_lazy(opts, :tenant_id, &unique_tenant_id/0)

    registration =
      case PackRegistration.by_slug_version(compiled_pack.pack_slug, compiled_pack.version) do
        {:ok, %PackRegistration{} = registration} ->
          registration

        {:error, _reason} ->
          MezzanineConfigRegistry.register_pack!(compiled_pack)
      end

    with {:ok, installation} <-
           MezzanineConfigRegistry.create_installation(%{
             tenant_id: tenant_id,
             environment: "test",
             pack_registration_id: registration.id
           }),
         {:ok, active_installation} <- MezzanineConfigRegistry.activate_installation(installation),
         {:ok, %ActiveBindingSet{} = active} <-
           MezzanineConfigRegistry.active_binding_set(
             active_installation.tenant_id,
             active_installation.environment,
             active_installation.pack_slug
           ) do
      {:ok,
       %{
         installation: active_installation,
         active_binding_set: active,
         compiled_pack: compiled_pack
       }}
    end
  end

  defp unique_tenant_id do
    "tenant-toy-document-review-#{unique_suffix()}"
  end

  defp unique_pack_version do
    "1.0.1-acceptance-#{unique_suffix()}"
  end

  defp unique_suffix do
    "#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive])}"
  end

  defp resolve_operations(service, registry, manifest_entry, opts) do
    ProductHost.operation_bindings()
    |> Enum.reduce_while({:ok, []}, fn {operation_key, binding}, {:ok, acc} ->
      case resolve_operation(operation_key, binding, service, registry, manifest_entry, opts) do
        {:ok, proof} -> {:cont, {:ok, [proof | acc]}}
        {:error, reason} -> {:halt, {:error, {operation_key, reason}}}
      end
    end)
    |> case do
      {:ok, proofs} -> {:ok, Enum.reverse(proofs)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_operation(operation_key, binding, service, registry, manifest_entry, opts) do
    active = registry.active_binding_set
    installation = registry.installation

    with {:ok, resolution} <-
           MezzanineConfigRegistry.resolve_active_binding(
             tenant_id: installation.tenant_id,
             environment: installation.environment,
             pack_slug: installation.pack_slug,
             binding_ref: binding.binding_ref,
             binding_kind: binding.binding_kind,
             expected_binding_epoch: active.binding_epoch
           ),
         {:ok, %RunBindingSnapshot{} = snapshot} <-
           MezzanineConfigRegistry.capture_run_binding_snapshot(
             tenant_id: installation.tenant_id,
             environment: installation.environment,
             pack_slug: installation.pack_slug,
             run_ref: "run://toy-document-review/#{operation_key}",
             binding_ref: binding.binding_ref,
             binding_kind: binding.binding_kind,
             expected_binding_epoch: active.binding_epoch
           ),
         {:ok, descriptor} <-
           resolve_descriptor(resolution, binding, manifest_entry, registry.compiled_pack.version),
         {:ok, authority} <- authorize_descriptor(descriptor, binding, installation),
         {:ok, lease} <- materialize_lease(descriptor, binding, installation),
         {:ok, %ResolvedOperationPlan{} = plan} <-
           BindingResolver.resolve_plan(operation_context(), operation_request(operation_key),
             operation_role: binding.operation_role,
             binding_resolution: resolution,
             operation_descriptor: descriptor,
             expected_binding_epoch: active.binding_epoch,
             authority_decision_ref: authority_ref(authority),
             credential_lease_ref: lease.credential_lease_ref,
             confirmation_policy_ref: confirmation_policy_ref(binding),
             operation_plan_ref: "operation-plan://toy-document-review/#{operation_key}"
           ),
         {:ok, mezzanine_envelope} <-
           BindingResolver.build_envelope(operation_context(), plan, payload(operation_key),
             invocation_ref: "invocation://toy-document-review/#{operation_key}",
             metadata: %{component: "mezzanine_to_jido"}
           ),
         {:ok, lower_envelope} <- lower_envelope(mezzanine_envelope, descriptor, authority),
         {:ok, instruction} <- execution_instruction(mezzanine_envelope, descriptor),
         {:ok, lower_receipt} <-
           LocalHttpConnector.invoke(service, lower_envelope, payload(operation_key),
             credential_lease_ref: lease.credential_lease_ref,
             lease_expires_at: lease.expires_at
           ),
         {:ok, receipt} <-
           operation_receipt(
             operation_key,
             binding,
             descriptor,
             plan,
             mezzanine_envelope,
             lower_receipt,
             opts
           ) do
      {:ok,
       %{
         operation_key: operation_key,
         binding_ref: binding.binding_ref,
         binding_kind: binding.binding_kind,
         operation_ref: plan.operation_ref,
         manifest_ref: plan.manifest_ref,
         registry_epoch: active.binding_epoch,
         snapshot_ref: snapshot.snapshot_ref,
         jido_manifest_lookup_used?: true,
         citadel_authority_used?: authority.result == :allowed,
         credential_lease_used?: lease.raw_material_present? == false,
         binding_resolver_used?: true,
         lower_invocation_used?: instruction.operation_ref == plan.operation_ref,
         lower_receipt_ref: lower_receipt.lower_receipt_ref,
         receipt_ref: receipt.receipt_ref,
         receipt_status: receipt.status,
         operation_receipt: receipt
       }}
    end
  end

  defp resolve_descriptor(resolution, binding, manifest_entry, pack_version) do
    dependency = dependency_for_role(resolution, binding.operation_role)

    LocalHttpConnector.resolve_operation(%{
      connector_ref: resolution.descriptor.connector_ref,
      manifest_ref: resolution.descriptor.manifest_ref,
      operation_ref: dependency.operation_ref,
      operation_role: connector_operation_role(binding.binding_kind),
      operation_class: dependency.operation_class,
      binding_kind: binding.binding_kind,
      required_runtime_family: dependency.required_runtime_family || :direct,
      binding_ref: binding.binding_ref,
      pack_ref: Pack.pack_slug(),
      pack_revision: pack_version,
      credential_scope_ref: dependency.credential_scope_ref,
      compiled_manifest_hash: manifest_entry.manifest_digest
    })
  end

  defp connector_operation_role(:source), do: :source_read
  defp connector_operation_role(:source_publication), do: :source_publish
  defp connector_operation_role(:runtime), do: :runtime_session
  defp connector_operation_role(:runtime_tool), do: :runtime_tool
  defp connector_operation_role(:evidence), do: :evidence_collection
  defp connector_operation_role(:resource_effect), do: :resource_effect

  defp authorize_descriptor(descriptor, binding, installation) do
    Authority.authorize_resolved_plan(
      %{
        actor_ref: "actor://toy-document-review/operator",
        tenant_ref: "tenant://#{installation.tenant_id}",
        installation_ref: "installation://#{installation.id}",
        operation_class: descriptor.operation_class,
        capability: binding.capability,
        manifest_ref: descriptor.manifest_ref,
        operation_ref: descriptor.operation_ref,
        binding_ref: binding.binding_ref,
        credential_scope_ref: descriptor.credential_scope_ref,
        side_effect_class: Atom.to_string(descriptor.side_effect_class),
        required_scopes: descriptor.required_scopes,
        confirmation_policy_ref: confirmation_policy_ref(binding),
        trace_ref: operation_context().trace_ref,
        metadata: %{product: "toy_document_review"}
      },
      allowed_operation_classes: [binding.operation_class],
      allowed_capabilities: [binding.capability],
      allowed_manifest_refs: [descriptor.manifest_ref],
      allowed_binding_refs: [binding.binding_ref],
      allowed_credential_scope_refs: [descriptor.credential_scope_ref],
      allowed_side_effect_classes: [Atom.to_string(descriptor.side_effect_class)],
      allowed_required_scopes: descriptor.required_scopes,
      confirmation_required_operation_classes: [:source_write, :resource_effect]
    )
  end

  defp materialize_lease(descriptor, binding, installation) do
    now = ~U[2026-05-17 00:01:00Z]

    CredentialLease.materialize(
      binding.binding_kind,
      %{
        tenant_ref: "tenant://#{installation.tenant_id}",
        installation_ref: "installation://#{installation.id}",
        binding_ref: binding.binding_ref,
        credential_scope_ref: descriptor.credential_scope_ref,
        connector_binding_ref: "connector-binding://toy-document-review/local-http",
        credential_handle_ref: "credential-handle://toy-document-review/local-http",
        credential_lease_ref: LocalHttpService.default_lease_ref(),
        operation_class: descriptor.operation_class,
        required_scopes: descriptor.required_scopes,
        issued_at: now,
        expires_at: DateTime.add(now, 300, :second),
        metadata: %{connector_ref: descriptor.connector_ref}
      },
      expected_credential_scope_ref: descriptor.credential_scope_ref,
      allowed_required_scopes: descriptor.required_scopes
    )
  end

  defp lower_envelope(mezzanine_envelope, descriptor, authority) do
    GovernedLowerEnvelope.new(%{
      lower_request_ref: "lower-request://#{mezzanine_envelope.invocation_ref}",
      lower_runtime_kind: :direct_connector,
      runtime_profile_ref: "runtime-profile://toy-document-review/local-http",
      runtime_profile_kind: :process,
      capability_id: descriptor.operation_ref,
      tenant_ref: mezzanine_envelope.tenant_ref,
      subject_ref: "subject://toy-document-review/doc-001",
      run_ref: "run://toy-document-review/#{descriptor.operation_ref}",
      trace_id: mezzanine_envelope.trace_ref,
      idempotency_key: mezzanine_envelope.idempotency_key,
      authority_ref: authority_ref(authority),
      authority_decision_hash: authority_hash(authority),
      allowed_operations: [descriptor.operation_ref],
      connector_ref: descriptor.connector_ref,
      connector_manifest_ref: descriptor.manifest_ref,
      connector_manifest_hash: descriptor.manifest_digest,
      connector_manifest_state: :active,
      side_effect_class: descriptor.side_effect_class,
      idempotency_class: :idempotent,
      runtime_class: descriptor.runtime_family,
      declared_actions: [descriptor.operation_ref],
      package_refs: ["stack_lab/examples/toy_document_review"],
      resource_scope_refs: descriptor.required_scopes,
      sandbox_level: :strict,
      input_ref: "input://toy-document-review/#{descriptor.operation_ref}",
      input_hash: "sha256:toy-document-review-input",
      extensions: %{"operation_ref" => descriptor.operation_ref}
    })
  end

  defp execution_instruction(mezzanine_envelope, descriptor) do
    ExecutionInstruction.new(%{
      instruction_ref: "instruction://#{mezzanine_envelope.invocation_ref}",
      invocation_ref: mezzanine_envelope.invocation_ref,
      operation_context_ref: mezzanine_envelope.operation_context_ref,
      execution_target_ref: "execution-target://toy-document-review/local-http",
      operation_ref: descriptor.operation_ref,
      payload: mezzanine_envelope.payload,
      retry_policy_ref: "retry://toy-document-review/local-http",
      metadata: %{connector_ref: descriptor.connector_ref}
    })
  end

  defp operation_receipt(
         operation_key,
         binding,
         descriptor,
         plan,
         mezzanine_envelope,
         lower_receipt,
         _opts
       ) do
    {:ok, payload_envelope} =
      PayloadEnvelope.new(%{
        payload_ref: "payload://toy-document-review/#{operation_key}",
        storage_mode: :inline,
        schema_ref: descriptor.input_schema_ref,
        redaction_ref: "redaction://toy-document-review/input/ref-only",
        data: mezzanine_envelope.payload,
        retention_refs: ["retention://toy-document-review/proof"]
      })

    {:ok, result} =
      ResultEnvelope.new(%{
        result_ref: "result://toy-document-review/#{operation_key}",
        storage_mode: :inline,
        schema_ref: descriptor.output_schema_ref,
        redaction_ref: "redaction://toy-document-review/result/ref-only",
        data: redacted_result_data(lower_receipt),
        retention_refs: ["retention://toy-document-review/proof"]
      })

    OperationReceipt.new(%{
      receipt_ref: "receipt://toy-document-review/#{plan.operation_ref}",
      operation_context_ref: plan.operation_context_ref,
      operation_plan_ref: plan.operation_plan_ref,
      trace_ref: operation_context().trace_ref,
      status: receipt_status(lower_receipt.status),
      started_at: ~U[2026-05-17 00:01:00Z],
      completed_at: ~U[2026-05-17 00:01:30Z],
      result: result,
      lineage_event_refs: ["lineage://toy-document-review/#{plan.operation_ref}"],
      metadata: %{
        path: "generic",
        operation_role: projection_role(binding.binding_kind),
        operation_class: binding.operation_class,
        subject_ref: lower_receipt.subject_ref,
        connector_manifest_ref: lower_receipt.connector_manifest_ref,
        credential_lease_ref: LocalHttpService.default_lease_ref(),
        effect_request_ref: lower_receipt.lower_request_ref,
        evidence_ref: evidence_ref(binding, lower_receipt),
        payload_envelope: payload_envelope,
        provider_object_refs: provider_object_refs(operation_key, lower_receipt),
        provider_facts: provider_facts(operation_key, descriptor, lower_receipt),
        extensions: %{
          "toy_document_review.operation" => Atom.to_string(operation_key),
          "toy_document_review.lower_receipt_ref" => lower_receipt.lower_receipt_ref
        }
      }
    })
  end

  defp redacted_result_data(lower_receipt) do
    %{
      lower_receipt_ref: lower_receipt.lower_receipt_ref,
      lower_request_ref: lower_receipt.lower_request_ref,
      status: lower_receipt.status,
      artifact_refs: lower_receipt.artifact_refs,
      observed_at: lower_receipt.observed_at
    }
  end

  defp provider_object_refs(operation_key, lower_receipt) do
    %{
      "local_http_fixture" => [
        "provider-object://toy-document-review/#{operation_key}",
        lower_receipt.lower_receipt_ref
      ]
    }
  end

  defp provider_facts(operation_key, descriptor, lower_receipt) do
    [
      %{
        fact_ref: "provider-fact://toy-document-review/#{operation_key}",
        fact_kind: :local_http_lower_receipt,
        operation_ref: descriptor.operation_ref,
        connector_manifest_ref: lower_receipt.connector_manifest_ref,
        lower_receipt_ref: lower_receipt.lower_receipt_ref
      }
    ]
  end

  defp evidence_ref(%{binding_kind: :evidence}, lower_receipt) do
    case lower_receipt.artifact_refs do
      [artifact_ref | _rest] -> artifact_ref
      [] -> lower_receipt.lower_receipt_ref
    end
  end

  defp evidence_ref(_binding, _lower_receipt), do: nil

  defp projection_role(:source), do: :source
  defp projection_role(:source_publication), do: :publication
  defp projection_role(:runtime), do: :runtime
  defp projection_role(:runtime_tool), do: :tool
  defp projection_role(:evidence), do: :evidence
  defp projection_role(:resource_effect), do: :resource_effect

  defp operation_request(operation_key) do
    binding = Keyword.fetch!(ProductHost.operation_bindings(), operation_key)

    struct!(
      OperationRequest,
      operation_request_ref: "operation-request://toy-document-review/#{operation_key}",
      operation_context_ref: operation_context().operation_context_ref,
      operation_role_ref: binding.operation_role,
      operation_class: binding.operation_class,
      payload: payload(operation_key),
      authority_packet_ref: "authority-packet://toy-document-review/#{operation_key}",
      state: :requested,
      metadata: %{}
    )
  end

  defp payload(_operation_key), do: %{document_id: "doc-001"}

  defp dependency_for_role(resolution, operation_role) do
    Enum.find(resolution.manifest_dependencies, &(&1.operation_role == operation_role))
  end

  defp confirmation_policy_ref(%{operation_class: operation_class})
       when operation_class in [:source_write, :resource_effect],
       do: "confirmation-policy://toy-document-review/write"

  defp confirmation_policy_ref(_binding), do: "confirmation-policy://toy-document-review/read"

  defp authority_ref(authority), do: "authority://toy-document-review/#{authority.operation_ref}"
  defp authority_hash(authority), do: "sha256:#{authority.result}:#{authority.operation_ref}"

  defp receipt_status(:succeeded), do: :succeeded
  defp receipt_status(:timed_out), do: :timed_out
  defp receipt_status(:denied), do: :denied
  defp receipt_status(_status), do: :failed

  defp registry_summary(%{active_binding_set: active}) do
    %{
      active_binding_epoch: active.binding_epoch,
      binding_set_id: active.binding_set_id
    }
  end

  defp fixture_summary(service) do
    {:ok, page_one} =
      LocalHttpService.request(service, :get, "/events",
        credential_lease_ref: LocalHttpService.default_lease_ref(),
        cursor: 0,
        page_size: 2
      )

    {:ok, page_two} =
      LocalHttpService.request(service, :get, "/events",
        credential_lease_ref: LocalHttpService.default_lease_ref(),
        cursor: 2,
        page_size: 2
      )

    %{
      supervised?: true,
      schema_version: LocalHttpService.schema_version(),
      ordered_event_sequences:
        Enum.map(page_one.body.events ++ page_two.body.events, &Map.fetch!(&1, :sequence))
    }
  end

  defp minimal_resolution do
    %{
      descriptor: %{
        binding_ref: "document_source",
        binding_kind: :source,
        connector_ref: LocalHttpConnector.connector_ref(),
        manifest_ref: LocalHttpConnector.manifest_ref(),
        operation_refs: %{"read" => "toy.documents.read"},
        credential_binding_ref: LocalHttpConnector.credential_scope_ref(),
        binding_epoch: 1
      },
      manifest_dependencies: [
        %{
          operation_role: "read",
          operation_ref: "toy.documents.read",
          operation_class: "source_read",
          binding_ref: "document_source",
          credential_scope_ref: LocalHttpConnector.credential_scope_ref(),
          manifest_digest: LocalHttpConnector.manifest_entry().manifest_digest,
          side_effect_class: "read",
          required_scopes: ["documents:read"]
        }
      ]
    }
  end

  defp minimal_descriptor do
    %{
      connector_ref: LocalHttpConnector.connector_ref(),
      manifest_ref: LocalHttpConnector.manifest_ref(),
      operation_ref: "toy.documents.read",
      operation_class: :source_read,
      adapter_ref: "adapter://toy-document-review/source",
      credential_scope_ref: LocalHttpConnector.credential_scope_ref(),
      side_effect_class: :read,
      input_schema_ref: "schema://toy-document-review/input",
      output_schema_ref: "schema://toy-document-review/output",
      manifest_digest: LocalHttpConnector.manifest_entry().manifest_digest,
      required_scopes: ["documents:read"]
    }
  end

  defp require_components(present, _opts) do
    missing = ProductHost.required_components() -- present

    case missing do
      [] -> :ok
      [_ | _] -> {:error, {:missing_required_components, missing}}
    end
  end

  defp fail_closed?({:error, _reason}), do: true
  defp fail_closed?(_result), do: false
end
