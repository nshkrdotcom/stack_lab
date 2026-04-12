defmodule StackLab.Examples.RestartAuthorityDrill do
  @moduledoc false

  def scenario do
    %{
      name: :restart_authority_drill,
      compose: StackLab.LabCore.compose_file(:single),
      runbook: StackLab.LabCore.runbook(:faults)
    }
  end
end
