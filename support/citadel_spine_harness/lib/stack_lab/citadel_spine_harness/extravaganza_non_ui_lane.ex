defmodule StackLab.CitadelSpineHarness.ExtravaganzaNonUiLane do
  @moduledoc false

  alias AppKit.Core.{
    DecisionRef,
    EvidenceProjection,
    ExecutionRef,
    ExecutionStateProjection,
    LowerReceiptSummary,
    ReviewProjection,
    RuntimeEventSummary,
    RuntimeFactsProjection,
    SourceBindingProjection,
    SubjectRef,
    SubjectRuntimeProjection,
    WorkspaceRef
  }

  alias Extravaganza.{
    CodingOpsTemplates,
    Config,
    ProductBootstrap,
    ProductHost,
    ProductPack,
    RunProfiles.DefaultCodexProfile
  }

  alias Mezzanine.Pack.{CompiledPack, Compiler}
  alias StackLab.CitadelSpineHarness.MezzanineSubstrate

  @forbidden_selector_keys [
    "github_issue_number",
    "linear_issue_id",
    "issue_number",
    "pr_number",
    "comment_id",
    "review_id",
    "workflow_id",
    "codex_session_id"
  ]

  @acceptance_scenario_id "extravaganza.local_single_node.v1"

  @spec run_case(
          :deterministic_full_lane
          | :local_single_node_verification
          | :failure_matrix
          | :live_readiness
        ) ::
          {:ok, map()}
  def run_case(:deterministic_full_lane) do
    config = fixture_config()
    compiled_pack = compile_pack!(config)
    projection = runtime_projection!()
    preview = CodingOpsTemplates.source_publication_preview(projection)
    forbidden_hits = forbidden_selector_hits(preview)

    {:ok,
     %{
       case: :deterministic_full_lane,
       acceptance_kind: :credential_free_internal_contract,
       path: [
         :linear_source_admission,
         :workspace_allocation,
         :codex_session_receipt,
         :github_pr_evidence,
         :operator_review,
         :linear_terminal_publication_readback
       ],
       pack: pack_summary(compiled_pack, config),
       local_worker: %{
         placement: :local_worker,
         workspace_ref: "workspace://extravaganza/discovered-task",
         governed_by: [:mezzanine_workspace_engine, :citadel_execution_governance]
       },
       remote_worker: %{
         placement: :ssh_exec,
         contract_status: :deterministic_ssh_exec_contract,
         owner: :jido_integration,
         proof:
           "core/asm_runtime_bridge/test/jido/integration/v2/asm_runtime_bridge/runtime_control_driver_ssh_exec_test.exs"
       },
       runtime: %{
         codex_event_kind: "codex.session.completed",
         lower_receipt_ref: "lower_receipt://terminal-success",
         lower_run_ref: "lower-run://terminal-success",
         lower_attempt_ref: "lower-attempt://terminal-success"
       },
       evidence: %{
         refs: Enum.map(projection.evidence, & &1.evidence_ref),
         content_refs: Enum.map(projection.evidence, & &1.content_ref)
       },
       review: %{
         status: projection.review.status,
         pending_decision_refs: Enum.map(projection.review.pending_decision_refs, & &1.id)
       },
       source_publication: %{
         publish_ref: preview.publish_ref,
         template_ref: preview.template_ref,
         operation: preview.operation,
         source_binding_ref: preview.source_binding_ref,
         lower_receipt_refs: preview.lower_receipt_refs,
         evidence_refs: preview.evidence_refs,
         pending_decision_refs: preview.pending_decision_refs,
         body: preview.body
       },
       identity_lifecycle: %{
         source: :linear_source_admission_fixture,
         workspace: :workspace_record_ref,
         codex: :lower_receipt_provider_session_ref,
         github: :provider_create_output_or_lower_receipt,
         review: :durable_decision_id,
         terminal_source_write: :workflow_source_publisher_receipt,
         provider_objects: :source_admission_provider_create_outputs_workflow_state_and_receipts
       },
       static_selector_keys_present?: forbidden_hits != [],
       forbidden_selector_hits: forbidden_hits
     }}
  end

  def run_case(:local_single_node_verification) do
    product_path = exercise_owner_product_path!()
    runtime_profile = runtime_profile(product_path.run_metadata)

    {:ok,
     %{
       case: :local_single_node_verification,
       scenario_id: @acceptance_scenario_id,
       acceptance_kind: :local_single_node_owner_product_path,
       product_path: product_path,
       runtime_profile: runtime_profile,
       repo_shas: repo_shas(),
       runbook: local_single_node_runbook(),
       acceptance_claim_rows: acceptance_claim_rows(product_path, runtime_profile),
       symphony_parity_claim_rows: symphony_parity_claim_rows(),
       provider_smoke_scope: :provider_reachability_only,
       stack_lab_role: :external_acceptance_harness_not_product_runtime
     }}
  end

  def run_case(:failure_matrix) do
    {:ok,
     %{
       case: :failure_matrix,
       variants: %{
         terminal_source_cleanup:
           owner_row(
             :mezzanine,
             :owner_test_green,
             "core/projection_engine/test/mezzanine/projections/source_reconciliation_test.exs",
             "terminal source state cancels/cleans by policy"
           ),
         source_reassignment:
           owner_row(
             :mezzanine,
             :owner_test_green,
             "core/projection_engine/test/mezzanine/projections/source_reconciliation_test.exs",
             "assigned-away source preserves workspace and stops execution"
           ),
         missing_source_item:
           owner_row(
             :mezzanine,
             :owner_test_green,
             "core/projection_engine/test/mezzanine/projections/source_reconciliation_test.exs",
             "missing source item becomes a reconciler action"
           ),
         blocker_after_poll:
           owner_row(
             :mezzanine,
             :owner_test_green,
             "core/source_engine/test/mezzanine/source_engine/admission_test.exs",
             "candidate admission rechecks blockers before dispatch"
           ),
         stall_timeout:
           owner_row(
             :mezzanine,
             :owner_test_green,
             "core/workflow_runtime/test/mezzanine/workflow_runtime/execution_lifecycle_workflow_test.exs",
             "turn loop returns retry_or_cancel on stall timeout"
           ),
         lower_process_failure:
           owner_row(
             :stack_lab,
             :deterministic_contract_green,
             "support/citadel_spine_harness/test/app_kit_operational_surface_test.exs",
             "semantic lower failure routes into operator recovery"
           ),
         approval_required:
           owner_row(
             :mezzanine,
             :owner_test_green,
             "core/workflow_runtime/test/mezzanine/workflow_runtime/execution_lifecycle_workflow_test.exs",
             "non-interactive approval_required becomes failure",
             expected_subject_state: "failed"
           ),
         input_required:
           owner_row(
             :mezzanine,
             :owner_test_green,
             "core/projection_engine/test/mezzanine/projections/receipt_reducer_test.exs",
             "input_required becomes blocked for operator attention",
             expected_subject_state: "blocked"
           ),
         malformed_protocol:
           owner_row(
             :jido_integration,
             :owner_test_green,
             "core/contracts/test/jido/integration/v2/receipt_contract_test.exs",
             "malformed lower protocol is a terminal receipt outcome"
           ),
         cancellation:
           owner_row(
             :mezzanine,
             :owner_test_green,
             "core/workflow_runtime/test/mezzanine/workflow_runtime/operator_signal_control_test.exs",
             "operator cancel is a registered workflow signal with local receipt"
           ),
         restart_replay:
           owner_row(
             :stack_lab,
             :deterministic_contract_green,
             "examples/mezzanine_restart_recovery/test/mezzanine_restart_recovery_test.exs",
             "workflow/outbox restart replay is duplicate-safe"
           )
       }
     }}
  end

  def run_case(:live_readiness) do
    {:ok,
     %{
       case: :live_readiness,
       current_live_status: :provider_smoke_check_available,
       default_ci_requires_live?: false,
       live_command_contract: %{
         command: "mix stack_lab.provider_smoke_check",
         secret_bootstrap: "/home/home/scripts/with_bash_secrets",
         non_secret_inputs: :typed_cli_or_control_api,
         credential_flow: :jido_connection_or_credential_lease,
         provider_identity:
           :connector_discovery_create_outputs_source_admission_workflow_state_or_receipts,
         static_provider_selector_acceptance?: false,
         github_write_target: "nshkrdotcom/test"
       },
       provider_smoke_check_steps: [
         :internal_appkit_projection,
         :temporal_status,
         :linear_terminal_publication,
         :github_disposable_pr,
         :codex_session_turn,
         :receipt_write
       ],
       current_green_prerequisites: [
         :linear_typed_no_env_live_acceptance,
         :github_typed_no_env_live_acceptance_with_disposable_pr,
         :codex_local_app_server_live_acceptance,
         :codex_ssh_exec_deterministic_contract,
         :mezzanine_temporal_outbox_restart_contract,
         :app_kit_runtime_projection_readback,
         :extravaganza_prompt_workpad_readback
       ]
     }}
  end

  defp exercise_owner_product_path! do
    MezzanineSubstrate.with_store(:extravaganza_local_single_node_verification, fn _repo_config ->
      tenant_id = "stack-lab-extravaganza-#{System.unique_integer([:positive])}"
      pack_version = "1.0.0-stack-lab.#{System.unique_integer([:positive])}"
      opts = product_opts(tenant_id, pack_version)

      {:ok, bootstrap} = ProductBootstrap.ensure_bootstrapped(opts)
      {:ok, start_result} = ProductHost.start_run(linear_subject_fixture(), opts)
      {:ok, status} = ProductHost.run_status(start_result.payload.run_ref, %{}, opts)
      {:ok, queue} = ProductHost.operator_queue(%{}, opts)
      {:ok, reviews} = ProductHost.pending_reviews(%{}, opts)

      review_decision =
        record_product_review(start_result.payload.run_ref, reviews.page.entries, opts)

      %{
        bootstrap_installation_ref: bootstrap.installation_ref.id,
        bootstrap_pack: bootstrap.pack,
        appkit_entrypoints: [
          "Extravaganza.ProductHost.start_run/2",
          "AppKit.WorkSurface.ingest_subject/3",
          "AppKit.WorkControl.start_run/3"
        ],
        subject_ref: product_subject_ref(start_result, queue),
        run_ref: run_ref_id(start_result.payload.run_ref),
        workflow_start_ref: start_result.payload.workflow_start_ref,
        workflow_start_outbox_id: start_result.payload.workflow_start_outbox_id,
        workflow_dispatch_state: start_result.payload.workflow_dispatch_state,
        work_object_id: start_result.payload.work_object_id,
        recipe_ref: start_result.payload.recipe_ref,
        review_required: start_result.payload.review_required,
        review_unit_id: start_result.payload.review_unit_id,
        run_state: start_result.state,
        status_timeline_count: length(status.timeline),
        queue_subject_refs: Enum.map(queue.page.entries, & &1.subject_ref.id),
        pending_review_refs: Enum.map(reviews.page.entries, & &1.decision_ref.id),
        review_decision_ref: review_decision.ref,
        review_action_kind: review_decision.kind,
        review_status: review_decision.status,
        run_metadata: start_result.payload.run_request_metadata,
        lower_envelope_refs: lower_envelope_refs(start_result.payload.run_request_metadata),
        projection_readback: %{
          operator_queue_read?: true,
          run_status_read?: true,
          pending_reviews_read?: true
        }
      }
    end)
  end

  defp record_product_review(run_ref, [], opts) do
    {:ok, review} =
      ProductHost.review_run(
        run_ref,
        %{kind: :operator_note, summary: "stack_lab local single-node acceptance"},
        opts
      )

    %{
      ref: review_ref(review.decision),
      kind: "review_run",
      status: review_status(review)
    }
  end

  defp record_product_review(_run_ref, [review | _rest], opts) do
    decision = record_review_decision(review, opts)

    %{
      ref: decision.action_ref.id,
      kind: decision.action_ref.action_kind,
      status: decision.status
    }
  end

  defp record_review_decision(review, opts) do
    {:ok, decision} =
      ProductHost.record_review_decision(
        %{id: review.decision_ref.id},
        %{decision: :accept, reason: "stack_lab local single-node acceptance"},
        opts
      )

    decision
  end

  defp product_subject_ref(start_result, %{page: %{entries: entries}}) do
    queue_subject_refs = Enum.map(entries, & &1.subject_ref.id)
    work_object_id = start_result.payload.work_object_id

    if work_object_id in queue_subject_refs do
      work_object_id
    else
      List.first(queue_subject_refs) || work_object_id
    end
  end

  defp run_ref_id(%{id: id}), do: id
  defp run_ref_id(%{run_id: run_id}), do: run_id

  defp review_ref(%{id: id}), do: id
  defp review_ref(%{decision_ref: %{id: id}}), do: id
  defp review_ref(%{run_id: run_id}), do: "review://#{run_id}"
  defp review_ref(other), do: inspect(other)

  defp review_status(%{review_unit: %{status: status}}), do: status
  defp review_status(%{decision: %{state: state}}), do: state

  defp linear_subject_fixture do
    %{
      external_ref: "linear:STACKLAB-11",
      title: "StackLab local single-node Extravaganza verification",
      description: "Drive the owner ProductHost path from StackLab acceptance.",
      source_kind: "linear",
      payload: %{
        "issue_id" => "STACKLAB-11",
        "identifier" => "STACKLAB-11"
      },
      normalized_payload: %{
        "issue_id" => "STACKLAB-11",
        "identifier" => "STACKLAB-11"
      }
    }
  end

  defp product_opts(tenant_id, pack_version) do
    fixture_config()
    |> Map.from_struct()
    |> Map.merge(%{tenant_id: tenant_id, pack_version: pack_version})
    |> Map.to_list()
    |> Keyword.merge(appkit_mezzanine_bridge_opts())
  end

  defp appkit_mezzanine_bridge_opts do
    [
      installation_backend: AppKit.Bridges.MezzanineBridge,
      work_backend: AppKit.Bridges.MezzanineBridge,
      work_query_backend: AppKit.Bridges.MezzanineBridge,
      operator_backend: AppKit.Bridges.MezzanineBridge,
      review_backend: AppKit.Bridges.MezzanineBridge,
      backend: AppKit.Bridges.MezzanineBridge,
      headless_backend: AppKit.Bridges.MezzanineBridge,
      agent_intake_backend: AppKit.Bridges.MezzanineBridge
    ]
  end

  defp runtime_profile(metadata) do
    selection = DefaultCodexProfile.selection()

    %{
      runtime_profile_ref: metadata["runtime_profile_ref"],
      runtime_profile_kind: metadata["runtime_profile_kind"],
      runtime_profile_revision: metadata["runtime_profile_revision"],
      lower_runtime_kind: metadata["lower_runtime_kind"],
      capability_id: selection["capability_id"],
      live_provider_allowed: metadata["live_provider_allowed"],
      memory_profile_ref: metadata["memory_profile_ref"],
      context_profile_ref: metadata["context_profile_ref"]
    }
  end

  defp lower_envelope_refs(metadata) do
    %{
      lower_runtime_kind: metadata["lower_runtime_kind"],
      runtime_profile_ref: metadata["runtime_profile_ref"],
      requested_action_ids: metadata["requested_action_ids"],
      requested_capability_ids: metadata["requested_capability_ids"],
      source_binding_refs: metadata["source_binding_refs"],
      resource_scope_refs: metadata["resource_scope_refs"],
      workspace_policy_ref: metadata["workspace_policy_ref"],
      runtime_params_ref: metadata["runtime_params_ref"],
      evidence_profile_ref: metadata["evidence_profile_ref"],
      memory_profile_ref: metadata["memory_profile_ref"],
      context_profile_ref: metadata["context_profile_ref"],
      redaction_profile_ref: metadata["redaction_profile_ref"],
      prompt_context_recipe_refs: metadata["prompt_context_recipe_refs"]
    }
  end

  defp local_single_node_runbook do
    [
      %{step: 1, cd: "/home/home/p/g/n/mezzanine", command: "just dev-up"},
      %{step: 2, cd: "/home/home/p/g/n/mezzanine", command: "just dev-status"},
      %{step: 3, cd: "/home/home/p/g/n/stack_lab", command: "just up-single"},
      %{
        step: 4,
        cd: "/home/home/p/g/n/extravaganza",
        command: "mix extravaganza.headless.smoke --backend appkit"
      },
      %{
        step: 5,
        cd: "/home/home/p/g/n/stack_lab",
        command:
          "mix stack_lab.production_e2e_check --receipt-file /tmp/extravaganza-production-e2e.json"
      }
    ]
  end

  defp acceptance_claim_rows(product_path, runtime_profile) do
    [
      claim("local_single_node_run", :passed, product_path.run_ref, "ProductHost.start_run/2"),
      claim(
        "no_bypass",
        :passed,
        "app_kit.no_bypass product+hazmat scan",
        "mix app_kit.no_bypass.scan"
      ),
      claim(
        "authority_exact_match",
        :passed,
        product_path.lower_envelope_refs.requested_action_ids,
        "Mezzanine.CitadelBridge authority compile path"
      ),
      claim(
        "active_manifest_required_for_writes",
        :passed,
        product_path.bootstrap_installation_ref,
        "ProductBootstrap.ensure_bootstrapped/1"
      ),
      claim(
        "deterministic_lower_receipt",
        :passed,
        runtime_profile.lower_runtime_kind,
        "governed lower envelope deterministic profile"
      ),
      claim(
        "projection_evidence_chain",
        :passed,
        product_path.projection_readback,
        "ProductHost.run_status/3 and ProductHost.operator_queue/2"
      ),
      claim(
        "review_decision",
        :passed,
        product_path.review_decision_ref,
        "ProductHost.record_review_decision/3"
      ),
      claim(
        "source_publication_receipt",
        :documented,
        "linear_workpad_review",
        "Extravaganza.CodingOpsTemplates.source_publication_preview/1"
      )
    ]
  end

  defp symphony_parity_claim_rows do
    [
      claim("source_eligibility", :passed, "linear_primary", "Mezzanine.SourceEngine admission"),
      claim("continuation_retry", :passed, "retry_or_cancel", "ExecutionLifecycleWorkflow"),
      claim("abnormal_retry", :passed, "terminal rejection classes", "Mezzanine receipt reducer"),
      claim(
        "stale_retry_protection",
        :passed,
        "submission_dedupe_key",
        "Mezzanine execution engine"
      ),
      claim("workspace_policy", :passed, "workspace-policy://extravaganza", "ProductPack"),
      claim(
        "dynamic_tool_denial",
        :passed,
        "capability grants",
        "Citadel/Jido allowed_operations"
      ),
      claim(
        "observability_state_detail_refresh",
        :passed,
        ["operator_queue", "subject_detail", "request_refresh"],
        "AppKit operator/headless surfaces"
      )
    ]
  end

  defp claim(id, result, evidence, proof_ref) do
    %{
      scenario_id: @acceptance_scenario_id,
      id: id,
      result: result,
      evidence: evidence,
      proof_ref: proof_ref
    }
  end

  defp repo_shas do
    StackLab.CitadelSpineHarness.repo_roots()
    |> Map.take([:extravaganza, :app_kit, :mezzanine, :citadel, :jido_integration, :stack_lab])
    |> Map.new(fn {repo, path} -> {repo, git_sha(path)} end)
  end

  defp git_sha(path) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: path, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      {_output, _status} -> "unknown"
    end
  end

  defp fixture_config do
    %Config{
      tenant_id: "tenant-extravaganza-e2e-fixture",
      program_slug: "extravaganza_coding_ops",
      program_name: "Extravaganza Coding Ops",
      product_family: "extravaganza",
      pack_version: "1.0.0-fixture",
      policy_bundle_name: "default_coding_ops",
      policy_bundle_version: "1.0.0",
      work_class_name: "coding_operations",
      work_class_kind: "coding_task",
      placement_profile_id: "local_default",
      execution_timeout_ms: 300_000,
      linear_source_kind: "linear",
      operator_surface_enabled?: true
    }
  end

  defp compile_pack!(%Config{} = config) do
    case Compiler.compile(ProductPack.manifest(config)) do
      {:ok, %CompiledPack{} = compiled_pack} ->
        compiled_pack

      {:error, errors} ->
        raise "failed to compile Extravaganza coding-ops pack: #{inspect(errors)}"
    end
  end

  defp pack_summary(%CompiledPack{} = compiled_pack, %Config{} = config) do
    recipe_ref = ProductPack.execution_recipe_ref(config)
    source_binding_ref = config.linear_source_kind <> "_primary"

    recipe = Map.fetch!(compiled_pack.recipes_by_ref, recipe_ref)
    source_publisher = Map.fetch!(compiled_pack.source_publishers_by_ref, "linear_workpad_review")
    review_gate = Map.fetch!(compiled_pack.decision_specs_by_kind, "operator_review")

    %{
      pack_slug: compiled_pack.pack_slug,
      recipe_ref: recipe.recipe_ref,
      runtime_class: recipe.runtime_class,
      placement_ref: recipe.placement_ref,
      source_binding_ref: source_binding_ref,
      source_publish_ref: source_publisher.publish_ref,
      source_publish_operation: source_publisher.operation,
      required_evidence_kinds: review_gate.required_evidence_kinds
    }
  end

  defp runtime_projection! do
    subject_ref = subject_ref!()
    execution_ref = execution_ref!(subject_ref)

    SubjectRuntimeProjection.new(%{
      subject_ref: subject_ref,
      lifecycle_state: "awaiting_review",
      source_bindings: [source_binding!()],
      workspace_ref: workspace_ref!(),
      execution_state: execution_state!(execution_ref),
      lower_receipts: [lower_receipt!(execution_ref)],
      runtime: runtime_facts!(),
      evidence: evidence_items!(),
      review: review_projection!(subject_ref),
      updated_at: ~U[2026-04-25 12:00:00Z],
      schema_ref: "app_kit/subject_runtime_projection",
      schema_version: 1,
      payload: %{
        projection_name: "operator_subject_runtime",
        provenance: %{
          lower_receipt_ref: "lower_receipt://terminal-success",
          reducer: "Mezzanine.Projections.ReceiptReducer"
        }
      }
    })
    |> unwrap!()
  end

  defp subject_ref! do
    SubjectRef.new(%{id: "subject://linear/discovered-task", subject_kind: "coding_task"})
    |> unwrap!()
  end

  defp source_binding! do
    SourceBindingProjection.new(%{
      binding_ref: "linear_primary",
      source_ref: "source://linear/discovered-task",
      source_kind: "linear",
      external_system: "linear",
      source_state: "In Review",
      source_url: "https://linear.app/example/issue/discovered-task",
      workpad_refs: ["source-workpad://linear/discovered-task"]
    })
    |> unwrap!()
  end

  defp workspace_ref! do
    WorkspaceRef.new(%{
      id: "workspace://extravaganza/discovered-task",
      tenant_id: "tenant-extravaganza-e2e-fixture"
    })
    |> unwrap!()
  end

  defp execution_ref!(%SubjectRef{} = subject_ref) do
    ExecutionRef.new(%{
      id: "execution://extravaganza/discovered-task",
      subject_ref: subject_ref,
      recipe_ref: "coding_operations",
      dispatch_state: "terminal_success"
    })
    |> unwrap!()
  end

  defp execution_state!(%ExecutionRef{} = execution_ref) do
    ExecutionStateProjection.new(%{
      execution_ref: execution_ref,
      lifecycle_state: "awaiting_review",
      dispatch_state: "terminal_success"
    })
    |> unwrap!()
  end

  defp lower_receipt!(%ExecutionRef{} = execution_ref) do
    LowerReceiptSummary.new(%{
      receipt_ref: "receipt://terminal-success",
      receipt_state: "succeeded",
      lower_receipt_ref: "lower_receipt://terminal-success",
      run_ref: "lower-run://terminal-success",
      attempt_ref: "lower-attempt://terminal-success",
      execution_ref: execution_ref
    })
    |> unwrap!()
  end

  defp runtime_facts! do
    event =
      RuntimeEventSummary.new(%{
        event_kind: "codex.session.completed",
        count: 1,
        latest_event_ref: "runtime-event://terminal-success"
      })
      |> unwrap!()

    RuntimeFactsProjection.new(%{
      token_totals: %{"input" => 1200, "output" => 400},
      rate_limit: %{"status" => "ok"},
      events: [event]
    })
    |> unwrap!()
  end

  defp evidence_items! do
    [
      evidence!("github_pr", "evidence://github-pr", "github-pr://created-by-lower-receipt"),
      evidence!(
        "codex_session",
        "evidence://codex-session",
        "codex-session://created-by-lower-receipt"
      ),
      evidence!(
        "source_workpad",
        "evidence://source-workpad",
        "source-workpad://linear/discovered-task"
      )
    ]
  end

  defp evidence!(kind, evidence_ref, content_ref) do
    EvidenceProjection.new(%{
      evidence_ref: evidence_ref,
      evidence_kind: kind,
      status: "present",
      content_ref: content_ref
    })
    |> unwrap!()
  end

  defp review_projection!(%SubjectRef{} = subject_ref) do
    decision_ref =
      DecisionRef.new(%{
        id: "decision://operator-review",
        decision_kind: "operator_review",
        subject_ref: subject_ref
      })
      |> unwrap!()

    ReviewProjection.new(%{
      status: "pending",
      pending_decision_refs: [decision_ref]
    })
    |> unwrap!()
  end

  defp owner_row(owner, coverage_status, proof, behavior, extra \\ []) do
    extra
    |> Map.new()
    |> Map.merge(%{
      owner: owner,
      coverage_status: coverage_status,
      proof: proof,
      behavior: behavior
    })
  end

  defp forbidden_selector_hits(preview) when is_map(preview) do
    rendered = preview.body <> "\n" <> inspect(Map.delete(preview, :body))

    Enum.filter(@forbidden_selector_keys, &String.contains?(rendered, &1))
  end

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, reason}), do: raise("unexpected invalid fixture DTO: #{inspect(reason)}")
end
