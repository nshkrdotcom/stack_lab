defmodule StackLab.CitadelSpineHarness.PrelimServiceMode do
  @moduledoc false

  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecision
  alias Extravaganza.ProductPack
  alias Extravaganza.WorkClasses.CodingOperations
  alias Jido.Integration.V2.TenantScope
  alias Mezzanine.Leasing.AuthorizationScope
  alias Mezzanine.Lifecycle.{Evaluator, SubjectSnapshot}
  alias Mezzanine.Pack.{CompiledPack, Compiler}

  alias Mezzanine.WorkflowRuntime.{
    ExecutionLifecycleWorkflow,
    FinalTemporalCutover,
    TemporalSupervisor
  }

  alias OuterBrain.Contracts.{
    ContextAdapterReadOnly,
    PrivacyRedactionFixture,
    ReplyPublication,
    SemanticContextProvenance,
    SemanticFailure,
    SuppressionVisibility
  }

  alias StackLab.CitadelSpineHarness.{
    LowerFacts,
    OuterBrainDurability,
    TemporalPostgresProjectionDrift
  }

  @stack_lab_root Path.expand("../../../../..", __DIR__)
  @mezzanine_root Path.expand("../mezzanine", @stack_lab_root)
  @release_ref "phase5prelim-m3-service-path-contract-join"

  @spec run_case(:m3_contract_join, keyword()) :: {:ok, map()} | {:error, term()}
  def run_case(:m3_contract_join, opts \\ []) when is_list(opts) do
    with {:ok, substrate} <- temporal_substrate(opts),
         {:ok, temporal} <- temporal_contract(),
         {:ok, workload} <- extravaganza_workload_contract(),
         {:ok, authority} <- authority_contract(),
         {:ok, semantic} <- semantic_contract() do
      {:ok,
       %{
         case: :m3_contract_join,
         release_manifest_ref: @release_ref,
         temporal: Map.put(temporal, :substrate, substrate),
         workload: workload,
         authority: authority,
         semantic: semantic,
         service_mode_gate: %{
           temporal_required?: true,
           non_temporal_classification: :lower_runtime_smoke_only,
           owner_contracts_joined?: true
         }
       }}
    end
  end

  defp temporal_substrate(opts) do
    runner = Keyword.get(opts, :temporal_runner, &System.cmd/3)
    mezzanine_root = Keyword.get(opts, :mezzanine_root, @mezzanine_root)

    case runner.("just", ["dev-status"], cd: mezzanine_root, stderr_to_stdout: true) do
      {output, 0} ->
        if String.contains?(output, "SERVING") and
             String.contains?(output, "mezzanine-temporal-dev.service") do
          {:ok,
           %{
             checked_by: "just dev-status",
             mezzanine_root: mezzanine_root,
             namespace: "default",
             endpoint: "127.0.0.1:7233",
             ui: "http://127.0.0.1:8233",
             service: "mezzanine-temporal-dev.service",
             status: :serving
           }}
        else
          {:error, {:temporal_substrate_not_serving, compact_output(output)}}
        end

      {output, status} ->
        {:error, {:temporal_substrate_check_failed, status, compact_output(output)}}
    end
  end

  defp temporal_contract do
    {:ok, scenario_201} =
      TemporalPostgresProjectionDrift.run_case(:temporal_postgres_projection_drift)

    cutover = FinalTemporalCutover.manifest()
    workflow = ExecutionLifecycleWorkflow.contract()
    hazmat = hazmat_worker_spec!()

    {:ok,
     %{
       workflow: %{
         module: workflow.workflow_module,
         contract: workflow.workflow_contract,
         task_queue: workflow.task_queue,
         activity_sequence: workflow.activity_sequence,
         activity_owners: workflow.activity_owners,
         execution_attempt_registered?: Mezzanine.Workflows.ExecutionAttempt in hazmat.workflows,
         temporal_boundary: Mezzanine.WorkflowRuntime
       },
       oban_cutover: %{
         retained_queues: cutover.retained_oban_queues,
         retained_workers: cutover.retained_oban_workers,
         retired_saga_workers: Enum.map(cutover.retired_oban_saga_workers, & &1.worker),
         active_worker_modules: FinalTemporalCutover.active_oban_worker_modules(@mezzanine_root),
         invalid_queue_configs: FinalTemporalCutover.invalid_oban_queue_configs(@mezzanine_root),
         invalid_saga_references:
           FinalTemporalCutover.invalid_oban_saga_references(@mezzanine_root),
         temporalex_boundary_violations:
           FinalTemporalCutover.temporalex_boundary_violations(@mezzanine_root)
       },
       compact_temporal: scenario_201.positive_path.compact_temporal_lookup,
       projection_drift_negatives: %{
         conflicting_terminal: scenario_201.negative_failures.conflicting_terminal.reason,
         missing_terminal_event_ref:
           scenario_201.negative_failures.missing_terminal_event_ref.reason,
         workflow_start_outbox_bypass:
           scenario_201.negative_failures.workflow_start_outbox_bypass.legacy_direct_enqueue
       }
     }}
  end

  defp hazmat_worker_spec! do
    TemporalSupervisor.task_queue_specs(
      enabled?: true,
      instance_base: Mezzanine.WorkflowRuntime.PrelimTemporal
    )
    |> Enum.find(&(&1.task_queue == "mezzanine.hazmat"))
    |> case do
      nil -> raise "missing mezzanine.hazmat Temporal worker spec"
      spec -> spec
    end
  end

  defp extravaganza_workload_contract do
    config = extravaganza_config()
    manifest = ProductPack.manifest(config)
    recipe_ref = ProductPack.execution_recipe_ref(config)

    with {:ok, compiled} <- Compiler.compile(manifest),
         {:ok, execution_transition} <-
           Evaluator.can_transition?(
             compiled,
             subject_snapshot(manifest, :submitted),
             {:execution_completed, recipe_ref}
           ),
         {:ok, review_transition} <-
           Evaluator.can_transition?(
             compiled,
             subject_snapshot(manifest, execution_transition.to),
             {:decision_made, "operator_review", :accept}
           ) do
      work_class = CodingOperations.definition()

      {:ok,
       %{
         work_class: %{
           name: work_class.name,
           kind: work_class.kind,
           intake_required: work_class.intake_schema["required"]
         },
         pack: %{
           pack_slug: manifest.pack_slug,
           version: manifest.version,
           subject_kind: subject_kind(manifest),
           compiled_pack_revision_source: compiled.pack_slug
         },
         lifecycle: %{
           initial_state: "submitted",
           after_execution_completed: execution_transition.to,
           review_gate: :operator_review,
           after_review_accept: review_transition.to,
           terminal_after_accept?:
             CompiledPack.terminal_state?(
               compiled,
               subject_kind(manifest),
               review_transition.to
             )
         }
       }}
    end
  end

  defp authority_contract do
    decision = AuthorityDecision.new!(authority_decision_attrs())

    scope =
      AuthorizationScope.new!(%{
        tenant_id: decision.tenant_id,
        installation_id: "installation-prelim",
        installation_revision: 1,
        activation_epoch: 1,
        lease_epoch: 1,
        subject_id: "subject-prelim",
        execution_id: "execution-prelim",
        trace_id: "trace-prelim",
        actor_ref: %{kind: :system, id: "stack_lab_prelim"},
        authorized_at: DateTime.from_unix!(1_800_003_000)
      })

    lower_scope =
      TenantScope.new!(%{
        tenant_id: scope.tenant_id,
        installation_id: scope.installation_id,
        actor_ref: scope.actor_ref,
        trace_id: scope.trace_id,
        authorized_at: scope.authorized_at
      })

    {:ok, authorized_read} = LowerFacts.run_case(:authorized_mezzanine_readback)
    {:ok, unauthorized_read} = LowerFacts.run_case(:unauthorized_mezzanine_readback)

    {:ok,
     %{
       authority_decision: %{
         contract_version: decision.contract_version,
         decision_id: decision.decision_id,
         tenant_id: decision.tenant_id,
         decision_hash: decision.decision_hash
       },
       authorization_scope: AuthorizationScope.dump(scope),
       lower_tenant_scope: TenantScope.dump(lower_scope),
       lower_read: %{
         authorized_operation: authorized_read.operation,
         authorized_source: authorized_read.source,
         unauthorized_error: unauthorized_read.error
       },
       negative_failures: %{
         missing_authority_tenant:
           rejected(AuthorityDecision.new(Map.delete(authority_decision_attrs(), :tenant_id))),
         missing_mezzanine_scope_tenant:
           rejected(
             AuthorizationScope.new(Map.delete(AuthorizationScope.dump(scope), :tenant_id))
           ),
         missing_lower_scope_tenant:
           rejected(TenantScope.new(Map.delete(TenantScope.dump(lower_scope), :tenant_id)))
       }
     }}
  end

  defp semantic_contract do
    scope = semantic_scope_attrs()

    {:ok, provenance} = SemanticContextProvenance.new(semantic_provenance_attrs(scope))
    {:ok, read_only} = ContextAdapterReadOnly.new(context_adapter_attrs(scope))
    {:ok, redaction} = PrivacyRedactionFixture.new(redaction_attrs(scope))
    {:ok, suppression} = SuppressionVisibility.new(suppression_attrs(scope))
    {:ok, failure} = SemanticFailure.new(semantic_failure_attrs())
    {:ok, publication} = ReplyPublication.new(reply_publication_attrs())

    {:ok, failure_durability} =
      OuterBrainDurability.run_case(:semantic_failure_carrier_after_restart)

    {:ok, duplicate_publication} =
      OuterBrainDurability.run_case(:duplicate_publication_suppressed_after_restart)

    {:ok,
     %{
       context_provenance: %{
         semantic_ref: provenance.semantic_ref,
         provider_ref: provenance.provider_ref,
         input_claim_check_ref: provenance.input_claim_check_ref,
         output_claim_check_ref: provenance.output_claim_check_ref,
         redaction_policy_ref: provenance.redaction_policy_ref
       },
       read_only_context_adapter: %{
         adapter_ref: read_only.adapter_ref,
         denied_write_resources: read_only.denied_write_resources,
         mutation_permissions: read_only.mutation_permissions
       },
       privacy_redaction: %{
         fixture_ref: redaction.fixture_ref,
         scan_ref: redaction.scan_ref,
         public_payload: redaction.public_payload,
         search_attributes: redaction.search_attributes
       },
       suppression_visibility: %{
         suppression_ref: suppression.suppression_ref,
         operator_visibility: suppression.operator_visibility,
         recovery_action_refs: suppression.recovery_action_refs
       },
       semantic_failure: %{
         kind: failure.kind,
         retry_class: failure.retry_class,
         trace_id: failure.request_trace_id
       },
       reply_publication: %{
         publication_id: publication.publication_id,
         phase: publication.phase,
         state: publication.state
       },
       durability: %{
         semantic_failure_retry_classes:
           failure_durability.after_restart.semantic_failure_retry_classes,
         duplicate_publication_ids: duplicate_publication.after_restart.publication_ids,
         duplicate_replayed_publication_id: duplicate_publication.durable.replayed_publication_id
       },
       negative_failures: %{
         raw_public_payload:
           rejected(
             PrivacyRedactionFixture.new(
               Map.put(redaction_attrs(scope), :public_payload, %{raw_prompt: "forbidden"})
             )
           ),
         context_adapter_write_permission:
           rejected(
             ContextAdapterReadOnly.new(
               Map.put(context_adapter_attrs(scope), :mutation_permissions, [:write])
             )
           ),
         missing_semantic_failure_tenant:
           rejected(SemanticFailure.new(Map.delete(semantic_failure_attrs(), :tenant_id)))
       }
     }}
  end

  defp subject_snapshot(manifest, lifecycle_state) do
    SubjectSnapshot.new(%{
      subject_kind: subject_kind(manifest),
      lifecycle_state: lifecycle_state,
      payload: %{
        "identifier" => "PRELIM-1",
        "title" => "Prove PRELIM service-mode contract join",
        "source_kind" => "linear_issue"
      }
    })
  end

  defp subject_kind(manifest) do
    manifest.subject_kind_specs
    |> List.first()
    |> Map.fetch!(:name)
    |> Atom.to_string()
  end

  defp extravaganza_config do
    %{
      tenant_id: "tenant-prelim",
      program_slug: "extravaganza_coding_ops",
      program_name: "Extravaganza Coding Ops",
      product_family: "operator_proving_ground",
      pack_version: "1.0.0-prelim",
      policy_bundle_name: "default_coding_ops",
      policy_bundle_version: "1.0.0",
      work_class_name: "coding_operations",
      work_class_kind: "coding_task",
      placement_profile_id: "local_default",
      execution_timeout_ms: 300_000,
      linear_source_kind: "linear_issue",
      operator_surface_enabled?: true
    }
  end

  defp authority_decision_attrs do
    %{
      contract_version: "v1",
      decision_id: "authority-decision-prelim",
      tenant_id: "tenant-prelim",
      request_id: "request-prelim",
      policy_version: "policy-prelim-v1",
      boundary_class: "service_mode_simulation",
      trust_profile: "operator_verified",
      approval_profile: "review_required",
      egress_profile: "blocked",
      workspace_profile: "read_write_ephemeral",
      resource_profile: "coding_task",
      decision_hash: String.duplicate("a", 64),
      extensions: %{"citadel" => %{"budget_ref" => "budget://prelim/local"}}
    }
  end

  defp semantic_scope_attrs do
    %{
      tenant_ref: "tenant-prelim",
      installation_ref: "installation-prelim",
      workspace_ref: "workspace-prelim",
      project_ref: "project-prelim",
      environment_ref: "local",
      resource_ref: "coding-task-prelim",
      authority_packet_ref: "authority-packet-prelim",
      permission_decision_ref: "authority-decision-prelim",
      idempotency_key: "semantic-prelim-idempotency",
      trace_id: "trace-prelim",
      correlation_id: "correlation-prelim",
      release_manifest_ref: @release_ref,
      principal_ref: "principal-operator"
    }
  end

  defp semantic_provenance_attrs(scope) do
    Map.merge(scope, %{
      semantic_ref: "semantic://prelim/turn-1",
      provider_ref: "provider://simulation/cli",
      model_ref: "model://simulation/gpt-5.4",
      prompt_hash: "sha256:" <> String.duplicate("1", 64),
      context_hash: "sha256:" <> String.duplicate("2", 64),
      input_claim_check_ref: "claim://semantic/input/prelim",
      output_claim_check_ref: "claim://semantic/output/prelim",
      provenance_refs: ["context://prelim/workspace"],
      normalizer_version: "outer-brain-normalizer.v1",
      redaction_policy_ref: "redaction://prelim/no-raw-body"
    })
  end

  defp context_adapter_attrs(scope) do
    Map.merge(scope, %{
      adapter_ref: "context-adapter://prelim/workspace-readonly",
      allowed_read_resources: ["workspace://prelim/root"],
      denied_write_resources: ["workspace://prelim/root", "lower://*"],
      read_claim_check_ref: "claim://semantic/context/prelim",
      mutation_scan_ref: "scan://semantic/context/prelim",
      mutation_permissions: []
    })
  end

  defp redaction_attrs(scope) do
    Map.merge(scope, %{
      redaction_policy_ref: "redaction://prelim/no-raw-body",
      raw_field_name: "raw_prompt",
      public_field_name: "prompt_hash",
      redaction_class: "hash_only",
      fixture_ref: "fixture://privacy/prelim",
      scan_ref: "scan://privacy/prelim",
      public_payload: %{prompt_hash: "sha256:" <> String.duplicate("3", 64)},
      search_attributes: %{"TraceRef" => "trace-prelim", "WorkflowType" => "execution_attempt"}
    })
  end

  defp suppression_attrs(scope) do
    Map.merge(scope, %{
      suppression_ref: "suppression://prelim/semantic-failure",
      suppression_kind: "semantic_failure",
      reason_code: "semantic_insufficient_context",
      target_ref: "semantic://prelim/turn-1",
      operator_visibility: "visible",
      recovery_action_refs: ["recovery://prelim/request-clarification"],
      diagnostics_ref: "diagnostics://prelim/semantic-failure"
    })
  end

  defp semantic_failure_attrs do
    %{
      kind: :semantic_insufficient_context,
      tenant_id: "tenant-prelim",
      semantic_session_id: "semantic-session-prelim",
      causal_unit_id: "causal-unit-prelim",
      request_trace_id: "trace-prelim",
      substrate_trace_id: "trace-substrate-prelim",
      provenance: [%{"semantic_ref" => "semantic://prelim/turn-1"}],
      context_hash: "sha256:" <> String.duplicate("4", 64),
      provider_ref: %{"provider_ref" => "provider://simulation/cli"},
      operator_message: "Clarification required before lower dispatch."
    }
  end

  defp reply_publication_attrs do
    %{
      publication_id: "publication-prelim-final",
      causal_unit_id: "causal-unit-prelim",
      phase: :final,
      dedupe_key: "reply-publication-prelim",
      state: :published,
      body: "Bounded public reply body."
    }
  end

  defp rejected({:error, reason}), do: reason
  defp rejected({:ok, _value}), do: :unexpected_acceptance

  defp compact_output(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.take(-8)
    |> Enum.join("\n")
  end
end
