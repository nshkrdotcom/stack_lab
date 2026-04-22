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
    AppKitOperationalSurface,
    LowerFacts,
    OuterBrainDurability,
    TemporalPostgresProjectionDrift
  }

  @stack_lab_root Path.expand("../../../../..", __DIR__)
  @mezzanine_root Path.expand("../mezzanine", @stack_lab_root)
  @release_ref "phase5prelim-m3-service-path-contract-join"
  @m5_release_ref "phase5prelim-m5-service-profile-bootstrap"
  @required_owner_evidence_ids ["P5P-011", "P5P-012", "P5P-013", "P5P-014"]
  @forbidden_provider_local_selectors [
    "ClaudeAgentSDK.Mock",
    "ClaudeAgentSDK.Mock.Process",
    "GEMINI_CLI_PATH",
    "AMP_CLI_PATH",
    "Codex fixture scripts"
  ]

  @spec run_case(
          :m3_contract_join | :m5_service_profile_bootstrap | :m5_governed_smoke,
          keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def run_case(case_name, opts \\ [])

  def run_case(:m3_contract_join, opts) when is_list(opts) do
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
         {:ok, workload} <- extravaganza_workload_contract(),
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
         release_manifest_ref: "phase5prelim-m5-governed-smoke",
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

  defp service_simulation_profile do
    profile = %{
      profile_ref: "service-simulation-profile://phase5prelim/m5/bootstrap",
      run_ref: "run://phase5prelim/m5/bootstrap",
      workload_ref: "workload://phase5prelim/governed-smoke",
      pack_ref: "pack://extravaganza/coding_operations",
      work_class_ref: "work-class://extravaganza/coding_operations",
      subject_kind: "coding_task",
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

    non_coding_subject =
      smoke_evidence
      |> put_in([:governed_subject, :subject_kind], "expense_request")
      |> validate_governed_smoke()
      |> rejected()

    {:ok,
     %{
       missing_review_gate: missing_review_gate,
       missing_lower_trace: missing_lower_trace,
       non_coding_subject: non_coding_subject
     }}
  end

  defp validate_governed_smoke(%{
         run_shape: %{tenant_count: 1, agent_count: 1, work_item_count: 1},
         governed_subject: %{subject_ref: subject_ref, subject_kind: "coding_task"},
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
       when subject_kind != "coding_task" do
    {:error, {:invalid_subject_kind, subject_kind}}
  end

  defp validate_governed_smoke(_evidence), do: {:error, :invalid_governed_smoke_evidence}

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
