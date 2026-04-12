defmodule StackLab.Examples.GovernedRunRoundtrip do
  @moduledoc false

  def scenario do
    %{
      name: :governed_run_roundtrip,
      compose: StackLab.LabCore.compose_file(:single),
      runbook: StackLab.LabCore.runbook(:up_single)
    }
  end
end
