defmodule StackLab.Examples.SessionLineageDrill do
  @moduledoc false

  def scenario do
    %{
      name: :session_lineage_drill,
      compose: StackLab.LabCore.compose_file(:multi),
      runbook: StackLab.LabCore.runbook(:up_multi)
    }
  end
end
