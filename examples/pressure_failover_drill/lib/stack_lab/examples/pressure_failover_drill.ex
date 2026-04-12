defmodule StackLab.Examples.PressureFailoverDrill do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.pressure_failover_scenario()
  end

  def exercise(case_name) when case_name in [:transport_interruption, :duplicate_delivery] do
    CitadelSpineHarness.exercise_pressure_failover(case_name)
  end
end
