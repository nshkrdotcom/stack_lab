defmodule StackLab.Examples.MultiNodeRoundtrip do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.multi_node_scenario()
  end

  def exercise(case_name) when case_name in [:acceptance, :scope_rejection] do
    CitadelSpineHarness.exercise_multi_node(case_name)
  end
end
