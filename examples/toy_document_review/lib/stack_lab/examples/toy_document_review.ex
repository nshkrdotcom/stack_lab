defmodule StackLab.Examples.ToyDocumentReview do
  @moduledoc """
  Executable neutral product proof for the generic substrate foundation.
  """

  alias Citadel.Authority
  alias Citadel.ConnectorBinding.CredentialLease

  alias AITrace.ReplayEngine
  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Mezzanine.Projections.{LineageEventOutbox, ReceiptReducer, SubjectRuntimeProjection}

  alias Mezzanine.ConfigRegistry.{ActiveBindingSet, RunBindingSnapshot}

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
    ContentShapeGate,
    LocalHttpConnector,
    LocalHttpService,
    OperationGraphGate,
    Pack
  }

  @required_components [
    :pack_compiler,
    :config_registry,
    :jido_manifest_lookup,
    :citadel_authority,
    :credential_lease,
    :binding_resolver,
    :lower_invocation,
    :receipt_creation
  ]

  @phase5_components @required_components ++
                       [
                         :generic_receipt_reduction,
                         :production_projection_mapping,
                         :mezzanine_execution_record_emission,
                         :aitrace_causal_replay
                       ]

  @phase5_replay_event_kinds [
    :command_recorded,
    :workflow_started,
    :operation_requested,
    :jido_manifest_resolved,
    :credential_lease_materialized,
    :effect_requested,
    :effect_receipted,
    :receipt_reduced,
    :evidence_attached,
    :review_opened,
    :projection_updated,
    :replay_exported
  ]

  @stacklab_detailed_event_kinds [
    :operation_requested,
    :effect_requested,
    :effect_receipted,
    :receipt_reduced,
    :projection_updated
  ]

  @extravaganza_required_field_groups %{
    standard_envelope: [
      :ok,
      :schema,
      :operation,
      :trace_id,
      :idempotency_key,
      :runtime_profile_ref,
      :data,
      :refs,
      :warnings,
      :generated_at
    ],
    refs: [
      :subject_ref,
      :run_ref,
      :workflow_ref,
      :runtime_profile_ref,
      :authority_ref,
      :decision_ref,
      :connector_manifest_ref,
      :capability_negotiation_ref,
      :lower_request_ref,
      :lower_receipt_ref,
      :source_publication_ref,
      :evidence_chain_ref,
      :event_page_ref,
      :idempotency_key
    ],
    run_detail_runtime_row: [
      :subject_ref,
      :run_ref,
      :execution_ref,
      :workflow_ref,
      :state,
      :status_reason,
      :updated_at,
      :session_ref,
      :workspace_ref,
      :token_totals
    ],
    provider_request_response: [
      :provider,
      :operation,
      :provider_request_ref,
      :provider_response_ref,
      :provider_request_sent?,
      :provider_response_received?,
      :receipt_recorded?,
      :raw_material_present?
    ],
    lower_receipt: [:lower_receipt_ref, :attempt_ref, :status],
    event_page_entry: [
      :event_ref,
      :event_seq,
      :event_kind,
      :observed_at,
      :run_ref,
      :subject_ref,
      :attempt_ref,
      :extensions
    ]
  }

  @operation_bindings [
    source_read: %{
      binding_ref: "document_source",
      binding_kind: :source,
      operation_role: "read",
      operation_class: :source_read,
      capability: "document_source_read"
    },
    source_publication: %{
      binding_ref: "review_publication",
      binding_kind: :source_publication,
      operation_role: "publish",
      operation_class: :source_write,
      capability: "review_publication"
    },
    runtime: %{
      binding_ref: "review_runtime",
      binding_kind: :runtime,
      operation_role: "run",
      operation_class: :runtime_session,
      capability: "review_runtime"
    },
    runtime_tool: %{
      binding_ref: "review_extract_tool",
      binding_kind: :runtime_tool,
      operation_role: "lookup",
      operation_class: :runtime_tool_invocation,
      capability: "review_extract_tool"
    },
    evidence: %{
      binding_ref: "review_evidence",
      binding_kind: :evidence,
      operation_role: "collect",
      operation_class: :evidence_collection,
      capability: "review_evidence"
    },
    resource_effect: %{
      binding_ref: "archive_effect",
      binding_kind: :resource_effect,
      operation_role: "archive",
      operation_class: :resource_effect,
      capability: "archive_document"
    }
  ]

  def scenario do
    %{
      name: :toy_document_review,
      pack_slug: Pack.pack_slug(),
      deterministic_command: "mix test",
      live_profiles: [],
      cases: %{
        foundation_path: %{kind: :deterministic_foundation},
        content_shape_gate: %{kind: :deterministic_content_shape_gate},
        operation_graph_gate: %{kind: :deterministic_operation_graph_gate},
        receipt_projection_replay: %{kind: :deterministic_receipt_projection_replay},
        fixture_faults: %{kind: :local_http_fault_matrix},
        bypass_rejections: %{kind: :required_component_rejections}
      }
    }
  end

  def required_components, do: @required_components

  def run_content_shape_gate, do: ContentShapeGate.run()

  def run_operation_graph_gate, do: OperationGraphGate.run()

  def run_foundation_proof(opts \\ []) when is_list(opts) do
    service = Keyword.fetch!(opts, :service)
    manifest_entry = LocalHttpConnector.manifest_entry()
    pack_manifest = Pack.manifest(manifest_entry.manifest_digest)

    with {:ok, compiled_pack} <- compile_pack(pack_manifest),
         {:ok, registry} <- activate_registry(compiled_pack, opts),
         {:ok, operations} <- resolve_operations(service, registry, manifest_entry, opts) do
      {:ok,
       %{
         scenario: scenario(),
         pack: %{
           compiled?: true,
           pack_slug: compiled_pack.pack_slug,
           version: compiled_pack.version,
           binding_count: map_size(compiled_pack.bindings_by_ref)
         },
         registry: registry_summary(registry),
         operations: operations,
         local_http_fixture: fixture_summary(service),
         component_path: @required_components
       }}
    end
  end

  def receipt_projection_replay_preflight do
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
      required_path: @phase5_components
    }
  end

  def run_receipt_projection_replay_proof(opts \\ []) when is_list(opts) do
    preflight = receipt_projection_replay_preflight()

    with :ok <- preflight_accepted(preflight),
         {:ok, foundation} <- run_foundation_proof(opts),
         {:ok, reduced} <- reduce_foundation_receipts(foundation),
         replay_events <- stacklab_replay_events(reduced.lineage_events),
         {:ok, replay} <- replay_stacklab_events(replay_events) do
      {:ok,
       %{
         scenario: scenario(),
         preflight: preflight,
         component_path: @phase5_components,
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

  def fault_matrix(service) do
    now = ~U[2026-05-17 00:01:00Z]
    expired_at = ~U[2026-05-17 00:00:00Z]
    refreshed_lease = "credential-lease://toy-document-review/local-http/refreshed"

    {:ok, _refresh} = LocalHttpService.refresh_lease(service, refreshed_lease)

    base = [
      credential_lease_ref: refreshed_lease,
      schema_version: LocalHttpService.schema_version(),
      now: now
    ]

    %{
      retryable_failure:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          Keyword.put(base, :failure_mode, :retryable)
        ),
      terminal_failure:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          Keyword.put(base, :failure_mode, :terminal)
        ),
      auth_rejection:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          Keyword.put(base, :credential_lease_ref, "credential-lease://wrong")
        ),
      credential_expiry:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          base
          |> Keyword.put(:lease_expires_at, expired_at)
          |> Keyword.put(:now, now)
        ),
      schema_mismatch:
        LocalHttpService.request(
          service,
          :get,
          "/documents",
          Keyword.put(base, :schema_version, "toy-document-review.v0")
        ),
      timeout:
        LocalHttpService.request(service, :get, "/documents", Keyword.put(base, :timeout_ms, 1)),
      ordered_page_one:
        LocalHttpService.request(service, :get, "/events", base ++ [cursor: 0, page_size: 2]),
      ordered_page_two:
        LocalHttpService.request(service, :get, "/events", base ++ [cursor: 2, page_size: 2])
    }
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
          operation_role: :read,
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

  defp compile_pack(pack_manifest) do
    MezzaninePackCompiler.compile(pack_manifest,
      manifest_resolver: &LocalHttpConnector.resolve_operation/1
    )
  end

  defp activate_registry(compiled_pack, opts) do
    tenant_id = Keyword.get(opts, :tenant_id, "tenant-toy-document-review")

    registration = MezzanineConfigRegistry.register_pack!(compiled_pack)

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

  defp resolve_operations(service, registry, manifest_entry, opts) do
    @operation_bindings
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
         {:ok, descriptor} <- resolve_descriptor(resolution, binding, manifest_entry),
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

  defp resolve_descriptor(resolution, binding, manifest_entry) do
    dependency = dependency_for_role(resolution, binding.operation_role)

    LocalHttpConnector.resolve_operation(%{
      connector_ref: resolution.descriptor.connector_ref,
      manifest_ref: resolution.descriptor.manifest_ref,
      operation_ref: dependency.operation_ref,
      operation_role: dependency.operation_role,
      operation_class: dependency.operation_class,
      binding_kind: binding.binding_kind,
      required_runtime_family: dependency.required_runtime_family || :direct,
      binding_ref: binding.binding_ref,
      pack_ref: Pack.pack_slug(),
      pack_revision: Pack.version(),
      credential_scope_ref: dependency.credential_scope_ref,
      compiled_manifest_hash: manifest_entry.manifest_digest
    })
  end

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

  defp preflight_accepted(%{accepted?: true}), do: :ok

  defp preflight_accepted(%{blocked_components: blocked}),
    do: {:error, {:blocked_phase5_proof, blocked}}

  defp reduce_foundation_receipts(%{operations: operations}) do
    receipts = Enum.map(operations, &Map.fetch!(&1, :operation_receipt))

    ReceiptReducer.reduce(receipts,
      operation_context_ref: operation_context().operation_context_ref,
      subject_ref: "subject://toy-document-review/doc-001",
      lineage_event_contract: :full_execution,
      review_state: :opened
    )
  end

  defp replay_stacklab_events(events) do
    ReplayEngine.replay_lineage_events(events,
      trace_profile: :stacklab_proof,
      required_event_kinds: @phase5_replay_event_kinds
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

  defp trace_level_for_event(event_kind) when event_kind in @stacklab_detailed_event_kinds,
    do: :detailed_proof

  defp trace_level_for_event(:replay_exported), do: :replay_minimum
  defp trace_level_for_event(_event_kind), do: :core_lineage

  defp trace_metadata_refs(event) do
    %{
      retention_policy_ref: "retention://stacklab/toy-document-review/phase5",
      ttl_seconds: 86_400,
      emission_mode: :inline,
      emission_expectation_ref: "trace-expectation://toy-document-review/#{event.event_kind}"
    }
  end

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
      extravaganza_required_field_groups: @extravaganza_required_field_groups,
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

  defp module_function_exported?(module, function, arity) do
    Code.ensure_loaded?(module) and function_exported?(module, function, arity)
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(nil), do: false
  defp present?(_value), do: true

  defp operation_context do
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

  defp operation_request(operation_key) do
    binding = Keyword.fetch!(@operation_bindings, operation_key)

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
    missing = @required_components -- present

    case missing do
      [] -> :ok
      [_ | _] -> {:error, {:missing_required_components, missing}}
    end
  end
end
