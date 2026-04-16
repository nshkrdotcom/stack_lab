defmodule StackLab.Examples.MezzanineRestartRecovery do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.mezzanine_restart_recovery_scenario()
  end

  def exercise(:dispatching_retry_after_restart) do
    CitadelSpineHarness.exercise_mezzanine_restart_recovery(:dispatching_retry_after_restart)
  end
end
