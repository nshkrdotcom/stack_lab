defmodule StackLab.Examples.PressureFailoverDrillTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness.RemoteSupport
  alias StackLab.Examples.PressureFailoverDrill

  @distribution_skip (case RemoteSupport.ensure_distribution_started() do
                        :ok ->
                          false

                        {:error, reason} ->
                          RemoteSupport.distribution_start_error_message(reason)
                      end)

  test "pressure and failover drill points at the multi-node harness and fault runbook" do
    scenario = PressureFailoverDrill.scenario()

    assert scenario.name == :pressure_failover_drill
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  @tag skip: @distribution_skip
  test "transport interruption leaves work pending until replay reaches a healthy Spine node" do
    assert {:ok, result} = PressureFailoverDrill.exercise(:transport_interruption)

    assert result.case == :transport_interruption
    assert result.before_recovery.replay_status == :pending
    assert result.before_recovery.last_error_code == "transport_unreachable"
    assert result.after_recovery.replay_status == :submission_accepted
    assert result.transport.status == :accepted
    assert result.transport.submission_key == result.spine.submission_key
  end

  @tag skip: @distribution_skip
  test "duplicate delivery produces a duplicate Spine acceptance without breaking Citadel truth" do
    assert {:ok, result} = PressureFailoverDrill.exercise(:duplicate_delivery)

    assert result.case == :duplicate_delivery
    assert result.transport.status == :accepted
    assert result.transport.duplicate_status == :duplicate
    assert result.citadel.replay_status == :submission_accepted
    assert result.transport.submission_key == result.spine.submission_key
  end
end
