defmodule StackLab.Examples.GovernedRunRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.GovernedRunRoundtrip

  test "governed-run example is wired to the single-node harness" do
    scenario = GovernedRunRoundtrip.scenario()

    assert scenario.name == :governed_run_roundtrip
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end
end
