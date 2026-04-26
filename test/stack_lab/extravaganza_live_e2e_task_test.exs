defmodule StackLab.ExtravaganzaLiveE2ETaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.StackLab.Extravaganza.LiveE2e

  test "root workspace exposes the Extravaganza live E2E task" do
    assert Code.ensure_loaded?(LiveE2e)
    assert LiveE2e.delegate_project_dir() == support_harness_dir()
  end

  defp support_harness_dir do
    Path.expand("support/citadel_spine_harness")
  end
end
