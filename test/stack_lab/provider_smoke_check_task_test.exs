defmodule StackLab.ProviderSmokeCheckTaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.StackLab.ProviderSmokeCheck

  test "root workspace exposes the provider smoke check task" do
    assert Code.ensure_loaded?(ProviderSmokeCheck)
    assert ProviderSmokeCheck.delegate_project_dir() == support_harness_dir()
  end

  test "old extravaganza live e2e task is not exposed" do
    refute Code.ensure_loaded?(Mix.Tasks.StackLab.Extravaganza.LiveE2e)
    refute Mix.Task.get("stack_lab.extravaganza.live_e2e")
  end

  defp support_harness_dir do
    Path.expand("support/citadel_spine_harness")
  end
end
