defmodule StackLab.Examples.SingleNodeRoundtrip do
  @moduledoc false

  def scenario do
    %{
      name: :single_node_roundtrip,
      compose: StackLab.LabCore.compose_file(:single),
      runbook: StackLab.LabCore.runbook(:up_single)
    }
  end
end
