defmodule StackLab.Examples.PressureFailoverDrill do
  @moduledoc false

  def scenario do
    %{
      name: :pressure_failover_drill,
      compose: StackLab.LabCore.compose_file(:multi),
      runbook: StackLab.LabCore.runbook(:faults)
    }
  end
end
