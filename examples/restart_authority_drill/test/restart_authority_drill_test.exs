defmodule StackLab.Examples.RestartAuthorityDrillTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness.RemoteSupport
  alias StackLab.Examples.RestartAuthorityDrill

  @distribution_skip (case RemoteSupport.ensure_distribution_started() do
                        :ok ->
                          false

                        {:error, reason} ->
                          RemoteSupport.distribution_start_error_message(reason)
                      end)

  test "restart-authority drill points at the fault runbook" do
    scenario = RestartAuthorityDrill.scenario()

    assert scenario.name == :restart_authority_drill
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  @tag skip: @distribution_skip
  test "delayed acceptance still converges to durable submission truth" do
    assert {:ok, result} = RestartAuthorityDrill.exercise(:delayed_acceptance)

    assert result.case == :delayed_acceptance
    assert result.delay_ms >= 100
    assert result.transport.status == :accepted
    assert result.citadel.replay_status == :submission_accepted
    assert result.transport.submission_key == result.spine.submission_key
  end

  @tag skip: @distribution_skip
  @tag timeout: 120_000
  test "node restart recovery replays pending work into a replacement Spine node" do
    assert {:ok, result} = RestartAuthorityDrill.exercise(:node_restart_recovery)

    assert result.case == :node_restart_recovery
    assert result.before_restart.replay_status == :pending
    assert result.before_restart.last_error_code == "transport_unreachable"
    assert result.after_restart.replay_status == :submission_accepted
    assert result.transport.status == :accepted
    assert result.transport.submission_key == result.spine.submission_key
    refute result.remote.initial_node == result.remote.replacement_node
  end
end
