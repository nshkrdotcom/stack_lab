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

  alias Extravaganza.{CodingOpsTemplates, Config, ProductPack}
  alias Mezzanine.Pack.{CompiledPack, Compiler}

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

  @spec run_case(:deterministic_full_lane | :failure_matrix | :live_readiness) ::
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
       current_live_status: :dynamic_live_e2e_command_available,
       default_ci_requires_live?: false,
       live_command_contract: %{
         command: "mix stack_lab.extravaganza.live_e2e",
         secret_bootstrap: "/home/home/scripts/with_bash_secrets",
         non_secret_inputs: :typed_cli_or_control_api,
         credential_flow: :jido_connection_or_credential_lease,
         provider_identity:
           :connector_discovery_create_outputs_source_admission_workflow_state_or_receipts,
         static_provider_selector_acceptance?: false,
         github_write_target: "nshkrdotcom/test"
       },
       dynamic_live_e2e_steps: [
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
      updated_at: ~U[2026-04-25 12:00:00Z]
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
