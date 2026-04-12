defmodule StackLab.Examples.MultiNodeRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.MultiNodeRoundtrip

  test "multi-node scenario points at the multi-node harness files" do
    scenario = MultiNodeRoundtrip.scenario()

    assert scenario.name == :multi_node_roundtrip
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end
end
