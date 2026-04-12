defmodule StackLab.Examples.RestartAuthorityDrill do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.restart_authority_scenario()
  end

  def exercise(case_name) when case_name in [:delayed_acceptance, :node_restart_recovery] do
    CitadelSpineHarness.exercise_restart_authority(case_name)
  end
end
