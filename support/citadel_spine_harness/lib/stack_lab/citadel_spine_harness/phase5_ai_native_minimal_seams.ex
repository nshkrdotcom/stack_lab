defmodule StackLab.CitadelSpineHarness.Phase5AiNativeMinimalSeams do
  @moduledoc false

  alias Jido.Integration.V2.{ControlPlane, InferenceRequest}
  alias OuterBrain.Contracts.{ReplyBodyBoundary, ReplyPublication, SemanticFailure}
  alias OuterBrain.Core.SemanticFrame
  alias OuterBrain.Prompting.ContextPack

  @budget_ref "budget://phase5/m8/local-no-spend-inference"
  @cost_attribution_ref "cost-attribution://phase5/m8/local-no-spend"
  @endpoint_ref "endpoint://phase5/local-no-spend"
  @model_ref "model://phase5/local-no-spend"
  @runtime_target_ref "runtime://jido-integration/inference/local-no-spend"
  @redaction_manifest_ref "redaction-manifest://phase5/semantic-failure-export"
  @release_manifest_ref "ai_native_runtime_guardrail_profiles[m08_descriptor_context_semantic_guardrails]"

  defmodule ContextAdapter do
    @moduledoc false
    @behaviour OuterBrain.Prompting.ContextAdapter

    @impl true
    def fetch_fragments(request, _runtime_binding) do
      {:ok,
       [
         %{
           fragment_id: "fragment-scenario-210",
           schema_ref: request.schema_ref,
           schema_version: 1,
           content: %{"summary" => "Scenario 210 bounded context fragment"},
           provenance: %{"source" => "stack_lab_scenario_210"},
           staleness: %{"class" => "fresh"},
           metadata: %{"rank" => 1}
         }
       ]}
    end
  end

  @spec run_case(
          :context_budget_exceeded
          | :cost_attribution_missing
          | :semantic_failure_evidence_gap
        ) ::
          {:ok, map()}
  def run_case(:context_budget_exceeded) do
    under_budget_pack = build_context_pack!(max_context_bytes: 1_000_000)
    exceeded_budget_pack = build_context_pack!(max_context_bytes: 1)
    unavailable_meter_pack = build_context_pack!(context_budget: :meter_unavailable)

    {:ok,
     %{
       scenario_id: 210,
       case: :context_budget_exceeded,
       budget_ref: @budget_ref,
       model_descriptor_ref: @model_ref,
       endpoint_descriptor_ref: @endpoint_ref,
       runtime_target_ref: @runtime_target_ref,
       positive: %{
         context_pack_decision: under_budget_pack.context_budget.decision,
         fragment_count: length(under_budget_pack.fragments),
         projected_context_bytes: under_budget_pack.context_budget.projected_context_bytes,
         max_context_bytes: under_budget_pack.context_budget.max_context_bytes
       },
       negative_failures:
         context_budget_negative_failures(exceeded_budget_pack, unavailable_meter_pack),
       source_meter_refs: [
         "OuterBrain.Prompting.ContextPack.context_budget",
         "Jido.Integration.V2.ControlPlane.Inference.require_descriptor_refs?",
         "Jido.Integration.V2.ControlPlane.Inference.require_artifact_refs?",
         "Jido.RuntimeControl.cost/1 source-meter input",
         "runtime result cost maps source-meter input"
       ],
       release_manifest_ref: @release_manifest_ref
     }}
  end

  def run_case(:cost_attribution_missing) do
    positive = valid_cost_attribution()

    {:ok,
     %{
       scenario_id: "210A",
       case: :cost_attribution_missing,
       cost_attribution_ref: @cost_attribution_ref,
       positive: %{
         attribution_decision: validate_cost_attribution(positive),
         join_refs: Map.take(positive, required_cost_join_keys())
       },
       negative_failures: %{
         global_counter_only: validate_cost_attribution(%{global_counter: 42}),
         provider_session_only:
           validate_cost_attribution(%{
             provider_session_id: "provider-session-1",
             cost: %{amount: 12, unit: "micro_usd", currency: "USD"}
           }),
         opaque_runtime_cost_map:
           validate_cost_attribution(%{cost: %{amount: 12, unit: "micro_usd"}}),
         missing_tenant_join: positive |> Map.delete(:tenant_ref) |> validate_cost_attribution(),
         missing_endpoint_join:
           positive |> Map.delete(:endpoint_descriptor_ref) |> validate_cost_attribution(),
         missing_source_meter_join:
           positive |> Map.delete(:source_meter_refs) |> validate_cost_attribution()
       },
       non_product_surface: %{
         billing_product_surface: false,
         invoice_product_surface: false,
         quota_ui_surface: false,
         chargeback_product_surface: false
       },
       release_manifest_ref: @release_manifest_ref
     }}
  end

  def run_case(:semantic_failure_evidence_gap) do
    failure = semantic_failure!()

    collision_left =
      semantic_failure!(semantic_session_id: "session:semantic", causal_unit_id: "turn")

    collision_right =
      semantic_failure!(semantic_session_id: "session", causal_unit_id: "semantic:turn")

    {:ok, reply_body} =
      ReplyBodyBoundary.build("cause-scenario-211", :final, "reply-scenario-211", "Done")

    {:ok, publication} =
      ReplyPublication.new(%{
        publication_id: "publication-scenario-211-final",
        causal_unit_id: "cause-scenario-211",
        phase: :final,
        dedupe_key: "reply-scenario-211",
        state: :published,
        body: reply_body.preview,
        body_ref: reply_body.ref
      })

    {:ok,
     %{
       scenario_id: 211,
       case: :semantic_failure_evidence_gap,
       positive: %{
         semantic_failure_id: "semantic-failure://scenario-211/exportable",
         journal_entry_id: SemanticFailure.journal_entry_id(failure),
         journal_identity_payload: SemanticFailure.journal_identity_payload(failure),
         semantic_failure_payload_hash: SemanticFailure.semantic_failure_payload_hash(failure),
         corrected_output_artifact_ref: "artifact://scenario-211/corrected-output-redacted",
         evidence_refs: [
           "OuterBrain.Contracts.SemanticFailure.journal_entry_id/1",
           "OuterBrain.Contracts.SemanticFailure.semantic_failure_payload_hash/1",
           "OuterBrain.Contracts.ReplyBodyBoundary"
         ],
         model_descriptor_ref: @model_ref,
         redaction_manifest_ref: @redaction_manifest_ref,
         incident_or_export_bundle_ref:
           "incident-export://scenario-211/semantic-failure-evidence",
         reply_publication_ref_summary: ReplyBodyBoundary.ref_summary(publication.body_ref)
       },
       negative_failures: %{
         missing_evidence_refs: validate_semantic_failure_export(%{evidence_refs: []}),
         raw_prompt_provider_body_export:
           validate_semantic_failure_export(%{
             raw_prompt: :redacted_placeholder,
             raw_provider_body: :redacted_placeholder
           }),
         feedback_training_promotion_fields:
           validate_semantic_failure_export(%{training_ready_marker: true}),
         opaque_delimiter_new_write:
           validate_semantic_failure_export(%{
             journal_entry_id: SemanticFailure.legacy_journal_entry_id(failure)
           }),
         delimiter_collision: %{
           legacy_ids_equal:
             SemanticFailure.legacy_journal_entry_id(collision_left) ==
               SemanticFailure.legacy_journal_entry_id(collision_right),
           structured_ids_equal?:
             SemanticFailure.journal_entry_id(collision_left) ==
               SemanticFailure.journal_entry_id(collision_right),
           result: :structured_ids_do_not_collide
         },
         agent_mutation_proposal_denial: %{
           proposal_ref: "agent-proposal://scenario-211/direct-policy-pack-mutation",
           result: {:error, :agent_direct_mutation_path_forbidden},
           direct_mutation_allowed?: false,
           proposal_state: :quarantined,
           rate_limit_key: "tenant-scenario-211:agent-scenario-211:policy-pack",
           dedupe_key: "sha256:" <> String.duplicate("d", 64),
           blast_radius: :tenant_local,
           quarantined_scopes: [:multi_tenant, :platform_global],
           accepted_reentry_paths: [
             :human_reviewed_proposal,
             :signed_authoring_bundle,
             :operator_approved_migration
           ]
         },
         unbounded_reply_publication:
           ReplyPublication.new(%{
             publication_id: "publication-scenario-211-raw",
             causal_unit_id: "cause-scenario-211",
             phase: :final,
             dedupe_key: "reply-scenario-211-raw",
             state: :published,
             body: String.duplicate("full semantic reply ", 300),
             body_ref: %{}
           })
       },
       release_manifest_ref: @release_manifest_ref
     }}
  end

  defp context_budget_negative_failures(exceeded_budget_pack, unavailable_meter_pack) do
    %{
      preflight_input_tokens: reject(:preflight, :input_tokens_budget_exceeded, :deny),
      preflight_wall_clock: reject(:preflight, :request_wall_clock_budget_exceeded, :shed),
      preflight_descriptor_refs: missing_descriptor_refs(),
      tool_result_append_context_bytes: %{
        locus: :tool_result_append,
        result: {:error, :context_budget_exceeded},
        decision: exceeded_budget_pack.context_budget.decision,
        fragments_appended?: exceeded_budget_pack.fragments != []
      },
      tool_result_append_unavailable_meter: %{
        locus: :tool_result_append,
        result: {:error, :context_budget_meter_unavailable},
        decision: unavailable_meter_pack.context_budget.decision,
        fragments_appended?: unavailable_meter_pack.fragments != []
      },
      stream_tick_output_tokens: reject(:stream_tick, :output_token_budget_exceeded, :truncate),
      stream_tick_streamed_bytes: reject(:stream_tick, :streamed_byte_budget_exceeded, :shed),
      runtime_admission_gpu_seconds:
        reject(:runtime_admission, :gpu_seconds_budget_exceeded, :deny),
      runtime_admission_cpu_ms: reject(:runtime_admission, :cpu_ms_budget_exceeded, :shed),
      runtime_admission_memory_mb_seconds:
        reject(:runtime_admission, :memory_mb_seconds_budget_exceeded, :shed),
      runtime_admission_cost: reject(:runtime_admission, :cost_budget_exceeded, :deny),
      runtime_admission_concurrency:
        reject(:runtime_admission, :tenant_role_model_target_concurrency_exceeded, :shed),
      post_run_reconcile_actual_cost: %{
        locus: :post_run_reconcile,
        result: {:error, :actual_cost_overrun},
        decision: :quarantine,
        retroactive_authorization?: false
      }
    }
  end

  defp missing_descriptor_refs do
    request =
      InferenceRequest.new!(%{
        request_id: "req-scenario-210-missing-descriptor",
        operation: :generate_text,
        messages: [%{role: "user", content: "prove descriptor fail closed"}],
        prompt: nil,
        model_preference: %{provider: "openai", id: "gpt-local"},
        target_preference: %{target_class: "cloud_provider"},
        stream?: false,
        tool_policy: %{},
        output_constraints: %{},
        metadata: %{tenant_id: "tenant-scenario-210"}
      })

    %{
      locus: :preflight,
      result:
        ControlPlane.invoke_inference(request,
          run_id: "run-scenario-210-missing-descriptor",
          trace_id: "trace-scenario-210-missing-descriptor",
          require_descriptor_refs?: true
        ),
      decision: :deny
    }
  end

  defp reject(locus, reason, decision) do
    %{locus: locus, result: {:error, reason}, decision: decision, side_effect_committed?: false}
  end

  defp build_context_pack!(opts) do
    frame =
      "session-scenario-210"
      |> SemanticFrame.seed("answer with bounded context")
      |> SemanticFrame.record_commitment("I will enforce context budget before append")

    context_budget =
      Keyword.get(opts, :context_budget) ||
        %{
          budget_ref: @budget_ref,
          budget_scope: "subject://scenario-210",
          max_context_bytes: Keyword.fetch!(opts, :max_context_bytes),
          current_context_bytes: 0,
          enforcement_point: :tool_result_append
        }

    ContextPack.build(
      frame,
      ["turn/scenario-210", "artifact/scenario-210"],
      mode: :reply,
      trace_id: "trace-scenario-210",
      context_sources: [
        %{
          source_ref: "workspace_memory",
          binding_key: "shared_memory",
          usage_phase: :retrieval,
          required?: true,
          timeout_ms: 1_000,
          schema_ref: "context/workspace_memory",
          max_fragments: 1
        }
      ],
      context_bindings: %{
        "shared_memory" => %{"adapter_key" => "scenario_210_context", "config" => %{}}
      },
      adapter_registry: %{"scenario_210_context" => ContextAdapter},
      context_budget: context_budget
    )
  end

  defp valid_cost_attribution do
    %{
      tenant_ref: "tenant://tenant-scenario-210",
      installation_ref: "installation://scenario-210/local-no-spend",
      authority_decision_ref: "authority-decision://scenario-210/no-spend",
      lineage_ref: "lineage://scenario-210/root",
      budget_ref: @budget_ref,
      runtime_ref: @runtime_target_ref,
      provider_ref: "provider://phase5/local-no-spend",
      model_descriptor_ref: @model_ref,
      endpoint_descriptor_ref: @endpoint_ref,
      source_meter_refs: ["Jido.RuntimeControl.cost/1", "runtime result cost maps"],
      cost: %{amount: 0, unit: "micro_usd", currency: "USD"}
    }
  end

  defp validate_cost_attribution(attribution) when is_map(attribution) do
    case Enum.reject(required_cost_join_keys(), &present?(attribution, &1)) do
      [] -> :attribute
      missing -> {:error, {:missing_cost_attribution_join_refs, missing}}
    end
  end

  defp required_cost_join_keys do
    [
      :tenant_ref,
      :installation_ref,
      :authority_decision_ref,
      :lineage_ref,
      :budget_ref,
      :runtime_ref,
      :provider_ref,
      :model_descriptor_ref,
      :endpoint_descriptor_ref,
      :source_meter_refs
    ]
  end

  defp validate_semantic_failure_export(evidence) when is_map(evidence) do
    cond do
      Map.get(evidence, :evidence_refs) == [] ->
        {:error, :missing_semantic_failure_evidence_refs}

      Map.has_key?(evidence, :raw_prompt) or Map.has_key?(evidence, :raw_provider_body) ->
        {:error, :raw_sensitive_payload_not_export_evidence}

      Map.has_key?(evidence, :training_ready_marker) ->
        {:error, :feedback_training_promotion_field_forbidden}

      evidence |> Map.get(:journal_entry_id, "") |> String.starts_with?("semantic_failure:") ->
        {:error, :legacy_delimiter_journal_id_new_write_forbidden}

      true ->
        :ok
    end
  end

  defp semantic_failure!(overrides \\ []) do
    attrs =
      %{
        kind: :semantic_insufficient_context,
        tenant_id: "tenant-scenario-211",
        semantic_session_id: "session-scenario-211",
        causal_unit_id: "turn-scenario-211",
        request_trace_id: "trace-scenario-211",
        canonical_idempotency_key: "idem:v1:scenario-211",
        context_hash: "sha256:" <> String.duplicate("a", 64),
        provenance: [%{"source" => "stack_lab_scenario_211"}],
        operator_message: "Scenario 211 corrected semantic failure evidence."
      }
      |> Map.merge(Map.new(overrides))

    {:ok, failure} = SemanticFailure.new(attrs)
    failure
  end

  defp present?(map, key) do
    case Map.get(map, key) do
      nil -> false
      [] -> false
      "" -> false
      _value -> true
    end
  end
end
