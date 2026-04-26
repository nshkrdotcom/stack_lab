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
    assert result.source_publication.body =~ "Operator Review Workpad"
    assert result.source_publication.body =~ "github_pr"
    assert result.source_publication.body =~ "codex.session.completed=1"

    assert result.identity_lifecycle.provider_objects ==
             :source_admission_provider_create_outputs_workflow_state_and_receipts

    assert result.static_selector_keys_present? == false
    assert result.forbidden_selector_hits == []
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

  test "live readiness reports explicit blockers instead of accepting static provider ids" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_extravaganza_non_ui_lane(:live_readiness)

    assert result.case == :live_readiness
    assert result.default_ci_requires_live? == false
    assert result.live_command_contract.secret_bootstrap == "/home/home/scripts/with_bash_secrets"
    assert result.live_command_contract.non_secret_inputs == :typed_cli_or_control_api
    assert result.live_command_contract.static_provider_selector_acceptance? == false

    assert :github_disposable_pr_creation_or_discovery in result.blockers
    assert :full_linear_to_github_to_linear_live_workflow in result.blockers
    assert result.current_live_status == :blocked_for_full_provider_e2e
  end
end
