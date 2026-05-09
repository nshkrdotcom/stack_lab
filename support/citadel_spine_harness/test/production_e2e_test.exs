defmodule StackLab.CitadelSpineHarness.ProductionE2ETest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "scenario is a separate true production-path acceptance from provider smoke" do
    scenario = CitadelSpineHarness.production_e2e_scenario()

    assert scenario.name == :production_e2e
    assert scenario.owner_repo == :stack_lab
    assert scenario.product_repo == :extravaganza
    assert scenario.schema_name == "production_e2e_receipt_v1.json"
    assert scenario.provider_smoke_schema_name == "provider_smoke_receipt_v1.json"

    assert scenario.temporal == %{
             target: "127.0.0.1:7233",
             namespace: "default",
             mode: :shared_dev_substrate,
             health_command: %{
               cd: "/home/home/p/g/n/mezzanine",
               command: "just",
               args: ["dev-status"]
             },
             forbidden_commands: [
               "temporal server start-dev",
               "just dev-down",
               "just temporal-reset-confirm"
             ]
           }

    assert scenario.cases.deterministic_offline_fixture.kind == :true_production_path

    assert scenario.cases.live_provider_mutation.requires_explicit_authorization ==
             :live_provider_mutation_authorized?

    assert scenario.cases.temporal_unavailable.kind == :fail_closed_guard
  end

  test "deterministic production E2E proves the full product path and durable receipt chain" do
    command_runner = fn command, args, opts ->
      assert command == "just"
      assert args == ["dev-status"]
      assert opts[:cd] == "/home/home/p/g/n/mezzanine"
      refute Enum.any?(args, &(&1 in ["dev-down", "temporal-reset-confirm"]))

      {:ok, "SERVING"}
    end

    assert {:ok, receipt} =
             CitadelSpineHarness.exercise_production_e2e(
               :deterministic_offline_fixture,
               command_runner: command_runner,
               env: %{}
             )

    assert receipt.schema_name == "production_e2e_receipt_v1.json"
    assert receipt.scenario_id == "extravaganza.production_e2e.v1"
    assert receipt.forbidden_provider_smoke_schema == "provider_smoke_receipt_v1.json"
    assert receipt.proof_class == "true_production_e2e"
    assert receipt.production_e2e == true
    assert receipt.live_provider_mutation == false
    assert receipt.live_mutation_leg == :deterministic_offline_fixture
    assert receipt.cleanup.stop_or_reset_temporal == false

    refute Map.has_key?(receipt, :provider_smoke_steps)
    refute Map.has_key?(receipt, :provider_smoke_result)

    assert receipt.path == [:extravaganza, :appkit, :mezzanine, :citadel, :jido_integration]
    assert receipt.trigger.starts_at == :product_appkit_boundary
    assert receipt.runtime_profile.lower_runtime_kind == "deterministic_fixture"
    assert receipt.runtime_profile.runtime_profile_kind == "temporal_local"
    assert receipt.runtime_profile.live_provider_allowed == false

    assert Map.keys(receipt.repo_shas) |> Enum.sort() == [
             :app_kit,
             :citadel,
             :extravaganza,
             :jido_integration,
             :mezzanine,
             :stack_lab
           ]

    assert receipt.trigger.appkit_calls == [
             :work_surface_ingest_subject_3,
             :work_control_start_run_3,
             :work_surface_get_runtime_projection_3
           ]

    assert receipt.host_composition.appkit_backend == AppKit.Bridges.MezzanineBridge
    assert receipt.host_composition.backend_configured? == true
    assert receipt.host_composition.bypasses_citadel? == false

    assert receipt.temporal.status == :reachable
    assert receipt.temporal.target == "127.0.0.1:7233"
    assert receipt.temporal.namespace == "default"
    assert receipt.temporal.mode == :shared_dev_substrate

    assert receipt.appkit.work_surface_ingested? == true
    assert receipt.appkit.work_control_started? == true
    assert receipt.appkit.runtime_projection_readback? == true
    assert receipt.appkit.runtime_projection_source == :reducer_owned_projection
    assert receipt.appkit.dto.lower_receipt_ref == receipt.jido_integration.lower_receipt_ref

    assert String.contains?(receipt.mezzanine.subject_ref, "mezzanine://subjects/")
    assert String.contains?(receipt.mezzanine.execution_ref, "mezzanine://executions/")
    assert String.contains?(receipt.mezzanine.workflow_outbox_ref, "mezzanine://workflow-outbox/")
    assert String.contains?(receipt.mezzanine.workflow_execution_ref, "temporal://default/")

    assert String.contains?(
             receipt.citadel.permission_decision_ref,
             "citadel://authority-decisions/"
           )

    assert String.contains?(
             receipt.citadel.execution_governance_ref,
             "citadel://execution-governance/"
           )

    assert receipt.citadel.decision == :allow

    assert String.contains?(receipt.jido_integration.lower_submission_ref, "jido://submissions/")
    assert receipt.jido_integration.carries_citadel_authority? == true
    assert receipt.jido_integration.lower_runtime_kind == "deterministic_fixture"
    assert receipt.jido_integration.provider_effect_live? == false

    assert receipt.jido_integration.provider_object_refs == [
             "fixture://github/pr/production-e2e",
             "fixture://linear/workpad/production-e2e"
           ]

    assert receipt.lower_receipt.receipt_state == :succeeded
    assert receipt.lower_receipt.lower_runtime_kind == "deterministic_fixture"

    assert receipt.lower_receipt.provider_created_refs ==
             receipt.jido_integration.provider_object_refs

    assert receipt.lower_receipt.evidence_artifact_refs == receipt.evidence.durable_refs

    assert receipt.reducer_projection.reducer == Mezzanine.Projections.ReceiptReducer
    assert receipt.reducer_projection.data_available_to_appkit? == true

    assert receipt.reducer_projection.lower_receipt_ref ==
             receipt.jido_integration.lower_receipt_ref

    assert receipt.extravaganza.readback_source == :appkit_runtime_projection_dto
    assert receipt.extravaganza.rendered? == true
    assert receipt.extravaganza.provider_smoke_result_consumed? == false

    assert receipt.evidence.required == ["github_pr", "codex_session", "source_workpad"]

    assert receipt.evidence.durable_refs == [
             "evidence://github-pr/production-e2e",
             "evidence://codex-session/production-e2e",
             "evidence://source-workpad/production-e2e"
           ]

    assert receipt.evidence.requirements_met? == true
    assert receipt.evidence.placeholder_artifact_refs? == false
    assert receipt.receipt_structural_difference_from_provider_smoke == true

    assert receipt.governed_lower_envelope.lower_runtime_kind == "deterministic_fixture"
    assert receipt.governed_lower_envelope.capability_id == "codex.session.turn"

    assert "source_binding://linear_primary" in receipt.governed_lower_envelope.resource_scope_refs

    assert Enum.map(receipt.acceptance_claim_rows, & &1.id) == [
             "local_single_node_run",
             "no_bypass",
             "authority_exact_match",
             "active_manifest_required_for_writes",
             "deterministic_lower_receipt",
             "projection_evidence_chain",
             "review_decision",
             "source_publication_receipt"
           ]

    assert Enum.map(receipt.symphony_parity_claim_rows, & &1.id) == [
             "source_eligibility",
             "continuation_retry",
             "abnormal_retry",
             "stale_retry_protection",
             "workspace_policy",
             "dynamic_tool_denial",
             "observability_state_detail_refresh"
           ]
  end

  test "live provider mutation is fail-closed unless explicitly enabled" do
    command_runner = fn _command, _args, _opts -> {:ok, "SERVING"} end

    assert {:error, {:live_provider_mutation_disabled, _message}} =
             CitadelSpineHarness.exercise_production_e2e(
               :live_provider_mutation,
               command_runner: command_runner,
               env: %{}
             )
  end

  test "ambient env map cannot authorize live provider mutation" do
    command_runner = fn _command, _args, _opts -> {:ok, "SERVING"} end

    assert {:error, {:live_provider_mutation_disabled, _message}} =
             CitadelSpineHarness.exercise_production_e2e(
               :live_provider_mutation,
               command_runner: command_runner,
               env: %{"EXTRAVAGANZA_LIVE_E2E" => "1"}
             )
  end

  test "live provider mutation leg requires explicit option and carries live provider refs" do
    command_runner = fn _command, _args, _opts -> {:ok, "SERVING"} end

    assert {:ok, receipt} =
             CitadelSpineHarness.exercise_production_e2e(
               :live_provider_mutation,
               command_runner: command_runner,
               live_provider_mutation_authorized?: true
             )

    assert receipt.live_provider_mutation == true
    assert receipt.live_mutation_leg == :live_provider_mutation
    assert receipt.jido_integration.provider_effect_live? == true
    assert receipt.cleanup.provider_cleanup == :delete_disposable_provider_objects

    assert receipt.jido_integration.provider_object_refs == [
             "github://nshkrdotcom/test/pulls/created-by-production-e2e",
             "linear://comments/created-by-production-e2e"
           ]
  end

  test "temporal health failure produces a clear unavailable error without starting a cluster" do
    command_runner = fn command, args, opts ->
      assert command == "just"
      assert args == ["dev-status"]
      assert opts[:cd] == "/home/home/p/g/n/mezzanine"

      {:ok, "NOT SERVING"}
    end

    assert {:error, {:temporal_unavailable, error}} =
             CitadelSpineHarness.exercise_production_e2e(
               :deterministic_offline_fixture,
               command_runner: command_runner,
               env: %{}
             )

    assert String.contains?(error.operator_action, "just dev-up")
    assert String.contains?(error.operator_action, "do not start an ephemeral Temporal cluster")
  end

  test "production E2E runbook stays aligned with the root StackLab command" do
    runbook =
      StackLab.CitadelSpineHarness.repo_roots().stack_lab
      |> Path.join("docs/runbooks/production_e2e.md")
      |> File.read!()

    assert String.contains?(runbook, "just dev-up")
    assert String.contains?(runbook, "just dev-status")
    assert String.contains?(runbook, "just up-single")
    assert String.contains?(runbook, "mix extravaganza.headless.smoke --backend appkit")
    assert String.contains?(runbook, "mix stack_lab.production_e2e_check")
    assert String.contains?(runbook, "--receipt-file /tmp/extravaganza-production-e2e.json")
    assert String.contains?(runbook, "Provider smoke remains separate")
  end
end
