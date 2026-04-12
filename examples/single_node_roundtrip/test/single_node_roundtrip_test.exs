defmodule StackLab.Examples.SingleNodeRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.SingleNodeRoundtrip

  test "single-node scenario points at the single-node harness files" do
    scenario = SingleNodeRoundtrip.scenario()

    assert scenario.name == :single_node_roundtrip
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end
end
