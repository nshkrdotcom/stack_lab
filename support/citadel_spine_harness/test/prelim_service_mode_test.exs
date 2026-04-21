defmodule StackLab.CitadelSpineHarness.PrelimServiceModeTest do
  use ExUnit.Case, async: false

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
