defmodule StackLab.Examples.RestartAuthorityDrillTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.RestartAuthorityDrill

  test "restart-authority drill points at the fault runbook" do
    scenario = RestartAuthorityDrill.scenario()

    assert scenario.name == :restart_authority_drill
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end
end
