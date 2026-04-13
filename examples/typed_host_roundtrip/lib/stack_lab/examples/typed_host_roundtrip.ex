defmodule StackLab.Examples.TypedHostRoundtrip do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.typed_host_scenario()
  end

  def exercise(case_name)
      when case_name in [:command_acceptance, :command_duplicate, :command_scope_rejection] do
    CitadelSpineHarness.exercise_typed_host(case_name)
  end
end
