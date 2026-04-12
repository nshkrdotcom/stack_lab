defmodule StackLab.Examples.MultiNodeRoundtrip do
  @moduledoc false

  def scenario do
    %{
      name: :multi_node_roundtrip,
      compose: StackLab.LabCore.compose_file(:multi),
      runbook: StackLab.LabCore.runbook(:up_multi)
    }
  end
end
