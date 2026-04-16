defmodule StackLab.Examples.GovernedRunRoundtrip do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.governed_run_scenario()
  end

  def exercise(case_name) do
    CitadelSpineHarness.exercise_governed_run(case_name)
  end
end
