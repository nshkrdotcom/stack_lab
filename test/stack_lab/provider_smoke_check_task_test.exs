defmodule StackLab.ProviderSmokeCheckTaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.StackLab.ProviderSmokeCheck

  test "root workspace exposes the provider smoke check task" do
    assert Code.ensure_loaded?(ProviderSmokeCheck)
    assert ProviderSmokeCheck.delegate_project_dir() == support_harness_dir()
  end

  defp support_harness_dir do
    Path.expand("support/citadel_spine_harness")
  end
end
