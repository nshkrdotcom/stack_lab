defmodule StackLab.CitadelSpineHarness.PrelimServiceModeTest do
  use ExUnit.Case, async: true

  @moduletag timeout: 300_000

  alias StackLab.CitadelSpineHarness

  test "PRELIM service-mode contract join exposes the M3 proof case" do
    scenario = CitadelSpineHarness.prelim_service_mode_scenario()

    assert scenario.name == :phase5prelim_service_mode_contract_join
    assert scenario.runbook == "phase5prelim_service_mode_contract_join.md"
    assert File.exists?(scenario.compose)

    assert scenario.cases == %{
             m3_contract_join: %{
               kind: :m3_contract_join,
               phase: "5PRELIM",
               milestone: "M3"
             },
             m5_service_profile_bootstrap: %{
               kind: :m5_service_profile_bootstrap,
               phase: "5PRELIM",
               milestone: "M5"
             },
             m5_governed_smoke: %{
               kind: :m5_governed_smoke,
               phase: "5PRELIM",
               milestone: "M5"
             },
             m5_pressure_and_negatives: %{
               kind: :m5_pressure_and_negatives,
               phase: "5PRELIM",
               milestone: "M5"
             },
             m6_evidence_report: %{
               kind: :m6_evidence_report,
               phase: "5PRELIM",
               milestone: "M6"
             }
           }
  end

  test "M3 contract join requires Temporal and joins owner-populated evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m3_contract_join,
               temporal_runner: &serving_temporal/3
             )

    assert result.case == :m3_contract_join
    assert result.service_mode_gate.temporal_required?
    assert result.service_mode_gate.non_temporal_classification == :lower_runtime_smoke_only
    assert result.service_mode_gate.owner_contracts_joined?

    assert result.temporal.substrate.status == :serving
    assert result.temporal.substrate.checked_by == "just dev-status"
    assert result.temporal.workflow.module == Mezzanine.Workflows.ExecutionAttempt
    assert result.temporal.workflow.task_queue == "mezzanine.hazmat"
    assert result.temporal.workflow.execution_attempt_registered?
    assert :compile_citadel_authority in result.temporal.workflow.activity_sequence
    assert :submit_jido_lower_run in result.temporal.workflow.activity_sequence

    assert result.temporal.oban_cutover.retained_queues == [
             :claim_check_gc,
             :workflow_signal_outbox,
             :workflow_start_outbox
           ]

    assert result.temporal.oban_cutover.invalid_queue_configs == []
    assert result.temporal.oban_cutover.invalid_saga_references == []
    assert result.temporal.oban_cutover.temporalex_boundary_violations == []
    refute result.temporal.projection_drift_negatives.workflow_start_outbox_bypass.accepted?

    assert result.workload.work_class.name == "coding_operations"
    assert result.workload.work_class.kind == "coding_task"
    assert result.workload.pack.pack_slug == "extravaganza_coding_ops"
    assert result.workload.pack.subject_kind == "coding_task"
    assert result.workload.lifecycle.after_execution_completed == "awaiting_review"
    assert result.workload.lifecycle.review_gate == :operator_review
    assert result.workload.lifecycle.after_review_accept == "completed"
    assert result.workload.lifecycle.terminal_after_accept?

    assert result.authority.authority_decision.contract_version == "v1"
    assert result.authority.authorization_scope.tenant_id == "tenant-prelim"
    assert result.authority.lower_tenant_scope.tenant_id == "tenant-prelim"
    assert result.authority.lower_read.authorized_operation == :fetch_run
    assert result.authority.lower_read.unauthorized_error == :unauthorized_lower_read
    refute result.authority.negative_failures.missing_authority_tenant == :unexpected_acceptance

    refute result.authority.negative_failures.missing_mezzanine_scope_tenant ==
             :unexpected_acceptance

    assert result.semantic.context_provenance.semantic_ref == "semantic://prelim/turn-1"
    assert result.semantic.read_only_context_adapter.mutation_permissions == []
    assert "lower://*" in result.semantic.read_only_context_adapter.denied_write_resources
    assert result.semantic.privacy_redaction.public_payload.prompt_hash =~ "sha256:"
    assert result.semantic.suppression_visibility.operator_visibility == "visible"
    assert result.semantic.semantic_failure.kind == :semantic_insufficient_context
    assert result.semantic.semantic_failure.retry_class == :clarification_required
    assert result.semantic.reply_publication.phase == :final
    assert result.semantic.reply_publication.state == :published
    assert result.semantic.durability.semantic_failure_retry_classes == [:clarification_required]

    assert result.semantic.durability.duplicate_publication_ids == [
             result.semantic.durability.duplicate_replayed_publication_id
           ]

    assert result.semantic.negative_failures.raw_public_payload ==
             {:public_payload_leak, :raw_prompt}

    assert result.semantic.negative_failures.context_adapter_write_permission ==
             {:read_only_violation, :mutation_permissions}

    refute result.semantic.negative_failures.missing_semantic_failure_tenant ==
             :unexpected_acceptance
  end

  test "M5 service profile bootstrap installs owner-backed profiles and cleans up" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m5_service_profile_bootstrap,
               temporal_runner: &serving_temporal/3
             )

    assert result.case == :m5_service_profile_bootstrap
    assert result.release_manifest_ref == "phase5prelim-m5-service-profile-bootstrap"
    assert result.service_mode_gate.temporal_required?
    assert result.service_mode_gate.profile_installation_required?
    assert result.service_mode_gate.owner_contracts_consumed?
    assert result.service_mode_gate.provider_local_mock_selectors_denied?

    assert result.temporal.substrate.status == :serving
    assert result.temporal.worker_health.status == :healthy
    assert result.temporal.worker_health.task_queue == "mezzanine.hazmat"
    assert result.temporal.worker_health.execution_attempt_registered?

    profile = result.service_profiles.profile
    assert profile.profile_ref == "service-simulation-profile://phase5prelim/m5/bootstrap"
    assert profile.egress_policy == :deny_real_provider_and_saas
    assert profile.artifact_policy.raw_prompts == :deny
    assert profile.input_fingerprint_policy.mode == :transient_hash

    assert profile.adapter_profile_refs.cli_core ==
             "adapter-profile://cli_subprocess_core/6ef1c72"

    assert profile.adapter_profile_refs.asm == "adapter-profile://agent_session_manager/eed6b45"
    assert profile.adapter_profile_refs.rest == "adapter-profile://pristine/83e8c04"
    assert profile.adapter_profile_refs.graphql == "adapter-profile://prismatic/5bd56b0"

    assert profile.adapter_profile_refs.self_hosted ==
             "adapter-profile://self_hosted_inference_core/79a5643"

    assert Enum.sort(Map.keys(result.owner_evidence)) == [
             "P5P-011",
             "P5P-012",
             "P5P-013",
             "P5P-014"
           ]

    assert result.owner_evidence["P5P-014"].source_commits == ["79a5643"]
    assert "6ef1c72" in result.owner_evidence["P5P-012"].source_commits

    assert result.service_profiles.installed.installed_count == 1

    assert result.service_profiles.installed.owner_evidence_ids == [
             "P5P-011",
             "P5P-012",
             "P5P-013",
             "P5P-014"
           ]

    assert result.service_profiles.cleanup.removed_count == 1
    assert result.service_profiles.cleanup.cleanup_complete?

    assert result.negative_failures.missing_owner_evidence ==
             {:missing_owner_evidence, ["P5P-014"]}

    assert result.negative_failures.provider_local_mock_selector ==
             {:provider_local_mock_selector_forbidden, "GEMINI_CLI_PATH"}

    assert result.negative_failures.invalid_egress_policy ==
             {:invalid_egress_policy, :allow_real_provider_fallback}
  end

  test "M5 governed smoke workload drives one coding task through owner paths" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m5_governed_smoke,
               temporal_runner: &serving_temporal/3
             )

    assert result.case == :m5_governed_smoke
    assert result.release_manifest_ref == "phase5prelim-m5-governed-smoke"

    assert result.service_mode_gate.temporal_required?
    assert result.service_mode_gate.governed_subject_required?
    assert result.service_mode_gate.review_gate_required?
    assert result.service_mode_gate.lower_trace_required?
    assert result.service_mode_gate.semantic_hop_required?
    assert result.service_mode_gate.owner_contracts_consumed?

    assert result.temporal.substrate.status == :serving
    assert result.temporal.substrate.checked_by == "just dev-status"
    assert result.temporal.worker_health.status == :healthy

    assert result.temporal.worker_health.instance_base ==
             Mezzanine.WorkflowRuntime.PrelimTemporal

    assert Mezzanine.Workflows.ExecutionAttempt in result.temporal.worker_health.workflows
    assert result.temporal.worker_health.execution_attempt_registered?

    assert result.service_profiles.installed.installed_count == 1
    assert result.service_profiles.cleanup.cleanup_complete?

    assert result.service_profiles.profile.profile_ref ==
             "service-simulation-profile://phase5prelim/m5/bootstrap"

    smoke = result.governed_smoke

    assert smoke.run_shape.tenant_count == 1
    assert smoke.run_shape.agent_count == 1
    assert smoke.run_shape.work_item_count == 1
    assert smoke.run_shape.max_concurrency == 1
    assert smoke.run_shape.no_slo_claim?

    assert smoke.workload_profile.profile_ref ==
             "service-simulation-profile://phase5prelim/m5/bootstrap"

    assert smoke.workload_profile.subject_kind == "coding_task"
    assert smoke.workload_profile.lifecycle_after_execution == "awaiting_review"
    assert smoke.workload_profile.lifecycle_after_review == "completed"

    assert smoke.governed_subject.source_kind == "linear"
    assert smoke.governed_subject.subject_kind == "coding_task"
    assert smoke.governed_subject.lifecycle_state_before_pause == "awaiting_review"
    assert smoke.governed_subject.lifecycle_state_after_review == "awaiting_review"

    assert is_binary(smoke.agent_execution.run_ref)
    assert is_binary(smoke.agent_execution.execution_ref)
    assert String.starts_with?(smoke.agent_execution.submission_receipt_ref, "submission://")
    assert "lower_run_status" in smoke.agent_execution.trace_step_sources

    assert smoke.review_gate.status_before == "pending"
    assert smoke.review_gate.status_after == "accepted"
    assert smoke.review_gate.action_kind == "review_accept"
    assert smoke.review_gate.decision_ref in smoke.review_gate.pending_ids_before
    refute smoke.review_gate.decision_ref in smoke.review_gate.pending_ids_after

    assert smoke.lower_access.no_real_provider_spend?
    assert smoke.lower_access.post_pause_read.code == :lease_invalidated
    assert smoke.lower_access.post_pause_read.reason == "subject_paused"
    assert smoke.lower_access.post_pause_stream.code == :lease_invalidated
    assert smoke.lower_access.post_pause_stream.reason == "subject_paused"

    assert smoke.owner_path_refs.appkit_tenant_ref == "tenant-reviewable-connector-automation"

    assert String.starts_with?(
             smoke.owner_path_refs.authorization_scope_ref,
             "authorization-scope://"
           )

    assert smoke.owner_path_refs.semantic_ref == "semantic://prelim/turn-1"
    assert is_binary(smoke.owner_path_refs.semantic_failure_ref)

    assert smoke.owner_path_refs.lower_submission_ref ==
             smoke.agent_execution.submission_receipt_ref

    assert result.negative_failures.missing_review_gate == :invalid_governed_smoke_evidence

    assert result.negative_failures.missing_lower_trace ==
             {:missing_trace_source, "lower_run_status"}

    assert result.negative_failures.non_coding_subject ==
             {:invalid_subject_kind, "expense_request"}
  end

  test "M5 pressure and negatives records bounded local pressure without provider spend" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m5_pressure_and_negatives,
               temporal_runner: &serving_temporal/3
             )

    assert result.case == :m5_pressure_and_negatives
    assert result.release_manifest_ref == "phase5prelim-m5-pressure-and-negatives"

    assert result.service_mode_gate.temporal_required?
    assert result.service_mode_gate.bounded_pressure_required?
    assert result.service_mode_gate.max_concurrency_enforced?
    assert result.service_mode_gate.no_slo_claim?
    assert result.service_mode_gate.no_real_provider_spend?
    assert result.service_mode_gate.fault_matrix_required?
    assert result.service_mode_gate.tenant_authority_no_bypass_required?
    assert result.service_mode_gate.owner_contracts_consumed?

    pressure = result.pressure

    assert pressure.run_shape.tenant_count == 3
    assert pressure.run_shape.agents_per_tenant == 4
    assert pressure.run_shape.agent_count == 12
    assert pressure.run_shape.work_items_per_agent == 2
    assert pressure.run_shape.work_item_count == 24
    assert pressure.run_shape.max_concurrency == 6
    assert pressure.run_shape.no_slo_claim?

    assert pressure.dispatch_window.scheduler == :bounded_async_stream
    assert pressure.dispatch_window.admitted_work_items == 24
    assert pressure.dispatch_window.max_in_flight == 6
    refute pressure.dispatch_window.slo_claim?

    assert pressure.cost.total_cost_units == 0
    assert pressure.cost.no_real_provider_spend?
    assert pressure.cost.no_real_saas_writes?

    assert pressure.owner_path_refs.semantic_ref == "semantic://prelim/turn-1"

    assert String.starts_with?(
             pressure.owner_path_refs.authorization_scope_ref,
             "authorization-scope://"
           )

    work_items =
      pressure.tenants
      |> Enum.flat_map(& &1.agents)
      |> Enum.flat_map(& &1.work_items)

    assert length(pressure.tenants) == 3
    assert length(work_items) == 24
    assert Enum.all?(work_items, &(&1.subject_kind == "coding_task"))
    assert Enum.all?(work_items, &(&1.cost_units == 0))
    refute Enum.any?(work_items, & &1.provider_egress_allowed?)

    assert Enum.all?(
             work_items,
             &String.starts_with?(&1.authorization_scope_ref, "authorization-scope://")
           )

    assert Enum.all?(work_items, &String.starts_with?(&1.lower_submission_ref, "submission://"))

    matrix = result.budget_cost_fault_matrix

    assert matrix.budget.budget_ref == "budget://phase5prelim/local-no-spend"
    assert matrix.budget.total_cost_units == 0
    assert :runtime_admission in matrix.budget.enforcement_points
    refute matrix.cost.real_provider_spend?
    assert matrix.cost.provider_billable_units == 0

    assert Enum.map(matrix.faults, & &1.fault_class) |> Enum.sort() ==
             [:malformed_response, :partial_response, :rate_limit, :timeout, :unavailable_meter]

    assert Enum.all?(matrix.faults, &(&1.injected_at == :configured_adapter_boundary))
    refute Enum.any?(matrix.faults, & &1.lower_side_effects?)

    assert result.negative_failures.cross_tenant_lower_read == :unauthorized_lower_read
    refute result.negative_failures.missing_authority_tenant == :unexpected_acceptance
    refute result.negative_failures.missing_authorization_scope == :unexpected_acceptance
    refute result.negative_failures.missing_lower_tenant_scope == :unexpected_acceptance
    assert result.negative_failures.missing_budget_ref == :missing_budget_ref
    assert result.negative_failures.max_concurrency_breach == {:max_concurrency_exceeded, 7}
    assert result.negative_failures.real_provider_spend == :real_provider_spend_allowed
    assert result.negative_failures.direct_lower_shortcut == :direct_lower_shortcut
    assert result.negative_failures.missing_semantic_boundary == :missing_semantic_boundary
  end

  test "M6 evidence report validates service-mode refs and privacy boundaries" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m6_evidence_report,
               temporal_runner: &serving_temporal/3
             )

    assert result.case == :m6_evidence_report
    assert result.release_manifest_ref == "phase5prelim-m6-evidence-report"
    assert result.schema_ref == "contracts/prelim_evidence_report.schema.json"
    assert result.validation.status == :passed

    report = result.report

    assert report.schema == "phase5prelim_evidence_report.v1"
    assert report.packet == "ecosystem_buildout_phase5PRELIM"
    assert report.substrate.temporal_required

    assert "workflow://Mezzanine.Workflows.ExecutionAttempt" in report.substrate.worker_health_refs

    assert report.workload_profile.subject_kind == "coding_task"
    assert report.workload_profile.tenant_count == 3
    assert report.workload_profile.agent_count == 12
    assert report.workload_profile.runs_per_agent == 2
    assert report.workload_profile.max_concurrency == 6
    assert report.workload_profile.review_gate_ref == "operator_review"

    assert Enum.find(report.scenario_results, &(&1.scenario_id == "P5P-009"))
    assert Enum.all?(report.scenario_results, &(&1.status == "passed"))
    assert Enum.all?(report.scenario_results, &(&1.positive_evidence_ref != ""))
    assert Enum.all?(report.scenario_results, &(&1.negative_evidence_ref != ""))

    assert length(report.authority.tenant_refs) == 3
    assert "authority-decision-prelim" in report.authority.authority_decision_refs

    assert Enum.any?(
             report.authority.authorization_scope_refs,
             &String.starts_with?(&1, "authorization-scope://tenant-prelim-pressure-")
           )

    assert "budget://phase5prelim/local-no-spend" in report.authority.budget_refs
    assert "Mezzanine.Workflows.ExecutionAttempt" in report.temporal.workflow_type_refs
    assert "mezzanine.hazmat" in report.temporal.task_queue_refs

    assert "semantic://prelim/turn-1" in report.semantic_gateway.context_provenance_refs
    assert "claim://semantic/input/prelim" in report.semantic_gateway.payload_boundary_refs

    assert report.provider_simulation.input_fingerprint_policy == "transient_hash"
    assert report.provider_simulation.egress_denied

    assert "fixture-scope://claude_agent_sdk/package-local-only" in report.provider_simulation.provider_sdk_fixture_scope_refs

    assert "fixture-scope://codex_sdk/package-local-only" in report.provider_simulation.provider_sdk_fixture_scope_refs

    assert report.observability.aitrace_refs == [
             "aitrace://scenario-19/observability-trace-join-continuity",
             "aitrace://scenario-25/claim-check-trace-continuity"
           ]

    assert report.privacy.raw_payload_scan_result == "passed"

    assert report.privacy.suppression_visibility_refs == [
             "suppression://prelim/semantic-failure"
           ]

    assert report.privacy.privacy_redaction_fixture_refs == ["fixture://privacy/prelim"]

    assert result.negative_failures.missing_temporal ==
             {:missing_required_refs, [:temporal, :workflow_type_refs]}

    assert result.negative_failures.missing_authority ==
             {:missing_required_refs, [:authority, :authorization_scope_refs]}

    assert result.negative_failures.missing_semantic ==
             {:missing_required_refs, [:semantic_gateway, :context_provenance_refs]}

    assert result.negative_failures.missing_negative_evidence ==
             {:missing_required_refs, [:negative_evidence_ref]}

    assert result.negative_failures.raw_payload_leak ==
             {:raw_payload_leak, [:privacy, :artifact_refs, 0]}
  end

  test "M3 contract join fails closed when Temporal substrate is not serving" do
    assert {:error, {:temporal_substrate_not_serving, output}} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m3_contract_join,
               temporal_runner: fn "just", ["dev-status"], _opts ->
                 {"mezzanine-temporal-dev.service inactive", 0}
               end
             )

    assert output =~ "inactive"
  end

  test "M5 service profile bootstrap fails closed when Temporal substrate is not serving" do
    assert {:error, {:temporal_substrate_not_serving, output}} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m5_service_profile_bootstrap,
               temporal_runner: fn "just", ["dev-status"], _opts ->
                 {"mezzanine-temporal-dev.service inactive", 0}
               end
             )

    assert output =~ "inactive"
  end

  test "M5 governed smoke fails closed when Temporal substrate is not serving" do
    assert {:error, {:temporal_substrate_not_serving, output}} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m5_governed_smoke,
               temporal_runner: fn "just", ["dev-status"], _opts ->
                 {"mezzanine-temporal-dev.service inactive", 0}
               end
             )

    assert output =~ "inactive"
  end

  test "M5 pressure and negatives fails closed when Temporal substrate is not serving" do
    assert {:error, {:temporal_substrate_not_serving, output}} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m5_pressure_and_negatives,
               temporal_runner: fn "just", ["dev-status"], _opts ->
                 {"mezzanine-temporal-dev.service inactive", 0}
               end
             )

    assert output =~ "inactive"
  end

  test "M6 evidence report fails closed when Temporal substrate is not serving" do
    assert {:error, {:temporal_substrate_not_serving, output}} =
             CitadelSpineHarness.exercise_prelim_service_mode(
               :m6_evidence_report,
               temporal_runner: fn "just", ["dev-status"], _opts ->
                 {"mezzanine-temporal-dev.service inactive", 0}
               end
             )

    assert output =~ "inactive"
  end

  defp serving_temporal("just", ["dev-status"], opts) do
    assert opts[:cd] =~ "/mezzanine"
    assert opts[:stderr_to_stdout]

    {"""
     mezzanine-temporal-dev.service active
     namespace default
     127.0.0.1:7233
     SERVING
     """, 0}
  end
end
