defmodule StackLab.Examples.MezzanineRestartRecoveryTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.MezzanineRestartRecovery

  test "mezzanine restart-recovery example exposes the Stage-2 substrate proof" do
    scenario = MezzanineRestartRecovery.scenario()

    assert scenario.name == :mezzanine_restart_recovery

    assert scenario.cases == %{
             dispatching_retry_after_restart: %{kind: :dispatching_retry_after_restart}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "dispatch work is recovered after restart and replayed without duplication" do
    assert {:ok, result} =
             MezzanineRestartRecovery.exercise(:dispatching_retry_after_restart)

    assert result.case == :dispatching_retry_after_restart
    assert result.before_restart.execution_dispatch_state == :dispatching
    assert result.before_restart.job_status == :missing_after_crash
    assert result.after_restart.recovered_count == 1
    assert result.after_restart.execution_dispatch_state == :dispatching_retry
    assert result.after_restart.job_status == :scheduled
    assert result.after_restart.dispatch_attempt_count == 1
    assert result.final.classification == :accepted
    assert result.final.execution_dispatch_state == :awaiting_receipt
    assert result.final.job_status == :completed
    refute result.final.job_id == result.before_restart.job_id
    assert result.final.submission_ref_status == "duplicate"
    assert result.final.unique_submission_count == 1
    assert result.final.duplicate_replay_count == 1
  end
end
