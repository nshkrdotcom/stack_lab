defmodule StackLab.Examples.LowerFactsRoundtrip do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.lower_facts_scenario()
  end

  def exercise(:generic_readback) do
    CitadelSpineHarness.exercise_lower_facts(:generic_readback)
  end

  def exercise(:authorized_mezzanine_readback) do
    CitadelSpineHarness.exercise_lower_facts(:authorized_mezzanine_readback)
  end

  def exercise(:unauthorized_mezzanine_readback) do
    CitadelSpineHarness.exercise_lower_facts(:unauthorized_mezzanine_readback)
  end
end
