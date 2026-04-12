defmodule StackLab.Examples.SingleNodeRoundtrip do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.same_node_scenario()
  end

  def exercise(case_name) when case_name in [:acceptance, :duplicate, :scope_rejection] do
    CitadelSpineHarness.exercise_same_node(case_name)
  end
end
