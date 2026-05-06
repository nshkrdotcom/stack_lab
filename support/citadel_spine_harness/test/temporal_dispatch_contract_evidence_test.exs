defmodule StackLab.CitadelSpineHarness.TemporalDispatchContractEvidenceTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "describes the Phase 6 TemporalDispatchContract evidence consumer scenario" do
    scenario = CitadelSpineHarness.temporal_dispatch_contract_scenario()

    assert scenario.name == :phase6_temporal_dispatch_contract

    assert scenario.cases == %{
             restart_replay_owner_evidence: %{kind: :restart_replay_owner_evidence}
           }

    assert scenario.contract == "TemporalDispatchContract.v1"
    assert scenario.owner_repo == :mezzanine
    assert :stack_lab in scenario.primary_repos
  end

  test "consumes Mezzanine TemporalDispatchContract.v1 evidence and keeps StackLab as composer" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_temporal_dispatch_contract(
               :restart_replay_owner_evidence
             )

    assert result.case == :restart_replay_owner_evidence
    assert result.stack_lab_role == :evidence_composer_not_owner
    assert result.contract.id == "TemporalDispatchContract.v1"
    assert result.contract.owner == :mezzanine
    assert result.service_mode_gate.temporal_required?
    assert result.service_mode_gate.owner_contract_consumed?
    assert result.service_mode_gate.lower_harness_only_rejected?

    assert result.positive.contract_id == "TemporalDispatchContract.v1"
    assert result.positive.temporal_namespace == "default"
    assert "temporal-task-queue://default/mezzanine.hazmat" in result.positive.task_queue_refs
    assert "workflow://Mezzanine.Workflows.ExecutionAttempt" in result.positive.workflow_type_refs
    assert result.positive.restart_procedure_ref == "mezzanine-just://temporal-restart"
    assert result.positive.active_workflow_state_before_restart_ref =~ "#accepted_active"
    assert result.positive.replay_or_continuation_evidence_ref =~ "temporal-replay://"
    assert result.positive.persisted_outcome_state_ref =~ "workflow-start-outbox://"
    refute result.positive.raw_workflow_history_included?
    refute Map.has_key?(result.positive, :raw_workflow_history)

    assert result.negative_failures.missing_worker ==
             {:missing_worker, "mezzanine.hazmat"}

    assert result.negative_failures.wrong_task_queue ==
             {:wrong_task_queue, %{expected: "mezzanine.hazmat", got: "mezzanine.agentic"}}

    assert result.negative_failures.outcome_persistence ==
             {:outbox_outcome_not_persisted, :store_down}
  end
end
