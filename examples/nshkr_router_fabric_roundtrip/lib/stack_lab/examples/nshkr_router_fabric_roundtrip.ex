defmodule StackLab.Examples.NSHKRRouterFabricRoundtrip.Receipt do
  @moduledoc "Deterministic NSHKR router fabric proof receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_refs,
    :status,
    :provider_dependency?,
    :context_packet_ref,
    :context_packet_hash,
    :authority_ref,
    :admission_receipt_ref,
    :route_decision_ref,
    :selected_route_kind,
    :selected_model_profile_ref,
    :trinity_selected_role_ref,
    :prompt_artifact_ref,
    :provider_payload_ref,
    :payload_hash,
    :model_invocation_ref,
    :model_receipt_ref,
    :appkit_projection_refs,
    :scanner_receipts,
    :aitrace_facts,
    :trace_refs,
    :does_not_prove
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.NSHKRRouterFabricRoundtrip do
  @moduledoc """
  Provider-free router fabric proof over the generalized fugu substrate.
  """

  alias AITrace.AIPlatform
  alias AppKit.ContextSurface
  alias Citadel.ContextAuthority
  alias Citadel.ContextAuthority.AuthorityRequest
  alias Jido.Integration.InferenceRuntime
  alias Jido.Integration.InferenceRuntime.FakeInvoker
  alias Jido.Integration.ModelInvocation
  alias Mezzanine.AIExecution
  alias Mezzanine.AIExecution.RuntimeDeps
  alias Mezzanine.ContextPacketEngine
  alias OuterBrain.ContextABI
  alias StackLab.ContextABIScanner
  alias StackLab.CoordinationFabricScanner
  alias StackLab.Examples.NSHKRRouterFabricRoundtrip.Receipt
  alias StackLab.ModelInferenceScanner
  alias StackLab.RouterFabricScanner
  alias Trinity.MezzanineRouterAdapter

  @fixture_refs ["AOC-026", "AOC-036", "AOC-043", "AOC-ROUTER-001"]
  @tenant_ref "tenant://router-fabric/demo"
  @workflow_ref "workflow://router-fabric/demo/run"
  @ai_run_ref "ai-run://router-fabric/demo/run"
  @trace_ref "trace://router-fabric/demo/run"
  @now ~U[2026-05-24 13:00:00Z]

  @spec run(keyword() | map()) :: {:ok, Receipt.t()} | {:error, term()}
  def run(opts \\ []) do
    opts = Map.new(opts)

    with {:ok, product_request} <- ContextSurface.compile_request(product_request_attrs()),
         {:ok, packet, compile_receipt} <-
           ContextABI.compile(context_compile_attrs(product_request)),
         {:ok, grant} <- ContextAuthority.authorize(packet, authority_request(packet), now: @now),
         {:ok, admission_receipt} <- admit_packet(packet, grant),
         route_request = route_request(packet, grant),
         {:ok, route_decision} <- route(route_request),
         {:ok, render_result} <- render(packet, route_decision),
         {:ok, invocation_request} <- model_invocation_request(render_result, route_decision),
         {:ok, %{receipt: model_receipt}} <- invoke_model(invocation_request),
         {:ok, projections} <-
           appkit_projections(packet, admission_receipt, grant, route_decision, model_receipt),
         {:ok, aitrace_facts} <-
           aitrace_facts(packet, grant, route_decision, model_receipt, projections),
         {:ok, scanner_receipts} <-
           scanner_receipts(
             packet,
             compile_receipt,
             grant,
             admission_receipt,
             route_request,
             route_decision,
             render_result,
             model_receipt,
             projections,
             aitrace_facts
           ) do
      {:ok,
       %Receipt{
         receipt_ref: receipt_ref(packet, route_decision),
         fixture_refs: @fixture_refs,
         status: status(scanner_receipts),
         provider_dependency?: Map.get(opts, :provider_dependency?, false),
         context_packet_ref: packet.context_packet_ref,
         context_packet_hash: packet.packet_hash,
         authority_ref: grant.authority_ref,
         admission_receipt_ref: admission_receipt.receipt_ref,
         route_decision_ref: route_decision.route_decision_ref,
         selected_route_kind: route_decision.selected_route_kind,
         selected_model_profile_ref: route_decision.selected_model_profile_ref,
         trinity_selected_role_ref: route_decision.trinity.selected_role_ref,
         prompt_artifact_ref: render_result.prompt_artifact_ref,
         provider_payload_ref: render_result.provider_payload_ref,
         payload_hash: render_result.payload_hash,
         model_invocation_ref: model_receipt.invocation_ref,
         model_receipt_ref: model_receipt.receipt_ref,
         appkit_projection_refs: appkit_projection_refs(projections),
         scanner_receipts: scanner_receipts,
         aitrace_facts: aitrace_facts,
         trace_refs: [@trace_ref, model_receipt.trace_ref],
         does_not_prove: [
           "live provider behavior",
           "distributed BEAM placement",
           "GEPA optimization quality",
           "production persistence",
           "TRINITY learned route quality beyond deterministic adapter wiring"
         ]
       }}
    end
  end

  @spec to_map(Receipt.t()) :: map()
  def to_map(%Receipt{} = receipt), do: json_safe(receipt)

  @spec to_json!(Receipt.t()) :: String.t()
  def to_json!(%Receipt{} = receipt), do: receipt |> to_map() |> Jason.encode!(pretty: true)

  defp product_request_attrs do
    %{
      request_ref: "request://router-fabric/demo/compile",
      tenant_ref: @tenant_ref,
      authority_ref: "authority://router-fabric/demo/requested",
      user_request_ref: "artifact://router-fabric/demo/user-request",
      system_instruction_ref: "artifact://router-fabric/demo/system-instruction",
      memory_refs: ["memory://router-fabric/demo/promoted/a"],
      budget_ref: "budget://router-fabric/demo/run",
      model_class_allowlist: ["model-profile://fixture/worker"],
      route_policy_ref: "route-policy://router-fabric/demo/trinity",
      trace_ref: @trace_ref,
      idempotency_key: "idem://router-fabric/demo/compile",
      redaction_policy_ref: "redaction-policy://router-fabric/demo/refs-only"
    }
  end

  defp context_compile_attrs(product_request) do
    product_request
    |> Map.from_struct()
    |> Map.take([
      :tenant_ref,
      :user_request_ref,
      :system_instruction_ref,
      :memory_refs,
      :budget_ref,
      :model_class_allowlist,
      :route_policy_ref,
      :trace_ref
    ])
  end

  defp authority_request(packet) do
    AuthorityRequest.new!(%{
      tenant_ref: packet.tenant_ref,
      actor_ref: "actor://router-fabric/operator",
      context_packet_ref: packet.context_packet_ref,
      model_class_allowlist: packet.model_class_allowlist,
      route_policy_ref: packet.route_policy_ref,
      trace_ref: packet.trace_ref,
      trust_classes: [:operator_authored, :memory_promoted],
      evidence_refs: ["evidence://router-fabric/policy/default"],
      authority_ref: "authority://router-fabric/demo/grant",
      payload_mode: :refs_only,
      redaction_class: :tenant_sensitive
    })
  end

  defp admit_packet(packet, grant) do
    ContextPacketEngine.admit(
      packet,
      %{
        tenant_ref: packet.tenant_ref,
        workflow_ref: @workflow_ref,
        authority_ref: grant.authority_ref,
        context_packet_ref: packet.context_packet_ref,
        idempotency_key: "idem://router-fabric/demo/admit",
        trace_ref: packet.trace_ref,
        actor_ref: "actor://router-fabric/operator",
        ai_run_ref: @ai_run_ref,
        budget_ref: packet.budget_ref,
        cost_ref: "cost://router-fabric/demo/model",
        eval_ref: "eval://router-fabric/demo/verdict",
        route_decision_ref: "route-decision://router-fabric/demo/pending",
        model_call_ref: "model-invocation://router-fabric/demo/pending",
        projection_ref: "appkit://router-fabric/demo/projection"
      },
      authority_grant: grant,
      budget_decision: :allow,
      now: @now
    )
  end

  defp route_request(packet, grant) do
    %{
      tenant_ref: packet.tenant_ref,
      workflow_ref: @workflow_ref,
      context_packet_ref: packet.context_packet_ref,
      packet_hash: packet.packet_hash,
      authority_ref: grant.authority_ref,
      route_policy_ref: packet.route_policy_ref,
      model_class_allowlist: packet.model_class_allowlist,
      trace_ref: packet.trace_ref
    }
  end

  defp route(route_request) do
    AIExecution.route(
      route_request,
      %RuntimeDeps{router_adapter: MezzanineRouterAdapter},
      trinity_config: trinity_config(),
      preferred_role_ref: "role://router-fabric/worker"
    )
  end

  defp render(packet, route_decision) do
    AIExecution.render_context(packet, route_decision, %RuntimeDeps{},
      workflow_ref: @workflow_ref,
      prompt_tokens: 64,
      payload_mode: :ref_only
    )
  end

  defp model_invocation_request(render_result, route_decision) do
    with {:ok, base_attrs} <-
           AIExecution.invocation_request(render_result, route_decision,
             idempotency_key: "idem://router-fabric/demo/model",
             credential_lease_ref: "credential-lease://router-fabric/demo/fixture"
           ) do
      ModelInvocation.new_request(
        Map.merge(base_attrs, %{
          invocation_ref: "model-invocation://router-fabric/demo/run",
          payload_hash: render_result.payload_hash,
          provider_ref: "provider://fixture",
          endpoint_ref: "endpoint://fixture/chat",
          runtime_ref: "runtime://jido/fake-invoker",
          runtime_kind: :client,
          token_budget_ref: "token-budget://router-fabric/demo/run",
          cost_budget_ref: "cost-budget://router-fabric/demo/run",
          redaction_class: "bounded_receipt",
          payload_mode: "artifact_ref",
          operation: :generate_text,
          stream?: false,
          issued_at: @now,
          metadata: %{"admission_receipt_ref" => "packet-admission://router-fabric/demo"}
        })
      )
    end
  end

  defp invoke_model(invocation_request) do
    _ = Code.ensure_loaded(FakeInvoker)
    InferenceRuntime.invoke(invocation_request, invoker: FakeInvoker)
  end

  defp appkit_projections(packet, admission_receipt, grant, route_decision, model_receipt) do
    with {:ok, packet_projection} <-
           ContextSurface.packet_projection(%{
             context_packet: packet,
             receipt_ref: admission_receipt.receipt_ref,
             admission_status: admission_receipt.status
           }),
         {:ok, route_projection} <-
           ContextSurface.route_decision_projection(%{
             route_decision_ref: route_decision.route_decision_ref,
             context_packet_ref: packet.context_packet_ref,
             route_policy_ref: route_decision.route_policy_ref,
             selected_route_kind: route_decision.selected_route_kind,
             selected_model_profile_ref: route_decision.selected_model_profile_ref,
             provider_or_runtime_ref: route_decision.provider_or_runtime_ref,
             verifier_ref: route_decision.verifier_ref,
             fallback_plan_ref:
               route_decision.fallback_plan_ref || "fallback-plan://router-fabric/none",
             cost_estimate_ref: route_decision.cost_estimate.estimate_ref,
             budget_status_ref: "budget-status://router-fabric/allow",
             authority_ref: grant.authority_ref,
             trace_ref: route_decision.trace_ref,
             reason_codes: route_decision.reason_codes
           }),
         {:ok, model_projection} <-
           ContextSurface.model_invocation_projection(%{
             model_invocation_ref: model_receipt.invocation_ref,
             model_receipt_ref: model_receipt.receipt_ref,
             context_packet_ref: model_receipt.context_packet_ref,
             route_decision_ref: model_receipt.route_decision_ref,
             prompt_artifact_ref: model_receipt.prompt_artifact_ref,
             provider_payload_ref: model_receipt.provider_payload_ref,
             payload_hash: model_receipt.payload_hash,
             model_profile_ref: model_receipt.model_profile_ref,
             endpoint_ref: model_receipt.endpoint_ref,
             provider_ref: model_receipt.provider_ref,
             credential_lease_ref: model_receipt.credential_lease_ref,
             cost_ref: "cost://router-fabric/demo/model",
             trace_ref: model_receipt.trace_ref
           }),
         {:ok, eval_projection} <-
           ContextSurface.eval_verdict_projection(%{
             eval_verdict_ref: "eval-verdict://router-fabric/demo/pass",
             context_packet_ref: packet.context_packet_ref,
             route_decision_ref: route_decision.route_decision_ref,
             model_receipt_ref: model_receipt.receipt_ref,
             verdict: :pass,
             severity_class: "clean",
             decision_evidence_ref: "decision-evidence://router-fabric/demo/eval",
             trace_ref: "trace://router-fabric/demo/eval"
           }) do
      {:ok,
       %{
         packet: packet_projection,
         route: route_projection,
         model: model_projection,
         eval: eval_projection
       }}
    end
  end

  defp aitrace_facts(packet, grant, route_decision, model_receipt, projections) do
    with {:ok, context_span} <-
           AIPlatform.context_packet_compile_span(%{
             tenant_ref: packet.tenant_ref,
             authority_ref: grant.authority_ref,
             trace_ref: packet.trace_ref,
             context_packet_ref: packet.context_packet_ref,
             context_packet_hash: packet.packet_hash
           }),
         {:ok, route_span} <-
           AIPlatform.route_decision_span(%{
             tenant_ref: packet.tenant_ref,
             authority_ref: grant.authority_ref,
             trace_ref: route_decision.trace_ref,
             route_decision_ref: route_decision.route_decision_ref,
             route_policy_ref: route_decision.route_policy_ref
           }),
         {:ok, model_span} <-
           AIPlatform.model_call_span(%{
             tenant_ref: model_receipt.tenant_ref,
             authority_ref: grant.authority_ref,
             trace_ref: model_receipt.trace_ref,
             model_invocation_ref: model_receipt.invocation_ref,
             model_receipt_ref: model_receipt.receipt_ref,
             model_profile_ref: model_receipt.model_profile_ref,
             provider_ref: model_receipt.provider_ref,
             endpoint_ref: model_receipt.endpoint_ref
           }),
         {:ok, eval_event} <-
           AIPlatform.eval_verdict_event(%{
             tenant_ref: packet.tenant_ref,
             trace_ref: projections.eval.trace_ref,
             eval_verdict_ref: projections.eval.eval_verdict_ref,
             eval_case_ref: "eval-case://router-fabric/demo/fixture"
           }) do
      {:ok,
       [
         trace_fact(context_span, packet.trace_ref),
         trace_fact(route_span, route_decision.trace_ref),
         trace_fact(model_span, model_receipt.trace_ref),
         trace_fact(eval_event, projections.eval.trace_ref)
       ]}
    end
  end

  defp scanner_receipts(
         packet,
         compile_receipt,
         grant,
         admission_receipt,
         route_request,
         route_decision,
         render_result,
         model_receipt,
         projections,
         aitrace_facts
       ) do
    with {:ok, context_scan} <-
           ContextABIScanner.scan(%{
             owner_repo: "stack_lab",
             package_path: "examples/nshkr_router_fabric_roundtrip",
             context_packets: [packet],
             context_compile_receipts: [compile_receipt],
             authority_grants: [grant],
             admission_receipts: [admission_receipt],
             route_decisions: [route_decision],
             render_results: [render_result],
             model_invocation_receipts: [model_receipt],
             appkit_projections: Map.values(projections),
             aitrace_facts: aitrace_facts
           }),
         {:ok, router_scan} <-
           RouterFabricScanner.scan(%{
             owner_repo: "stack_lab",
             package_path: "examples/nshkr_router_fabric_roundtrip",
             route_requests: [route_request],
             route_decisions: [route_decision]
           }),
         {:ok, coordination_scan} <-
           CoordinationFabricScanner.scan(coordination_scan_input(route_decision)),
         {:ok, model_scan} <- ModelInferenceScanner.scan(model_scan_input(model_receipt)) do
      {:ok,
       %{
         context_abi: context_scan,
         router_fabric: router_scan,
         coordination_fabric: coordination_scan,
         model_inference: model_scan
       }}
    end
  end

  defp model_scan_input(model_receipt) do
    %{
      owner_repo: "jido_integration",
      package_path: "core/inference_runtime",
      runtime_facts: [
        %{
          model_profile_ref: model_receipt.model_profile_ref,
          endpoint_profile_ref: model_receipt.endpoint_ref,
          endpoint_identity_ref: "endpoint-identity://fixture/chat",
          provider_credential_ref: model_receipt.credential_lease_ref,
          operation_policy_ref: "operation-policy://router-fabric/generate-text"
        }
      ],
      source_units: []
    }
  end

  defp coordination_scan_input(route_decision) do
    %{
      owner_repo: "trinity_framework",
      package_path: "core/trinity_coordinator_core",
      coordination_facts: [
        %{
          router_artifact_refs: [route_decision.trinity.router_artifact_ref],
          router_eval_refs: ["router-eval://router-fabric/golden"],
          calibration_refs: ["calibration://router-fabric/threshold"],
          drift_detection_refs: ["drift://router-fabric/window"],
          parity_check_refs: ["parity://router-fabric/fixture"],
          role_prompt_refs: ["prompt://router-fabric/worker"],
          provider_pool_refs: ["provider-pool://router-fabric/fixture"],
          governed_inference_boundary_ref: "inference-boundary://router-fabric/jido",
          verifier_refs: [route_decision.verifier_ref],
          handoff_scope_ref: "handoff-scope://router-fabric/mezzanine-to-jido",
          trace_refs: [route_decision.trace_ref],
          replay_refs: ["replay://router-fabric/demo"],
          trace_redaction: :redacted
        }
      ]
    }
  end

  defp trinity_config do
    %{
      router_artifact: %{
        router_artifact_ref: "router-artifact://router-fabric/fixture",
        extractor_ref: "extractor://router-fabric/context-packet",
        head_ref: "head://router-fabric/fixture",
        compatibility_ref: "compatibility://router-fabric/mezzanine/v1",
        calibration_ref: "calibration://router-fabric/threshold",
        parity_ref: "parity://router-fabric/fixture",
        hash_ref: "sha256:router"
      },
      role_packs: [
        %{
          role_ref: "role://router-fabric/worker",
          prompt_ref: "prompt://router-fabric/worker",
          capability_refs: ["capability://router-fabric/answer"],
          allowed_model_profile_refs: ["model-profile://fixture/worker"],
          tool_policy_ref: "tool-policy://router-fabric/none",
          memory_profile_ref: "memory-profile://router-fabric/ref-only",
          guardrail_profile_ref: "guardrail-profile://router-fabric/default",
          verifier_profile_ref: "verifier-profile://router-fabric/worker",
          budget_ref: "budget://router-fabric/role/worker",
          context_budget_ref: "context-budget://router-fabric/role/worker",
          handoff_policy_ref: "handoff-policy://router-fabric/worker",
          projection_ref: "projection://router-fabric/worker",
          gepa_target_refs: []
        }
      ],
      provider_pool: [
        %{
          slot_ref: "slot://router-fabric/worker",
          slot_kind: :mock,
          role_refs: ["role://router-fabric/worker"],
          model_profile_ref: "model-profile://fixture/worker",
          endpoint_profile_ref: "endpoint-profile://fixture/worker",
          operation_policy_ref: "operation-policy://router-fabric/worker",
          target_ref: "runtime://fixture/worker",
          credential_ref: "credential://router-fabric/ref-only",
          per_role_constraints: %{}
        }
      ]
    }
  end

  defp appkit_projection_refs(projections) do
    [
      projections.packet.context_packet_ref,
      projections.route.route_decision_ref,
      projections.model.model_receipt_ref,
      projections.eval.eval_verdict_ref
    ]
  end

  defp trace_fact(%{name: name, attributes: attributes}, trace_ref) do
    %{trace_ref: trace_ref, name: name, attributes: attributes}
  end

  defp receipt_ref(packet, route_decision) do
    suffix = packet.packet_hash |> String.replace_prefix("sha256:", "") |> String.slice(0, 16)

    "nshkr-router-fabric-roundtrip://#{suffix}/#{URI.encode_www_form(route_decision.route_decision_ref)}"
  end

  defp status(scanner_receipts) do
    scanner_receipts
    |> Map.values()
    |> Enum.all?(&(&1.status == :pass))
    |> if(do: :pass, else: :open_defect)
  end

  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%_struct{} = value), do: value |> Map.from_struct() |> json_safe()

  defp json_safe(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), json_safe(v)} end)

  defp json_safe(values) when is_list(values), do: Enum.map(values, &json_safe/1)
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value), do: value
end
