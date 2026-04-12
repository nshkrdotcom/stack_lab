defmodule StackLab.Examples.SessionLineageDrillTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.SessionLineageDrill

  test "session-lineage drill points at the multi-node harness" do
    scenario = SessionLineageDrill.scenario()

    assert scenario.name == :session_lineage_drill
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end
end
