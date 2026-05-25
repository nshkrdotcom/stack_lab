defmodule StackLab.Examples.ContextABIRoundtrip.Receipt do
  @moduledoc "Deterministic Context ABI roundtrip receipt."
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
    :render_result_ref,
    :prompt_artifact_ref,
    :provider_payload_ref,
    :payload_hash,
    :model_invocation_ref,
    :model_receipt_ref,
    :eval_verdict_ref,
    :appkit_projection_refs,
    :scanner_receipts,
    :aitrace_facts,
    :trace_refs,
    :does_not_prove
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.ContextABIRoundtrip do
  @moduledoc """
  Provider-free Context ABI platform roundtrip.

  This proof intentionally composes the owner packages added by the fugu
  phases. StackLab owns the proof receipt and scanner evidence, not the
  underlying context, authority, execution, invocation, or projection semantics.
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
  alias StackLab.AIRunLineageScanner
  alias StackLab.ContextABIScanner
  alias StackLab.CostBudgetScanner
  alias StackLab.Examples.ContextABIRoundtrip.Receipt
  alias StackLab.MemoryFabricScanner
  alias StackLab.ModelInferenceScanner
  alias StackLab.TenantIsolationScanner

  @fixture_refs ["AOC-CTX-001", "AOC-CTX-002", "AOC-CTX-003", "AOC-041"]
  @tenant_ref "tenant://context-abi/demo"
  @workflow_ref "workflow://context-abi/demo/run"
  @ai_run_ref "ai-run://context-abi/demo/run"
  @trace_ref "trace://context-abi/demo/run"
  @now ~U[2026-05-24 12:00:00Z]

  @spec run(keyword() | map()) :: {:ok, Receipt.t()} | {:error, term()}
  def run(opts \\ []) do
    opts = Map.new(opts)

    with {:ok, product_request} <- ContextSurface.compile_request(product_request_attrs()),
         {:ok, packet, compile_receipt} <-
           ContextABI.compile(context_compile_attrs(product_request)),
         {:ok, grant} <-
           ContextAuthority.authorize(packet, authority_request(packet),
             now: @now,
             grant_expires_at: nil
           ),
         {:ok, admission_receipt} <- admit_packet(packet, grant),
         {:ok, route_decision} <- route(packet, grant),
         {:ok, render_result} <- render(packet, route_decision),
         {:ok, invocation_request} <- model_invocation_request(render_result, route_decision),
         {:ok, %{receipt: model_receipt, stream_fragments: stream_fragments}} <-
           invoke_model(invocation_request),
         {:ok, projections} <-
           appkit_projections(packet, admission_receipt, grant, route_decision, model_receipt),
         {:ok, aitrace_facts} <-
           aitrace_facts(packet, grant, route_decision, model_receipt, projections),
         {:ok, scanner_receipts} <-
           scanner_receipts(%{
             packet: packet,
             compile_receipt: compile_receipt,
             grant: grant,
             admission_receipt: admission_receipt,
             route_decision: route_decision,
             render_result: render_result,
             model_receipt: model_receipt,
             projections: projections,
             aitrace_facts: aitrace_facts
           }) do
      {:ok,
       %Receipt{
         receipt_ref: receipt_ref(packet, model_receipt),
         fixture_refs: @fixture_refs,
         status: status(scanner_receipts),
         provider_dependency?: Map.get(opts, :provider_dependency?, false),
         context_packet_ref: packet.context_packet_ref,
         context_packet_hash: packet.packet_hash,
         authority_ref: grant.authority_ref,
         admission_receipt_ref: admission_receipt.receipt_ref,
         route_decision_ref: route_decision.route_decision_ref,
         render_result_ref: render_result.payload_hash,
         prompt_artifact_ref: render_result.prompt_artifact_ref,
         provider_payload_ref: render_result.provider_payload_ref,
         payload_hash: render_result.payload_hash,
         model_invocation_ref: model_receipt.invocation_ref,
         model_receipt_ref: model_receipt.receipt_ref,
         eval_verdict_ref: projections.eval.eval_verdict_ref,
         appkit_projection_refs: appkit_projection_refs(projections),
         scanner_receipts: scanner_receipts,
         aitrace_facts: aitrace_facts,
         trace_refs: [@trace_ref, model_receipt.trace_ref],
         does_not_prove: [
           "live provider behavior",
           "production persistence",
           "distributed BEAM placement",
           "TRINITY router quality beyond fixture adapter behavior",
           "GEPA optimization quality"
         ]
       }}
      |> tap(fn _ -> _ = stream_fragments end)
    end
  end

  @spec to_map(Receipt.t()) :: map()
  def to_map(%Receipt{} = receipt), do: json_safe(receipt)

  @spec to_json!(Receipt.t()) :: String.t()
  def to_json!(%Receipt{} = receipt), do: receipt |> to_map() |> Jason.encode!(pretty: true)

  defp product_request_attrs do
    %{
      request_ref: "request://context-abi/demo/compile",
      tenant_ref: @tenant_ref,
      authority_ref: "authority://context-abi/demo/requested",
      user_request_ref: "artifact://context-abi/demo/user-request",
      system_instruction_ref: "artifact://context-abi/demo/system-instruction",
      memory_refs: ["memory://context-abi/demo/promoted/a"],
      budget_ref: "budget://context-abi/demo/run",
      model_class_allowlist: ["model-class://fixture"],
      route_policy_ref: "route-policy://context-abi/demo/fixture",
      trace_ref: @trace_ref,
      idempotency_key: "idem://context-abi/demo/compile",
      redaction_policy_ref: "redaction-policy://context-abi/demo/refs-only"
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
      actor_ref: "actor://context-abi/operator",
      context_packet_ref: packet.context_packet_ref,
      model_class_allowlist: packet.model_class_allowlist,
      route_policy_ref: packet.route_policy_ref,
      trace_ref: packet.trace_ref,
      trust_classes: [:operator_authored, :memory_promoted],
      evidence_refs: ["evidence://context-abi/policy/default"],
      authority_ref: "authority://context-abi/demo/grant",
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
        idempotency_key: "idem://context-abi/demo/admit",
        trace_ref: packet.trace_ref,
        actor_ref: "actor://context-abi/operator",
        ai_run_ref: @ai_run_ref,
        budget_ref: packet.budget_ref,
        cost_ref: "cost://context-abi/demo/model",
        eval_ref: "eval://context-abi/demo/verdict",
        route_decision_ref: "route-decision://context-abi/demo/pending",
        model_call_ref: "model-invocation://context-abi/demo/pending",
        projection_ref: "appkit://context-abi/demo/projection"
      },
      authority_grant: grant,
      budget_decision: :allow
    )
  end

  defp route(packet, grant) do
    AIExecution.route(%{
      tenant_ref: packet.tenant_ref,
      workflow_ref: @workflow_ref,
      context_packet_ref: packet.context_packet_ref,
      packet_hash: packet.packet_hash,
      authority_ref: grant.authority_ref,
      route_policy_ref: packet.route_policy_ref,
      model_class_allowlist: packet.model_class_allowlist,
      trace_ref: packet.trace_ref
    })
  end

  defp render(packet, route_decision) do
    AIExecution.render_context(packet, route_decision, %RuntimeDeps{},
      workflow_ref: @workflow_ref,
      prompt_tokens: 48,
      provider_family: "fixture",
      payload_mode: :ref_only
    )
  end

  defp model_invocation_request(render_result, route_decision) do
    with {:ok, base_attrs} <-
           AIExecution.invocation_request(render_result, route_decision,
             idempotency_key: "idem://context-abi/demo/model",
             credential_lease_ref: "credential-lease://context-abi/demo/fixture"
           ) do
      ModelInvocation.new_request(
        Map.merge(base_attrs, %{
          invocation_ref: "model-invocation://context-abi/demo/run",
          payload_hash: render_result.payload_hash,
          provider_ref: "provider://fixture",
          endpoint_ref: "endpoint://fixture/chat",
          runtime_ref: "runtime://jido/fake-invoker",
          runtime_kind: :client,
          token_budget_ref: "token-budget://context-abi/demo/run",
          cost_budget_ref: "cost-budget://context-abi/demo/run",
          redaction_class: "bounded_receipt",
          payload_mode: "artifact_ref",
          operation: :generate_text,
          stream?: false,
          issued_at: @now,
          metadata: %{
            "admission_receipt_ref" => "packet-admission://context-abi/demo"
          }
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
             provider_or_runtime_ref: "runtime://jido/fake-invoker",
             verifier_ref: "verifier://context-abi/fixture",
             fallback_plan_ref: "fallback-plan://context-abi/none",
             cost_estimate_ref: "cost-estimate://context-abi/fixture",
             budget_status_ref: "budget-status://context-abi/allow",
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
             cost_ref: "cost://context-abi/demo/model",
             trace_ref: model_receipt.trace_ref
           }),
         {:ok, eval_projection} <-
           ContextSurface.eval_verdict_projection(%{
             eval_verdict_ref: "eval-verdict://context-abi/demo/pass",
             context_packet_ref: packet.context_packet_ref,
             route_decision_ref: route_decision.route_decision_ref,
             model_receipt_ref: model_receipt.receipt_ref,
             verdict: :pass,
             severity_class: "clean",
             decision_evidence_ref: "decision-evidence://context-abi/demo/eval",
             trace_ref: "trace://context-abi/demo/eval"
           }),
         {:ok, review_projection} <-
           ContextSurface.operator_review_projection(%{
             review_ref: "review://context-abi/demo/operator",
             context_packet_ref: packet.context_packet_ref,
             route_decision_ref: route_decision.route_decision_ref,
             eval_verdict_ref: "eval-verdict://context-abi/demo/pass",
             promotion_refs: [],
             rollback_refs: [],
             operator_state: :pending,
             trace_refs: [@trace_ref, "trace://context-abi/demo/eval"]
           }) do
      {:ok,
       %{
         packet: packet_projection,
         route: route_projection,
         model: model_projection,
         eval: eval_projection,
         review: review_projection
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
             eval_case_ref: "eval-case://context-abi/demo/fixture"
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

  defp scanner_receipts(%{
         packet: packet,
         compile_receipt: compile_receipt,
         grant: grant,
         admission_receipt: admission_receipt,
         route_decision: route_decision,
         render_result: render_result,
         model_receipt: model_receipt,
         projections: projections,
         aitrace_facts: aitrace_facts
       }) do
    with {:ok, context_scan} <-
           ContextABIScanner.scan(%{
             owner_repo: "stack_lab",
             package_path: "examples/context_abi_roundtrip",
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
         {:ok, model_scan} <- ModelInferenceScanner.scan(model_scan_input(model_receipt)),
         {:ok, cost_scan} <- CostBudgetScanner.scan(cost_scan_input(model_receipt)),
         {:ok, lineage_scan} <- AIRunLineageScanner.scan(lineage_scan_input(grant)),
         {:ok, tenant_scan} <- TenantIsolationScanner.scan(tenant_scan_input(model_receipt)),
         {:ok, memory_scan} <- MemoryFabricScanner.scan(memory_scan_input(grant)) do
      {:ok,
       %{
         context_abi: context_scan,
         model_inference: model_scan,
         cost_budget: cost_scan,
         ai_run_lineage: lineage_scan,
         tenant_isolation: tenant_scan,
         memory_fabric: memory_scan
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
          operation_policy_ref: "operation-policy://context-abi/generate-text"
        }
      ],
      source_units: []
    }
  end

  defp cost_scan_input(model_receipt) do
    %{
      owner_repo: "mezzanine",
      package_path: "core/ai_execution_engine",
      cost_budget_facts: [
        %{
          token_cost_refs: ["cost://context-abi/tokens"],
          model_request_cost_refs: ["cost://context-abi/model-request"],
          self_hosted_gpu_minute_cost_refs: ["cost://context-abi/gpu-minute/not-applicable"],
          endpoint_startup_cost_refs: ["cost://context-abi/endpoint-startup"],
          eval_batch_cost_refs: ["cost://context-abi/eval-batch"],
          replay_cost_refs: ["cost://context-abi/replay"],
          optimization_search_cost_refs: ["cost://context-abi/optimization/not-applicable"],
          provider_pool_turn_cost_refs: ["cost://context-abi/provider-pool-turn"],
          role_budget_refs: ["budget://context-abi/role/fixture"],
          promotion_cost_refs: ["cost://context-abi/promotion/not-applicable"],
          failed_retry_cost_refs: ["cost://context-abi/retry/none"],
          exhaustion_decision_ref: "budget-exhaustion://context-abi/none",
          appkit_projection_refs: ["appkit://context-abi/projection"],
          aitrace_span_refs: ["aitrace-span://context-abi/model"],
          receipt_refs: [model_receipt.receipt_ref],
          trace_redaction: :redacted
        }
      ]
    }
  end

  defp lineage_scan_input(grant) do
    %{
      owner_repo: "mezzanine",
      package_path: "core/context_packet_engine",
      run_facts: [
        %{
          ai_run_ref: @ai_run_ref,
          tenant_ref: @tenant_ref,
          authority_ref: grant.authority_ref,
          parent_run_ref: "ai-run://context-abi/demo/root",
          idempotency_ref: "idem://context-abi/demo/admit",
          persistence_profile_ref: "persistence://fixture/ref-only",
          optimization_refs: ["optimization://context-abi/not-applicable"],
          trace_refs: [@trace_ref]
        }
      ]
    }
  end

  defp tenant_scan_input(model_receipt) do
    %{
      tenant_ref: @tenant_ref,
      owner_repo: "stack_lab",
      package_path: "examples/context_abi_roundtrip",
      target_code_paths: ["examples/context_abi_roundtrip/lib"],
      facts: [
        %{kind: :receipt, tenant_ref: @tenant_ref, ref: model_receipt.receipt_ref},
        %{kind: :trace, tenant_ref: @tenant_ref, ref: @trace_ref},
        %{kind: :product_projection, tenant_ref: @tenant_ref, ref: "appkit://context-abi/demo"}
      ],
      proof_refs: ["receipt://stack_lab/context_abi_roundtrip/latest"],
      scanner_refs: ["stack-lab.context-abi-scanner.v1"]
    }
  end

  defp memory_scan_input(grant) do
    %{
      owner_repo: "outer_brain",
      runtime_facts: [
        %{
          tenant_ref: @tenant_ref,
          authority_ref: grant.authority_ref,
          installation_ref: "installation://context-abi/demo",
          idempotency_key: "idem://context-abi/demo/compile",
          trace_ref: @trace_ref
        }
      ],
      source_paths: []
    }
  end

  defp appkit_projection_refs(projections) do
    [
      projections.packet.context_packet_ref,
      projections.route.route_decision_ref,
      projections.model.model_receipt_ref,
      projections.eval.eval_verdict_ref,
      projections.review.review_ref
    ]
  end

  defp trace_fact(%{name: name, attributes: attributes}, trace_ref) do
    %{
      trace_ref: trace_ref,
      name: name,
      attributes: attributes
    }
  end

  defp receipt_ref(packet, model_receipt) do
    suffix =
      packet.packet_hash
      |> String.replace_prefix("sha256:", "")
      |> String.slice(0, 16)

    "context-abi-roundtrip://#{suffix}/#{URI.encode_www_form(model_receipt.invocation_ref)}"
  end

  defp status(scanner_receipts) do
    scanner_receipts
    |> Map.values()
    |> Enum.all?(&(&1.status == :pass))
    |> if(do: :pass, else: :open_defect)
  end

  defp json_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json_safe(%_struct{} = value), do: value |> Map.from_struct() |> json_safe()

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), json_safe(nested)} end)
  end

  defp json_safe(values) when is_list(values), do: Enum.map(values, &json_safe/1)
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value), do: value
end
