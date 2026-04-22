defmodule StackLab.Examples.OuterBrainRestartDurabilityTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.OuterBrainRestartDurability

  test "outer-brain durability scenario exposes the Stage-1 semantic restart proof" do
    scenario = OuterBrainRestartDurability.scenario()

    assert scenario.name == :outer_brain_restart_durability

    assert scenario.cases == %{
             pending_recovery_after_restart: %{kind: :pending_recovery_after_restart},
             final_reply_after_restart: %{kind: :final_reply_after_restart},
             semantic_failure_carrier_after_restart: %{
               kind: :semantic_failure_carrier_after_restart
             },
             duplicate_publication_suppressed_after_restart: %{
               kind: :duplicate_publication_suppressed_after_restart
             }
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "pending recovery reconstructs from durable truth after process restart" do
    assert {:ok, result} =
             OuterBrainRestartDurability.exercise(:pending_recovery_after_restart)

    assert result.case == :pending_recovery_after_restart
    assert result.before_restart.mirrored_holder == "stack_lab_outer_brain"
    assert result.after_restart.mirrored_fence == nil
    assert result.after_restart.persisted_lease_holder == "stack_lab_outer_brain"
    assert result.after_restart.persisted_lease_epoch == 1
    assert result.after_restart.journal_entry_ids == [result.before_restart.journal_entry_id]
    assert result.after_restart.journal_entry_types == ["wake_input"]
    assert result.after_restart.publication_phase == :provisional
    assert result.after_restart.pending_recovery_tasks == [:ambiguous_submission]
    assert result.after_restart.next_action == {:reconcile, :ambiguous_submission}
    assert result.durable.recovery_task_id != nil
    assert result.durable.publication_phase == :provisional
  end

  test "final publication reconstructs as a durable noop after process restart" do
    assert {:ok, result} =
             OuterBrainRestartDurability.exercise(:final_reply_after_restart)

    assert result.case == :final_reply_after_restart
    assert result.before_restart.mirrored_holder == "stack_lab_outer_brain"
    assert result.after_restart.mirrored_fence == nil
    assert result.after_restart.persisted_lease_holder == "stack_lab_outer_brain"
    assert result.after_restart.journal_entry_ids == [result.before_restart.journal_entry_id]
    assert result.after_restart.journal_entry_types == ["wake_input"]
    assert result.after_restart.publication_phase == :final
    assert result.after_restart.pending_recovery_tasks == []
    assert result.after_restart.next_action == {:noop, :final_reply_published}
    assert result.durable.recovery_task_id == nil
    assert result.durable.publication_phase == :final
  end

  test "semantic failure carriers reconstruct after process restart" do
    assert {:ok, result} =
             OuterBrainRestartDurability.exercise(:semantic_failure_carrier_after_restart)

    assert result.case == :semantic_failure_carrier_after_restart
    assert result.durable.semantic_failure_kind == :semantic_insufficient_context
    assert result.durable.semantic_failure_retry_class == :clarification_required
    assert result.after_restart.semantic_failure_kinds == [:semantic_insufficient_context]
    assert result.after_restart.semantic_failure_retry_classes == [:clarification_required]
    assert result.after_restart.semantic_failure_trace_ids == ["trace-semantic-failure"]
  end

  test "duplicate reply publication is suppressed after process restart" do
    assert {:ok, result} =
             OuterBrainRestartDurability.exercise(:duplicate_publication_suppressed_after_restart)

    assert result.case == :duplicate_publication_suppressed_after_restart
    assert result.durable.initial_publication_id =~ "publication-"
    assert result.durable.replayed_publication_id == result.durable.initial_publication_id
    assert result.after_restart.publication_ids == [result.durable.initial_publication_id]
    assert result.after_restart.publication_bodies == ["Done"]
    assert result.after_restart.next_action == {:noop, :final_reply_published}
  end
end
