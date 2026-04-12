defmodule StackLab.Examples.PressureFailoverDrillTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.PressureFailoverDrill

  test "pressure and failover drill points at the multi-node harness and fault runbook" do
    scenario = PressureFailoverDrill.scenario()

    assert scenario.name == :pressure_failover_drill
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end
end
