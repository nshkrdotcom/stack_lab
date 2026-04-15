defmodule StackLab.Examples.OuterBrainRestartDurability do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.outer_brain_durability_scenario()
  end

  def exercise(case_name)
      when case_name in [:pending_recovery_after_restart, :final_reply_after_restart] do
    CitadelSpineHarness.exercise_outer_brain_durability(case_name)
  end
end
