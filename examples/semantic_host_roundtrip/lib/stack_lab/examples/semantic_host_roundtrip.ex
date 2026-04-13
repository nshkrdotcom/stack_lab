defmodule StackLab.Examples.SemanticHostRoundtrip do
  @moduledoc false

  alias StackLab.CitadelSpineHarness

  def scenario do
    CitadelSpineHarness.semantic_host_scenario()
  end

  def exercise(case_name)
      when case_name in [:turn_acceptance, :turn_replay, :turn_scope_rejection] do
    CitadelSpineHarness.exercise_semantic_host(case_name)
  end
end
