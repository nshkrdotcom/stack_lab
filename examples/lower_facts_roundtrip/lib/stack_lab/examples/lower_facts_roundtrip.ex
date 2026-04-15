defmodule StackLab.Examples.LowerFactsRoundtrip do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.lower_facts_scenario()
  end

  def exercise(:generic_readback) do
    CitadelSpineHarness.exercise_lower_facts(:generic_readback)
  end
end
