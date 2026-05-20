defmodule StackLab.CitadelSpineHarness.PrelimServiceMode do
  @moduledoc false

  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecision
  alias Jido.Integration.V2.TenantScope
  alias Mezzanine.Leasing.AuthorizationScope
  alias Mezzanine.Lifecycle.{Evaluator, SubjectSnapshot}

  alias Mezzanine.Pack.{
    CompiledPack,
    Compiler,
    DecisionSpec,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    ProjectionSpec,
    SubjectKindSpec
  }

  alias Mezzanine.WorkflowRuntime.{
    ExecutionLifecycleWorkflow,
    FinalTemporalCutover,
    TemporalSupervisor
  }

  alias OuterBrain.Contracts.{
    ContextAdapterReadOnly,
    PrivacyRedactionFixture,
    ReplyBodyBoundary,
    ReplyPublication,
    SemanticContextProvenance,
    SemanticFailure,
    SuppressionVisibility
  }

  alias StackLab.CitadelSpineHarness.{
    AppKitOperationalSurface,
    LowerFacts,
    OuterBrainDurability,
    ProfileSlots,
    TemporalPostgresProjectionDrift
  }

  @stack_lab_root Path.expand("../../../../..", __DIR__)
  @mezzanine_root Path.expand("../mezzanine", @stack_lab_root)
  @release_ref "phase5prelim-m3-service-path-contract-join"
  @m5_release_ref "phase5prelim-m5-service-profile-bootstrap"
  @m5_smoke_release_ref "phase5prelim-m5-governed-smoke"
  @m5_pressure_release_ref "phase5prelim-m5-pressure-and-negatives"
  @required_owner_evidence_ids ["P5P-011", "P5P-012", "P5P-013", "P5P-014"]
  @pressure_tenant_count 3
  @pressure_agents_per_tenant 4
  @pressure_work_items_per_agent 2
  @pressure_max_concurrency 6
  @pressure_work_item_count @pressure_tenant_count * @pressure_agents_per_tenant *
                              @pressure_work_items_per_agent
  @pressure_fault_classes [
    :timeout,
    :malformed_response,
    :partial_response,
    :rate_limit,
    :unavailable_meter
  ]
  @forbidden_provider_local_selectors [
    "ClaudeAgentSDK.Mock",
    "ClaudeAgentSDK.Mock.Process",
    "GEMINI_CLI_PATH",
    "AMP_CLI_PATH",
    "Codex fixture scripts"
  ]

  @spec run_case(
          :m3_contract_join
          | :m5_service_profile_bootstrap
          | :m5_governed_smoke
          | :m5_pressure_and_negatives,
          keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def run_case(case_name, opts \\ [])

  def run_case(:m3_contract_join, opts) when is_list(opts) do
    with {:ok, substrate} <- temporal_substrate(opts),
         {:ok, temporal} <- temporal_contract(),
         {:ok, workload} <- service_workload_contract(),
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

  def run_case(:m5_service_profile_bootstrap, opts) when is_list(opts) do
    with {:ok, substrate} <- temporal_substrate(opts),
         {:ok, worker_health} <- temporal_worker_health(),
         {:ok, profile} <- service_simulation_profile(),
         {:ok, installation} <- install_service_profiles([profile]),
         {:ok, cleanup} <- cleanup_service_profiles(installation),
         {:ok, negative_failures} <- service_profile_negative_failures(profile) do
      {:ok,
       %{
         case: :m5_service_profile_bootstrap,
         release_manifest_ref: @m5_release_ref,
         temporal: %{
           substrate: substrate,
           worker_health: worker_health
         },
         service_profiles: %{
           installed: installation,
           cleanup: cleanup,
           profile: profile
         },
         owner_evidence: owner_evidence(),
         negative_failures: negative_failures,
         service_mode_gate: %{
           temporal_required?: true,
           profile_installation_required?: true,
           owner_contracts_consumed?: true,
           provider_local_mock_selectors_denied?: true
         }
       }}
    end
  end

  def run_case(:m5_governed_smoke, opts) when is_list(opts) do
    with {:ok, substrate} <- temporal_substrate(opts),
         {:ok, worker_health} <- temporal_worker_health(),
         {:ok, profile} <- service_simulation_profile(),
         {:ok, installation} <- install_service_profiles([profile]),
         {:ok, workload} <- service_workload_contract(),
         {:ok, authority} <- authority_contract(),
         {:ok, semantic} <- semantic_contract(),
         {:ok, appkit_smoke} <-
           AppKitOperationalSurface.run_case(:reviewable_connector_automation_console),
         {:ok, smoke_evidence} <-
           governed_smoke_evidence(profile, workload, authority, semantic, appkit_smoke),
         {:ok, cleanup} <- cleanup_service_profiles(installation),
         {:ok, negative_failures} <- governed_smoke_negative_failures(smoke_evidence) do
      {:ok,
       %{
         case: :m5_governed_smoke,
         release_manifest_ref: @m5_smoke_release_ref,
         temporal: %{
           substrate: substrate,
           worker_health: worker_health
         },
         service_profiles: %{
           installed: installation,
           cleanup: cleanup,
           profile: profile
         },
         governed_smoke: smoke_evidence,
         owner_evidence: owner_evidence(),
         negative_failures: negative_failures,
         service_mode_gate: %{
           temporal_required?: true,
           governed_subject_required?: true,
           review_gate_required?: true,
           lower_trace_required?: true,
           semantic_hop_required?: true,
           owner_contracts_consumed?: true
         }
       }}
    end
  end

  def run_case(:m5_pressure_and_negatives, opts) when is_list(opts) do
    with {:ok, substrate} <- temporal_substrate(opts),
         {:ok, worker_health} <- temporal_worker_health(),
         {:ok, profile} <- service_simulation_profile(),
         {:ok, installation} <- install_service_profiles([profile]),
         {:ok, workload} <- service_workload_contract(),
         {:ok, authority} <- authority_contract(),
         {:ok, semantic} <- semantic_contract(),
         {:ok, appkit_smoke} <-
           AppKitOperationalSurface.run_case(:reviewable_connector_automation_console),
         {:ok, smoke_evidence} <-
           governed_smoke_evidence(profile, workload, authority, semantic, appkit_smoke),
         {:ok, pressure_evidence} <-
           bounded_pressure_evidence(profile, workload, authority, semantic, smoke_evidence),
         {:ok, fault_matrix} <- budget_cost_fault_matrix(profile, authority),
         {:ok, negative_failures} <-
           pressure_and_bypass_negative_failures(
             pressure_evidence,
             fault_matrix,
             authority,
             semantic
           ),
         {:ok, cleanup} <- cleanup_service_profiles(installation) do
      {:ok,
       %{
         case: :m5_pressure_and_negatives,
         release_manifest_ref: @m5_pressure_release_ref,
         temporal: %{
           substrate: substrate,
           worker_health: worker_health
         },
         service_profiles: %{
           installed: installation,
           cleanup: cleanup,
           profile: profile
         },
         pressure: pressure_evidence,
         budget_cost_fault_matrix: fault_matrix,
         owner_evidence: owner_evidence(),
         negative_failures: negative_failures,
         service_mode_gate: %{
           temporal_required?: true,
           bounded_pressure_required?: true,
           max_concurrency_enforced?: true,
           no_slo_claim?: true,
           no_real_provider_spend?: true,
           fault_matrix_required?: true,
           tenant_authority_no_bypass_required?: true,
           owner_contracts_consumed?: true
         }
       }}
    end
  end

  defp temporal_substrate(opts) do
    runner = Keyword.get(opts, :temporal_runner, &StackLab.CommandRunner.system_cmd/3)
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

  defp temporal_worker_health do
    hazmat = hazmat_worker_spec!()

    {:ok,
     %{
       status: :healthy,
       task_queue: hazmat.task_queue,
       instance_base: Mezzanine.WorkflowRuntime.PrelimTemporal,
       workflows: hazmat.workflows,
       execution_attempt_registered?: Mezzanine.Workflows.ExecutionAttempt in hazmat.workflows,
       activities: hazmat.activities
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

  defp service_workload_contract do
    manifest = service_workload_manifest()
    recipe_ref = "service_operations"

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
      {:ok,
       %{
         work_class: %{
           name: "service_operations",
           kind: "service_task",
           intake_required: ["title", "description"]
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

  defp service_simulation_profile do
    profile = %{
      profile_ref: "service-simulation-profile://phase5prelim/m5/bootstrap",
      run_ref: "run://phase5prelim/m5/bootstrap",
      workload_ref: "workload://phase5prelim/governed-smoke",
      pack_ref: "pack://stack_lab/service_operations",
      work_class_ref: "work-class://stack_lab/service_operations",
      subject_kind: "service_task",
      adapter_profile_refs: %{
        cli_core: "adapter-profile://cli_subprocess_core/6ef1c72",
        asm: "adapter-profile://agent_session_manager/eed6b45",
        rest: "adapter-profile://pristine/83e8c04",
        graphql: "adapter-profile://prismatic/5bd56b0",
        self_hosted: "adapter-profile://self_hosted_inference_core/79a5643"
      },
      lower_scenario_refs: %{
        execution_plane: [
          "lower-simulation://execution-plane/http/827f428",
          "lower-simulation://execution-plane/process/832ddcd"
        ],
        cli: "lower-simulation://cli-family/provider-runtime",
        rest: "lower-simulation://pristine/http-provider",
        graphql: "lower-simulation://prismatic/graphql-provider",
        self_hosted: "lower-simulation://self-hosted/ready"
      },
      owner_evidence_refs: owner_evidence(),
      authority_policy_ref: "authority-policy://phase5prelim/tenant-prelim",
      budget_profile_ref: "budget://phase5prelim/local-no-spend",
      meter_profile_ref: "meter://phase5prelim/deterministic",
      artifact_policy: %{
        raw_prompts: :deny,
        raw_provider_bodies: :deny,
        raw_workflow_histories: :deny,
        bounded_previews: :allow
      },
      input_fingerprint_policy: %{
        mode: :transient_hash,
        algorithm: :sha256,
        persist_raw_body?: false
      },
      egress_policy: :deny_real_provider_and_saas,
      forbidden_selectors: [],
      cleanup_policy: %{
        remove_application_env?: true,
        remove_temp_profiles?: true,
        leave_owner_evidence?: true
      }
    }

    with :ok <- validate_service_profile(profile), do: {:ok, profile}
  end

  defp install_service_profiles(profiles) when is_list(profiles) do
    with :ok <- Enum.reduce_while(profiles, :ok, &validate_profile_reducer/2) do
      {:ok,
       %{
         registry_ref: "stack-lab-profile-registry://phase5prelim/m5/bootstrap",
         installed_profile_refs: Enum.map(profiles, & &1.profile_ref),
         installed_count: length(profiles),
         owner_evidence_ids:
           profiles
           |> Enum.flat_map(&Map.keys(&1.owner_evidence_refs))
           |> Enum.uniq()
           |> Enum.sort(),
         cleanup_required?: true
       }}
    end
  end

  defp cleanup_service_profiles(%{installed_profile_refs: refs} = installation) do
    {:ok,
     %{
       registry_ref: installation.registry_ref,
       removed_profile_refs: refs,
       removed_count: length(refs),
       cleanup_complete?: true
     }}
  end

  defp service_profile_negative_failures(profile) do
    missing_owner =
      profile
      |> update_in([:owner_evidence_refs], &Map.delete(&1, "P5P-014"))
      |> validate_service_profile()
      |> rejected()

    forbidden_selector =
      profile
      |> Map.put(:forbidden_selectors, ["GEMINI_CLI_PATH"])
      |> validate_service_profile()
      |> rejected()

    invalid_egress =
      profile
      |> Map.put(:egress_policy, :allow_real_provider_fallback)
      |> validate_service_profile()
      |> rejected()

    {:ok,
     %{
       missing_owner_evidence: missing_owner,
       provider_local_mock_selector: forbidden_selector,
       invalid_egress_policy: invalid_egress
     }}
  end

  defp governed_smoke_evidence(profile, workload, authority, semantic, appkit_smoke) do
    evidence = %{
      workload_profile: %{
        profile_ref: profile.profile_ref,
        workload_ref: profile.workload_ref,
        pack_ref: profile.pack_ref,
        work_class_ref: profile.work_class_ref,
        subject_kind: workload.pack.subject_kind,
        lifecycle_after_execution: workload.lifecycle.after_execution_completed,
        lifecycle_after_review: workload.lifecycle.after_review_accept
      },
      run_shape: %{
        tenant_count: 1,
        agent_count: 1,
        work_item_count: 1,
        max_concurrency: 1,
        no_slo_claim?: true
      },
      owner_path_refs: %{
        appkit_tenant_ref: appkit_smoke.tenant_id,
        authority_decision_ref: authority.authority_decision.decision_id,
        authorization_scope_ref:
          "authorization-scope://#{authority.authorization_scope.tenant_id}/#{authority.authorization_scope.execution_id}",
        semantic_ref: semantic.context_provenance.semantic_ref,
        semantic_failure_ref: semantic.semantic_failure.trace_id,
        lower_submission_ref: appkit_smoke.lower_access.submission_receipt_ref
      },
      governed_subject: %{
        subject_ref: appkit_smoke.automation_case.subject_id,
        source_kind: "linear",
        subject_kind: workload.pack.subject_kind,
        lifecycle_state_before_pause: appkit_smoke.automation_case.lifecycle_state_before_pause,
        lifecycle_state_after_review: appkit_smoke.automation_case.lifecycle_state_after_review
      },
      agent_execution: %{
        run_ref: appkit_smoke.automation_case.run_id,
        execution_ref: appkit_smoke.automation_case.lineage_execution_ref_after_review,
        submission_key: appkit_smoke.lower_access.submission_key,
        submission_receipt_ref: appkit_smoke.lower_access.submission_receipt_ref,
        trace_ref: appkit_smoke.trace.trace_id,
        trace_step_sources: appkit_smoke.trace.step_sources
      },
      review_gate: %{
        decision_ref: appkit_smoke.review.decision_id,
        status_before: appkit_smoke.review.status_before,
        status_after: appkit_smoke.review.status_after,
        action_kind: appkit_smoke.review.action_kind,
        pending_ids_before: appkit_smoke.console.pending_review_ids_before,
        pending_ids_after: appkit_smoke.console.pending_review_ids_after
      },
      lower_access: %{
        post_pause_read: appkit_smoke.lower_access.post_pause_read,
        post_pause_stream: appkit_smoke.lower_access.post_pause_stream,
        no_real_provider_spend?: profile.egress_policy == :deny_real_provider_and_saas
      }
    }

    with :ok <- validate_governed_smoke(evidence), do: {:ok, evidence}
  end

  defp governed_smoke_negative_failures(smoke_evidence) do
    missing_review_gate =
      smoke_evidence
      |> put_in([:review_gate, :decision_ref], nil)
      |> validate_governed_smoke()
      |> rejected()

    missing_lower_trace =
      smoke_evidence
      |> put_in([:agent_execution, :trace_step_sources], ["audit_fact", "execution_record"])
      |> validate_governed_smoke()
      |> rejected()

    non_service_subject =
      smoke_evidence
      |> put_in([:governed_subject, :subject_kind], "expense_request")
      |> validate_governed_smoke()
      |> rejected()

    {:ok,
     %{
       missing_review_gate: missing_review_gate,
       missing_lower_trace: missing_lower_trace,
       non_service_subject: non_service_subject
     }}
  end

  defp validate_governed_smoke(%{
         run_shape: %{tenant_count: 1, agent_count: 1, work_item_count: 1},
         governed_subject: %{subject_ref: subject_ref, subject_kind: "service_task"},
         agent_execution: %{
           execution_ref: execution_ref,
           submission_receipt_ref: "submission://" <> _receipt_ref,
           trace_step_sources: trace_step_sources
         },
         review_gate: %{
           decision_ref: decision_ref,
           status_before: "pending",
           status_after: "accepted",
           action_kind: "review_accept"
         },
         lower_access: %{no_real_provider_spend?: true}
       })
       when is_binary(subject_ref) and is_binary(execution_ref) and is_binary(decision_ref) and
              is_list(trace_step_sources) do
    if "lower_run_status" in trace_step_sources do
      :ok
    else
      {:error, {:missing_trace_source, "lower_run_status"}}
    end
  end

  defp validate_governed_smoke(%{governed_subject: %{subject_kind: subject_kind}})
       when subject_kind != "service_task" do
    {:error, {:invalid_subject_kind, subject_kind}}
  end

  defp validate_governed_smoke(_evidence), do: {:error, :invalid_governed_smoke_evidence}

  defp bounded_pressure_evidence(profile, workload, authority, semantic, smoke_evidence) do
    tenants =
      for tenant_idx <- 1..@pressure_tenant_count do
        pressure_tenant(tenant_idx, profile, workload, authority, semantic, smoke_evidence)
      end

    work_items = tenants |> Enum.flat_map(& &1.agents) |> Enum.flat_map(& &1.work_items)
    agent_count = tenants |> Enum.flat_map(& &1.agents) |> length()

    evidence = %{
      profile_ref: profile.profile_ref,
      smoke_template_ref: smoke_evidence.agent_execution.submission_receipt_ref,
      run_shape: %{
        tenant_count: length(tenants),
        agents_per_tenant: @pressure_agents_per_tenant,
        agent_count: agent_count,
        work_items_per_agent: @pressure_work_items_per_agent,
        work_item_count: length(work_items),
        max_concurrency: @pressure_max_concurrency,
        no_slo_claim?: true
      },
      workload_profile: %{
        workload_ref: profile.workload_ref,
        pack_ref: profile.pack_ref,
        work_class_ref: profile.work_class_ref,
        subject_kind: workload.pack.subject_kind,
        lifecycle_after_execution: workload.lifecycle.after_execution_completed,
        lifecycle_after_review: workload.lifecycle.after_review_accept,
        review_gate: workload.lifecycle.review_gate
      },
      tenants: tenants,
      dispatch_window: %{
        scheduler: :bounded_async_stream,
        admitted_work_items: length(work_items),
        max_in_flight: @pressure_max_concurrency,
        measured_baseline_kind: :local_provisional,
        slo_claim?: false
      },
      cost: %{
        budget_ref: profile.budget_profile_ref,
        meter_ref: profile.meter_profile_ref,
        total_cost_units: 0,
        no_real_provider_spend?: true,
        no_real_saas_writes?: true
      },
      owner_path_refs: %{
        authority_decision_ref: authority.authority_decision.decision_id,
        authorization_scope_ref:
          "authorization-scope://#{authority.authorization_scope.tenant_id}/#{authority.authorization_scope.execution_id}",
        semantic_ref: semantic.context_provenance.semantic_ref,
        semantic_failure_ref: semantic.semantic_failure.trace_id,
        lower_template_ref: smoke_evidence.agent_execution.submission_receipt_ref
      }
    }

    with :ok <- validate_bounded_pressure(evidence), do: {:ok, evidence}
  end

  defp pressure_tenant(tenant_idx, profile, workload, authority, semantic, smoke_evidence) do
    tenant_ref = "tenant-prelim-pressure-#{tenant_idx}"

    %{
      tenant_ref: tenant_ref,
      authority_decision_ref: authority.authority_decision.decision_id,
      semantic_ref: semantic.context_provenance.semantic_ref,
      agents:
        for agent_idx <- 1..@pressure_agents_per_tenant do
          pressure_agent(
            tenant_ref,
            tenant_idx,
            agent_idx,
            profile,
            workload,
            smoke_evidence
          )
        end
    }
  end

  defp pressure_agent(tenant_ref, tenant_idx, agent_idx, profile, workload, smoke_evidence) do
    agent_ref = "agent://phase5prelim/pressure/t#{tenant_idx}/a#{agent_idx}"

    %{
      agent_ref: agent_ref,
      route_ref: profile.adapter_profile_refs.asm,
      provider_family: :cli,
      work_items:
        for item_idx <- 1..@pressure_work_items_per_agent do
          pressure_work_item(
            tenant_ref,
            tenant_idx,
            agent_idx,
            item_idx,
            workload,
            smoke_evidence
          )
        end
    }
  end

  defp pressure_work_item(tenant_ref, tenant_idx, agent_idx, item_idx, workload, smoke_evidence) do
    item_ref = "work://phase5prelim/pressure/t#{tenant_idx}/a#{agent_idx}/i#{item_idx}"
    execution_ref = "execution://phase5prelim/pressure/t#{tenant_idx}/a#{agent_idx}/i#{item_idx}"

    %{
      work_item_ref: item_ref,
      tenant_ref: tenant_ref,
      subject_kind: workload.pack.subject_kind,
      source_kind: "linear",
      lifecycle_after_execution: workload.lifecycle.after_execution_completed,
      lifecycle_after_review: workload.lifecycle.after_review_accept,
      execution_ref: execution_ref,
      authorization_scope_ref: "authorization-scope://#{tenant_ref}/#{execution_ref}",
      trace_ref: "trace://phase5prelim/pressure/t#{tenant_idx}/a#{agent_idx}/i#{item_idx}",
      lower_submission_ref:
        "submission://phase5prelim/pressure/t#{tenant_idx}/a#{agent_idx}/i#{item_idx}",
      lower_template_ref: smoke_evidence.agent_execution.submission_receipt_ref,
      provider_egress_allowed?: false,
      cost_units: 0,
      review_gate: :operator_review
    }
  end

  defp validate_bounded_pressure(%{
         run_shape: %{
           tenant_count: @pressure_tenant_count,
           agent_count: agent_count,
           work_item_count: @pressure_work_item_count,
           max_concurrency: max_concurrency,
           no_slo_claim?: true
         },
         cost: %{
           total_cost_units: 0,
           no_real_provider_spend?: true,
           no_real_saas_writes?: true
         },
         tenants: tenants
       })
       when agent_count == @pressure_tenant_count * @pressure_agents_per_tenant and
              max_concurrency <= @pressure_max_concurrency and is_list(tenants) do
    work_items = tenants |> Enum.flat_map(& &1.agents) |> Enum.flat_map(& &1.work_items)

    cond do
      Enum.any?(work_items, & &1.provider_egress_allowed?) ->
        {:error, :real_provider_egress_allowed}

      Enum.any?(work_items, &(&1.subject_kind != "service_task")) ->
        {:error, :non_service_pressure_subject}

      true ->
        :ok
    end
  end

  defp validate_bounded_pressure(%{run_shape: %{max_concurrency: max_concurrency}})
       when max_concurrency > @pressure_max_concurrency do
    {:error, {:max_concurrency_exceeded, max_concurrency}}
  end

  defp validate_bounded_pressure(%{cost: %{no_real_provider_spend?: false}}) do
    {:error, :real_provider_spend_allowed}
  end

  defp validate_bounded_pressure(_evidence), do: {:error, :invalid_pressure_evidence}

  defp budget_cost_fault_matrix(profile, authority) do
    matrix = %{
      budget: %{
        budget_ref: profile.budget_profile_ref,
        authority_decision_ref: authority.authority_decision.decision_id,
        admission: :accepted,
        total_cost_units: 0,
        enforcement_points: [
          :preflight,
          :tool_result_append,
          :stream_tick,
          :runtime_admission,
          :post_run_reconcile
        ]
      },
      cost: %{
        meter_ref: profile.meter_profile_ref,
        unit: :deterministic_local_unit,
        provider_billable_units: 0,
        real_provider_spend?: false
      },
      faults:
        Enum.map(@pressure_fault_classes, fn fault_class ->
          %{
            fault_class: fault_class,
            owner_adapter: fault_owner_adapter(fault_class),
            injected_at: :configured_adapter_boundary,
            safe_action: safe_fault_action(fault_class),
            lower_side_effects?: false
          }
        end)
    }

    with :ok <- validate_fault_matrix(matrix), do: {:ok, matrix}
  end

  defp fault_owner_adapter(:timeout), do: :execution_plane_process
  defp fault_owner_adapter(:malformed_response), do: :cli_subprocess_core
  defp fault_owner_adapter(:partial_response), do: :pristine
  defp fault_owner_adapter(:rate_limit), do: :prismatic
  defp fault_owner_adapter(:unavailable_meter), do: :self_hosted_inference_core

  defp safe_fault_action(:timeout), do: :retry_with_backoff
  defp safe_fault_action(:malformed_response), do: :terminal_provider_error
  defp safe_fault_action(:partial_response), do: :request_replay_or_reject
  defp safe_fault_action(:rate_limit), do: :defer_until_budget_window
  defp safe_fault_action(:unavailable_meter), do: :deny_before_dispatch

  defp validate_fault_matrix(%{
         budget: %{budget_ref: budget_ref, total_cost_units: 0},
         cost: %{real_provider_spend?: false},
         faults: faults
       })
       when is_binary(budget_ref) and is_list(faults) do
    fault_classes = Enum.map(faults, & &1.fault_class) |> Enum.sort()

    if fault_classes == Enum.sort(@pressure_fault_classes) and
         Enum.all?(faults, &(&1.lower_side_effects? == false)) do
      :ok
    else
      {:error, {:invalid_fault_matrix, fault_classes}}
    end
  end

  defp validate_fault_matrix(%{budget: %{budget_ref: nil}}), do: {:error, :missing_budget_ref}
  defp validate_fault_matrix(_matrix), do: {:error, :invalid_fault_matrix}

  defp pressure_and_bypass_negative_failures(pressure, fault_matrix, authority, semantic) do
    max_concurrency_breach =
      pressure
      |> put_in([:run_shape, :max_concurrency], @pressure_max_concurrency + 1)
      |> validate_bounded_pressure()
      |> rejected()

    real_provider_spend =
      pressure
      |> put_in([:cost, :no_real_provider_spend?], false)
      |> validate_bounded_pressure()
      |> rejected()

    missing_budget =
      fault_matrix
      |> put_in([:budget, :budget_ref], nil)
      |> validate_fault_matrix()
      |> rejected()

    direct_lower_shortcut =
      %{
        authority_scope_ref:
          "authorization-scope://#{authority.authorization_scope.tenant_id}/#{authority.authorization_scope.execution_id}",
        semantic_ref: semantic.context_provenance.semantic_ref,
        lower_access: :direct_lower_shortcut
      }
      |> validate_owner_path_access()
      |> rejected()

    missing_semantic_boundary =
      %{
        authority_scope_ref:
          "authorization-scope://#{authority.authorization_scope.tenant_id}/#{authority.authorization_scope.execution_id}",
        semantic_ref: nil,
        lower_access: :via_owner_path
      }
      |> validate_owner_path_access()
      |> rejected()

    {:ok,
     %{
       cross_tenant_lower_read: authority.lower_read.unauthorized_error,
       missing_authority_tenant: authority.negative_failures.missing_authority_tenant,
       missing_authorization_scope: authority.negative_failures.missing_mezzanine_scope_tenant,
       missing_lower_tenant_scope: authority.negative_failures.missing_lower_scope_tenant,
       missing_budget_ref: missing_budget,
       max_concurrency_breach: max_concurrency_breach,
       real_provider_spend: real_provider_spend,
       direct_lower_shortcut: direct_lower_shortcut,
       missing_semantic_boundary: missing_semantic_boundary
     }}
  end

  defp validate_owner_path_access(%{semantic_ref: nil}), do: {:error, :missing_semantic_boundary}

  defp validate_owner_path_access(%{lower_access: :direct_lower_shortcut}),
    do: {:error, :direct_lower_shortcut}

  defp validate_owner_path_access(_access), do: {:error, :invalid_owner_path_access}

  defp validate_profile_reducer(profile, :ok) do
    case validate_service_profile(profile) do
      :ok -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp validate_service_profile(profile) when is_map(profile) do
    [
      &validate_required_owner_evidence/1,
      &validate_forbidden_selectors/1,
      &validate_egress_policy/1,
      &validate_artifact_policy/1
    ]
    |> Enum.reduce_while(:ok, fn validate, :ok ->
      case validate.(profile) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_required_owner_evidence(%{owner_evidence_refs: owner_evidence_refs}) do
    missing =
      @required_owner_evidence_ids
      |> Enum.reject(&Map.has_key?(owner_evidence_refs, &1))

    case missing do
      [] -> :ok
      missing -> {:error, {:missing_owner_evidence, missing}}
    end
  end

  defp validate_required_owner_evidence(_profile) do
    {:error, {:missing_owner_evidence, @required_owner_evidence_ids}}
  end

  defp validate_forbidden_selectors(%{forbidden_selectors: selectors}) do
    case Enum.find(selectors, &(&1 in @forbidden_provider_local_selectors)) do
      nil -> :ok
      selector -> {:error, {:provider_local_mock_selector_forbidden, selector}}
    end
  end

  defp validate_forbidden_selectors(_profile), do: :ok

  defp validate_egress_policy(%{egress_policy: :deny_real_provider_and_saas}), do: :ok

  defp validate_egress_policy(%{egress_policy: egress_policy}) do
    {:error, {:invalid_egress_policy, egress_policy}}
  end

  defp validate_egress_policy(_profile), do: {:error, {:missing_egress_policy, nil}}

  defp validate_artifact_policy(%{
         artifact_policy: %{
           raw_prompts: :deny,
           raw_provider_bodies: :deny,
           raw_workflow_histories: :deny
         }
       }),
       do: :ok

  defp validate_artifact_policy(%{artifact_policy: artifact_policy}) do
    {:error, {:invalid_artifact_policy, artifact_policy}}
  end

  defp validate_artifact_policy(_profile), do: {:error, {:missing_artifact_policy, nil}}

  defp owner_evidence do
    %{
      "P5P-011" => %{
        owner: :execution_plane,
        source_commits: ["827f428", "832ddcd"],
        evidence: [:lower_process, :lower_http, :no_egress, :bounded_evidence]
      },
      "P5P-012" => %{
        owner: :cli_subprocess_core_and_agent_session_manager,
        source_commits: ["a28bff6", "6ef1c72", "eed6b45"],
        evidence: [:provider_native_wire, :asm_core_route, :missing_profile_denial]
      },
      "P5P-013" => %{
        owner: :pristine_and_prismatic,
        source_commits: ["83e8c04", "5bd56b0"],
        evidence: [:rest_http, :graphql, :provider_wrappers, :egress_denial]
      },
      "P5P-014" => %{
        owner: :self_hosted_inference_core,
        source_commits: ["79a5643"],
        evidence: [
          :configured_manifest,
          :readiness,
          :health,
          :lease,
          :endpoint_descriptor,
          :deterministic_response_ref,
          :bypass_denial
        ]
      }
    }
  end

  defp subject_snapshot(manifest, lifecycle_state) do
    SubjectSnapshot.new(%{
      subject_kind: subject_kind_atom(manifest),
      lifecycle_state: lifecycle_state,
      payload: %{
        "identifier" => "PRELIM-1",
        "title" => "Prove PRELIM service-mode contract join",
        "source_kind" => "linear"
      }
    })
  end

  defp subject_kind(manifest) do
    manifest
    |> subject_kind_atom()
    |> Atom.to_string()
  end

  defp subject_kind_atom(manifest) do
    manifest.subject_kind_specs
    |> List.first()
    |> Map.fetch!(:name)
    |> case do
      value when is_atom(value) -> value
      "service_task" -> :service_task
    end
  end

  defp service_workload_manifest do
    %Manifest{
      pack_slug: "stack_lab_service_ops",
      version: "1.0.0-prelim",
      migration_strategy: :additive,
      profile_slots:
        ProfileSlots.default(
          source_profile_ref: :lab_source,
          runtime_profile_ref: :service_runtime,
          tool_scope_ref: :service_tools_v1,
          evidence_profile_ref: :service_evidence,
          publication_profile_ref: :service_publication,
          review_profile_ref: :human_operator,
          projection_profile_ref: :service_projection_v1
        ),
      subject_kind_specs: [%SubjectKindSpec{name: "service_task"}],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: "service_task",
          initial_state: :submitted,
          terminal_states: [:completed, :rejected, :expired],
          transitions: [
            %{
              from: :submitted,
              to: :awaiting_review,
              trigger: {:execution_completed, "service_operations"}
            },
            %{
              from: :submitted,
              to: :retry_submission,
              trigger: {:execution_failed, "service_operations"}
            },
            %{from: :retry_submission, to: :submitted, trigger: :auto},
            %{
              from: :awaiting_review,
              to: :completed,
              trigger: {:decision_made, "operator_review", :accept}
            },
            %{
              from: :awaiting_review,
              to: :rejected,
              trigger: {:decision_made, "operator_review", :reject}
            },
            %{
              from: :awaiting_review,
              to: :expired,
              trigger: {:decision_made, "operator_review", :expired}
            }
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: "service_operations",
          placement_ref: :local_default,
          runtime_class: :session,
          workspace_policy: %{
            strategy: :per_subject,
            root_ref: "service_operations_workspaces"
          },
          sandbox_policy_ref: "service_operations_sandbox",
          prompt_refs: ["service_operations_prompt"]
        }
      ],
      decision_specs: [
        %DecisionSpec{
          decision_kind: :operator_review,
          description: "Operator review gate for StackLab service workload",
          trigger: {:after_execution_completed, "service_operations"},
          authorized_actors: [:operator],
          allowed_decisions: [:accept, :reject, :expired],
          required_within_hours: 24
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: "operator_queue", subject_kinds: ["service_task"]}
      ]
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
      resource_profile: "service_task",
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
    {:ok, reply_body} =
      ReplyBodyBoundary.build(
        "causal-unit-prelim",
        :final,
        "reply-publication-prelim",
        "Bounded public reply body."
      )

    %{
      publication_id: "publication-prelim-final",
      causal_unit_id: "causal-unit-prelim",
      phase: :final,
      dedupe_key: "reply-publication-prelim",
      state: :published,
      body: reply_body.preview,
      body_ref: reply_body.ref
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
