defmodule StackLab.Examples.ToyDocumentReview do
  @moduledoc """
  Executable neutral product proof for the generic substrate foundation.
  """

  alias AITrace.ReplayEngine
  alias AppKit.Core.{ActorRef, Context, InstallationRef, TenantRef}
  alias AppKit.{Evidence, Reviews, RuntimeGateway, Sources, Traces}
  alias Citadel.Authority
  alias Citadel.ConnectorBinding.CredentialLease
  alias ExecutionPlane.Contracts.ExecutionIntentEnvelope.V1, as: ExecutionIntentEnvelope
  alias ExecutionPlane.Contracts.ExecutionRoute.V1, as: ExecutionRoute
  alias ExecutionPlane.Contracts.HttpExecutionIntent.V1, as: HttpExecutionIntent
  alias ExecutionPlane.Contracts.NoEgressPolicy.V1, as: NoEgressPolicy
  alias ExecutionPlane.Kernel, as: ExecutionKernel
  alias Jido.Integration.V2.GovernedLowerEnvelope
  alias Mezzanine.Projections.{LineageEventOutbox, ReceiptReducer, SubjectRuntimeProjection}

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
    ContentShapeGate,
    ContentStoreAcceptance,
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

  @full_acceptance_components [
    :appkit_role_ref_boundary,
    :pack_compiler,
    :config_registry,
    :jido_manifest_lookup,
    :citadel_authority,
    :credential_lease,
    :binding_resolver,
    :lower_invocation,
    :execution_plane_dispatch_plan,
    :receipt_creation,
    :generic_receipt_reduction,
    :production_projection_mapping,
    :mezzanine_execution_record_emission,
    :aitrace_causal_replay,
    :aitrace_full_replay_gate
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

  @forbidden_neutral_terms [
    "Extra" <> "vaganza",
    "Lin" <> "ear",
    "Git" <> "Hub",
    "Co" <> "dex",
    "Sym" <> "phony"
  ]

  defmodule RoleRefBackend do
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

  def scenario do
    %{
      name: :toy_document_review,
      pack_slug: Pack.pack_slug(),
      deterministic_command: "mix stack_lab.proof_app.toy_document_review.acceptance --json",
      live_profiles: [],
      cases: %{
        full_neutral_acceptance: %{kind: :deterministic_full_acceptance},
        foundation_path: %{kind: :deterministic_foundation},
        content_shape_gate: %{kind: :deterministic_content_shape_gate},
        content_store_acceptance: %{kind: :deterministic_content_store_acceptance},
        operation_graph_gate: %{kind: :deterministic_operation_graph_gate},
        receipt_projection_replay: %{kind: :deterministic_receipt_projection_replay},
        fixture_faults: %{kind: :local_http_fault_matrix},
        bypass_rejections: %{kind: :required_component_rejections}
      }
    }
  end

  def required_components, do: @required_components

  def full_acceptance_components, do: @full_acceptance_components

  def source_inputs do
    [
      %{
        input_kind: :uploaded_document_source,
        source_ref: "upload://toy-document-review/doc-001",
        subject_ref: "subject://toy-document-review/doc-001",
        external_state: "submitted",
        payload_ref: "payload://toy-document-review/uploaded-document/doc-001"
      },
      %{
        input_kind: :event_style_review_update,
        source_ref: "event://toy-document-review/3",
        subject_ref: "subject://toy-document-review/doc-001",
        external_state: "review.completed",
        payload_ref: "payload://toy-document-review/event/review-completed/doc-001"
      }
    ]
  end

  def state_mapping do
    %{
      "submitted" => %{source_state: :open, workflow_state: :submitted},
      "review.started" => %{source_state: :active, workflow_state: :reviewing},
      "review.completed" => %{source_state: :terminal, workflow_state: :reviewed},
      "archived" => %{source_state: :terminal, workflow_state: :archived},
      "expired" => %{source_state: :terminal, workflow_state: :expired}
    }
  end

  def run_content_shape_gate, do: ContentShapeGate.run()

  def run_content_store_acceptance, do: ContentStoreAcceptance.run()

  def run_operation_graph_gate, do: OperationGraphGate.run()

  def run_full_acceptance(opts \\ []) when is_list(opts) do
    service = Keyword.fetch!(opts, :service)
    content_shape = run_content_shape_gate()
    content_store = run_content_store_acceptance()
    faults = fault_matrix(service)
    bypass = bypass_rejections()

    with {:ok, graph} <- run_operation_graph_gate(),
         {:ok, appkit} <- appkit_role_ref_probe(),
         {:ok, execution_plane} <- execution_plane_probe(),
         {:ok, foundation} <- run_foundation_proof(opts),
         {:ok, receipt_replay} <- run_receipt_projection_replay_proof(opts),
         {:ok, gate3} <- run_full_gate3_proof(opts) do
      {:ok,
       %{
         scenario: scenario(),
         accepted?: true,
         component_path: @full_acceptance_components,
         source_inputs: source_inputs(),
         state_mapping: state_mapping(),
         appkit_role_ref_boundary: appkit,
         foundation: foundation_summary(foundation),
         content_shape_gate: content_shape.acceptance,
         content_store_acceptance: content_store.content_store_contract,
         operation_graph_gate: graph_summary(graph),
         fault_matrix: fault_matrix_summary(faults),
         bypass_rejections: bypass_summary(bypass),
         receipt_projection_replay: receipt_projection_summary(receipt_replay),
         full_gate3: gate3,
         execution_plane: execution_plane,
         neutral_code_scan: neutral_code_scan(),
         live_profiles: [],
         live_acceptance: %{
           required?: false,
           reason: :no_live_github_or_linear_profile_for_neutral_proof_app
         }
       }}
    end
  end

  def run_foundation_proof(opts \\ []) when is_list(opts) do
    service = Keyword.fetch!(opts, :service)
    manifest_entry = LocalHttpConnector.manifest_entry()
    pack_manifest = Pack.manifest(manifest_entry.manifest_digest, unique_pack_version())

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
    with {:ok, evidence} <- replay_evidence(opts) do
      preflight = evidence.preflight
      foundation = evidence.foundation
      reduced = evidence.reduced
      replay_events = evidence.replay_events
      replay = evidence.replay

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

  def run_full_gate3_proof(opts \\ []) when is_list(opts) do
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

    matrix = %{
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

    {:ok, _restore} =
      LocalHttpService.refresh_lease(service, LocalHttpService.default_lease_ref())

    matrix
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

  def appkit_role_ref_probe do
    opts = [generic_backend: RoleRefBackend]

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

  def execution_plane_probe do
    route = execution_route()
    intent = http_intent()

    case ExecutionKernel.build_dispatch(intent, route) do
      {:ok, plan} ->
        {:ok,
         %{
           accepted?: true,
           route_id: plan.route_id,
           family: plan.family,
           protocol: plan.protocol,
           timeout_ms: plan.timeout_ms,
           lower_simulation_configured?:
             not is_nil(plan.route.resolved_target["lower_simulation"])
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def neutral_code_scan do
    files =
      __ENV__.file
      |> Path.dirname()
      |> Path.join("**/*.{ex,exs}")
      |> Path.wildcard()
      |> Enum.reject(&generated_path?/1)

    findings =
      files
      |> Enum.flat_map(fn path ->
        body = File.read!(path)

        @forbidden_neutral_terms
        |> Enum.filter(&String.contains?(body, &1))
        |> Enum.map(&%{path: path, term: &1})
      end)

    %{
      accepted?: findings == [],
      scanned_file_count: length(files),
      forbidden_terms: @forbidden_neutral_terms,
      findings: findings
    }
  end

  defp replay_evidence(opts) do
    preflight = receipt_projection_replay_preflight()

    with :ok <- preflight_accepted(preflight),
         {:ok, foundation} <- run_foundation_proof(opts),
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

  defp execution_route do
    ExecutionRoute.new!(%{
      route_id: "route-toy-document-review-http",
      family: "http",
      protocol: "http",
      transport_family: "http",
      placement_family: "local",
      resolved_target: %{
        "target_id" => "toy-document-review-local-http",
        "method" => "post",
        "url" => "http://127.0.0.1/toy-document-review",
        "lower_simulation" => %{
          "scenario_ref" => "lower-simulation://toy-document-review/http",
          "status" => "succeeded",
          "side_effect_policy" => "deny_external_egress",
          "raw_payload" => %{"status" => "simulated"},
          "no_egress_policy" =>
            NoEgressPolicy.dump(NoEgressPolicy.default_lower_boundary_policy!())
        }
      },
      resolved_budget: %{"timeout_ms" => 5_000},
      lineage: execution_lineage("route-toy-document-review-http")
    })
  end

  defp http_intent do
    HttpExecutionIntent.new!(%{
      envelope:
        ExecutionIntentEnvelope.new!(%{
          intent_id: "intent-toy-document-review-http",
          family: "http",
          protocol: "http",
          trace_id: "trace://toy-document-review/execution-plane",
          idempotency_key: "toy-document-review-execution-plane",
          boundary_session_id: "boundary-session-toy-document-review",
          decision_id: "decision-toy-document-review",
          lease_ref: LocalHttpService.default_lease_ref(),
          target_ref: "target://toy-document-review/local-http",
          attach_grant_ref: "attach-grant://toy-document-review/local-http",
          target_auth_posture_ref: "target-posture://toy-document-review/local-http",
          workspace_ref: "workspace://toy-document-review/local",
          no_egress_posture_ref: "no-egress-posture://toy-document-review/local-http",
          credential_handle_refs: ["credential-handle://toy-document-review/local-http"],
          attempt_ref: "attempt://toy-document-review/execution-plane",
          requested_capabilities: ["http.unary"],
          extensions: %{proof_app: "toy_document_review"}
        }),
      request_shape: "request_response",
      stream_mode: "unary",
      headers: %{"accept" => "application/json"},
      body: %{"document_id" => "doc-001"},
      egress_surface: %{"surface_kind" => "local_http_fixture"},
      timeouts: %{"request_timeout_ms" => 5_000},
      retry_class: "safe_idempotent"
    })
  end

  defp execution_lineage(route_id) do
    %{
      tenant_id: "tenant-toy-document-review",
      trace_id: "trace://toy-document-review/execution-plane",
      request_id: "request-toy-document-review-execution-plane",
      decision_id: "decision-toy-document-review",
      boundary_session_id: "boundary-session-toy-document-review",
      attempt_ref: "attempt://toy-document-review/execution-plane",
      route_id: route_id,
      idempotency_key: "toy-document-review-execution-plane"
    }
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
    Enum.any?(@operation_bindings, fn {_key, binding} -> binding.binding_ref == role_ref end)
  end

  defp generated_path?(path) do
    parts = Path.split(path)
    "_build" in parts or "deps" in parts or "doc" in parts
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
      operation_role: dependency.operation_role,
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

  defp foundation_summary(proof) do
    %{
      pack: proof.pack,
      registry: proof.registry,
      operation_count: length(proof.operations),
      component_path: proof.component_path,
      local_http_fixture: proof.local_http_fixture
    }
  end

  defp graph_summary(proof) do
    %{
      graph: proof.graph,
      initial_ready_node_refs: proof.initial_ready_node_refs,
      alternate_completion_orders: proof.alternate_completion_orders,
      concurrent_runtime_evidence_branch: proof.concurrent_runtime_evidence_branch
    }
  end

  defp fault_matrix_summary(matrix) do
    %{
      retryable_failure?: fault_reason?(matrix.retryable_failure, :retryable_failure),
      terminal_failure?: fault_reason?(matrix.terminal_failure, :terminal_failure),
      auth_rejection?: fault_reason?(matrix.auth_rejection, :auth_rejected),
      credential_expiry?: fault_reason?(matrix.credential_expiry, :credential_expired),
      schema_mismatch?: fault_reason?(matrix.schema_mismatch, :schema_version_mismatch),
      timeout?: fault_reason?(matrix.timeout, :timeout),
      pagination_ordered?: pagination_ordered?(matrix.ordered_page_one, matrix.ordered_page_two)
    }
  end

  defp fault_reason?({:error, %{reason: reason}}, reason), do: true
  defp fault_reason?(_result, _reason), do: false

  defp pagination_ordered?({:ok, page_one}, {:ok, page_two}) do
    Enum.map(page_one.body.events ++ page_two.body.events, & &1.sequence) == [1, 2, 3]
  end

  defp pagination_ordered?(_page_one, _page_two), do: false

  defp bypass_summary(rejections) do
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

  defp fail_closed?({:error, _reason}), do: true
  defp fail_closed?(_result), do: false

  defp receipt_projection_summary(proof) do
    %{
      projection: proof.projection,
      lower_receipt_summary: proof.lower_receipt_summary,
      lineage: proof.lineage,
      aitrace_replay: proof.aitrace_replay,
      product_shape_comparison: proof.product_shape_comparison
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
