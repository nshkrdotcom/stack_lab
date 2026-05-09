defmodule StackLab.TreLaneCheckTaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.StackLab.TreLaneCheck

  test "root workspace exposes the TRE lane acceptance task" do
    assert Code.ensure_loaded?(TreLaneCheck)
    assert TreLaneCheck.delegate_project_dir() == support_harness_dir()
  end

  defp support_harness_dir do
    Path.expand("support/citadel_spine_harness")
  end
end
