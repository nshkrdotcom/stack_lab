defmodule StackLab.CitadelSpineHarness.ExtravaganzaNonUiLaneTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "scenario exposes the deterministic non-UI Extravaganza lane proof" do
    scenario = CitadelSpineHarness.extravaganza_non_ui_lane_scenario()

    assert scenario.name == :extravaganza_non_ui_lane
    assert scenario.owner_repo == :stack_lab
    assert scenario.product_repo == :extravaganza

    assert scenario.cases == %{
             deterministic_full_lane: %{kind: :deterministic_full_lane},
             local_single_node_verification: %{kind: :owner_product_path},
             failure_matrix: %{kind: :failure_matrix},
             live_readiness: %{kind: :live_readiness}
           }
  end

  test "deterministic full lane carries identity through AppKit DTOs without static selectors" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_extravaganza_non_ui_lane(:deterministic_full_lane)

    assert result.case == :deterministic_full_lane
    assert result.acceptance_kind == :credential_free_internal_contract

    assert result.path == [
             :linear_source_admission,
             :workspace_allocation,
             :codex_session_receipt,
             :github_pr_evidence,
             :operator_review,
             :linear_terminal_publication_readback
           ]

    assert result.pack.recipe_ref == "coding_operations"
    assert result.pack.source_binding_ref == "linear_primary"
    assert result.pack.source_publish_ref == "linear_workpad_review"
    assert result.pack.required_evidence_kinds == ["codex_session", "github_pr", "source_workpad"]

    assert result.local_worker.placement == :local_worker
    assert result.remote_worker.contract_status == :deterministic_ssh_exec_contract

    assert result.runtime.codex_event_kind == "codex.session.completed"

    assert result.evidence.refs == [
             "evidence://github-pr",
             "evidence://codex-session",
             "evidence://source-workpad"
           ]

    assert result.review.pending_decision_refs == ["decision://operator-review"]

    assert result.source_publication.operation == :update_comment
    assert result.source_publication.source_binding_ref == "linear_primary"
    assert result.source_publication.lower_receipt_refs == ["receipt://terminal-success"]
    assert String.contains?(result.source_publication.body, "Operator Review Workpad")
    assert String.contains?(result.source_publication.body, "github_pr")
    assert String.contains?(result.source_publication.body, "codex.session.completed=1")

    assert result.identity_lifecycle.provider_objects ==
             :source_admission_provider_create_outputs_workflow_state_and_receipts

    assert result.static_selector_keys_present? == false
    assert result.forbidden_selector_hits == []
  end

  @tag timeout: 300_000
  test "local single-node verification drives the owner ProductHost path and emits acceptance rows" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_extravaganza_non_ui_lane(
               :local_single_node_verification
             )

    assert result.case == :local_single_node_verification
    assert result.scenario_id == "extravaganza.local_single_node.v1"
    assert result.acceptance_kind == :local_single_node_owner_product_path
    assert result.provider_smoke_scope == :provider_reachability_only
    assert result.stack_lab_role == :external_acceptance_harness_not_product_runtime

    assert result.product_path.run_state == :waiting_review
    assert result.product_path.workflow_dispatch_state == "queued"
    assert String.starts_with?(result.product_path.workflow_start_ref, "workflow-start-outbox://")
    assert result.product_path.review_required == true
    assert result.product_path.review_status in [:accepted, :approved, :completed]
    assert result.product_path.review_action_kind in ["review_run", "review_accept"]
    assert result.product_path.subject_ref in result.product_path.queue_subject_refs

    assert result.product_path.appkit_entrypoints == [
             "Extravaganza.ProductHost.start_run/2",
             "AppKit.WorkSurface.ingest_subject/3",
             "AppKit.WorkControl.start_run/3"
           ]

    assert result.runtime_profile.lower_runtime_kind == "codex_session"
    assert result.runtime_profile.runtime_profile_kind == "temporal_local"
    assert result.runtime_profile.live_provider_allowed == false
    assert result.product_path.lower_envelope_refs.runtime_profile_ref == "codex_session"
    assert "codex.session.turn" in result.product_path.lower_envelope_refs.requested_action_ids

    assert "linear.comments.update" in result.product_path.lower_envelope_refs.requested_capability_ids

    assert Map.keys(result.repo_shas) |> Enum.sort() == [
             :app_kit,
             :citadel,
             :extravaganza,
             :jido_integration,
             :mezzanine,
             :stack_lab
           ]

    assert Enum.all?(result.repo_shas, fn {_repo, sha} -> is_binary(sha) and sha != "" end)

    claim_ids = Enum.map(result.acceptance_claim_rows, & &1.id)

    assert claim_ids == [
             "local_single_node_run",
             "no_bypass",
             "authority_exact_match",
             "active_manifest_required_for_writes",
             "deterministic_lower_receipt",
             "projection_evidence_chain",
             "review_decision",
             "source_publication_receipt"
           ]

    assert Enum.all?(result.acceptance_claim_rows, &(&1.scenario_id == result.scenario_id))

    parity_ids = Enum.map(result.symphony_parity_claim_rows, & &1.id)

    assert parity_ids == [
             "source_eligibility",
             "continuation_retry",
             "abnormal_retry",
             "stale_retry_protection",
             "workspace_policy",
             "dynamic_tool_denial",
             "observability_state_detail_refresh"
           ]

    assert Enum.any?(
             result.runbook,
             &(&1.command ==
                 "mix stack_lab.production_e2e_check --receipt-file /tmp/extravaganza-production-e2e.json")
           )
  end

  test "failure matrix maps every required M10 variant to owner coverage" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_extravaganza_non_ui_lane(:failure_matrix)

    assert result.case == :failure_matrix

    required = [
      :terminal_source_cleanup,
      :source_reassignment,
      :missing_source_item,
      :blocker_after_poll,
      :stall_timeout,
      :lower_process_failure,
      :approval_required,
      :input_required,
      :malformed_protocol,
      :cancellation,
      :restart_replay
    ]

    assert Map.keys(result.variants) |> Enum.sort() == Enum.sort(required)

    assert result.variants.approval_required.expected_subject_state == "failed"
    assert result.variants.input_required.expected_subject_state == "blocked"
    assert result.variants.restart_replay.owner == :stack_lab

    assert Enum.all?(result.variants, fn {_variant, row} ->
             row.coverage_status in [:owner_test_green, :deterministic_contract_green]
           end)
  end

  test "live readiness exposes the provider smoke command without accepting static provider ids" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_extravaganza_non_ui_lane(:live_readiness)

    assert result.case == :live_readiness
    assert result.default_ci_requires_live? == false
    assert result.live_command_contract.command == "mix stack_lab.provider_smoke_check"
    assert result.live_command_contract.secret_bootstrap == "/home/home/scripts/with_bash_secrets"
    assert result.live_command_contract.non_secret_inputs == :typed_cli_or_control_api
    assert result.live_command_contract.github_write_target == "nshkrdotcom/test"
    assert result.live_command_contract.static_provider_selector_acceptance? == false

    assert result.provider_smoke_check_steps == [
             :internal_appkit_projection,
             :temporal_status,
             :linear_terminal_publication,
             :github_disposable_pr,
             :codex_session_turn,
             :receipt_write
           ]

    assert result.current_live_status == :provider_smoke_check_available
  end
end
