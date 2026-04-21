defmodule StackLab.Examples.MezzanineRestartRecoveryTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.MezzanineRestartRecovery

  test "mezzanine restart-recovery example exposes the Stage-2 substrate proof" do
    scenario = MezzanineRestartRecovery.scenario()

    assert scenario.name == :mezzanine_restart_recovery

    assert scenario.cases == %{
             temporal_replay_after_restart: %{kind: :temporal_replay_after_restart}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "dispatch work is recovered after restart and replayed without duplication" do
    assert {:ok, result} =
             MezzanineRestartRecovery.exercise(:temporal_replay_after_restart)

    assert result.case == :temporal_replay_after_restart
    assert result.before_restart.execution_dispatch_state == :in_flight
    assert result.before_restart.handoff_status == :missing_after_crash
    assert result.after_restart.recovered_count == 1
    assert result.after_restart.execution_dispatch_state == :in_flight
    assert result.after_restart.handoff_status == :available
    assert result.after_restart.dispatch_attempt_count == 1
    assert result.final.classification == :accepted
    assert result.final.execution_dispatch_state == :accepted_active
    assert result.final.handoff_status == :completed
    refute result.final.temporal_handoff_ref == result.before_restart.temporal_handoff_ref
    assert result.final.submission_ref_status == "duplicate"
    assert result.final.unique_submission_count == 1
    assert result.final.duplicate_replay_count == 1
  end
end
