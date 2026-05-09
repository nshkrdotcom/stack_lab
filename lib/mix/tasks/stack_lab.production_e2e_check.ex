defmodule Mix.Tasks.StackLab.ProductionE2ECheck do
  @moduledoc """
  Root workspace entry point for the Extravaganza production E2E check.

  The implementation lives in `support/citadel_spine_harness`; this task keeps
  the documented root command working by delegating to that package.
  """

  use Mix.Task

  @shortdoc "Run the Extravaganza production E2E acceptance check"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case run_child_mix(args) do
      0 -> :ok
      status -> Mix.raise("Production E2E check failed: support harness exit #{status}")
    end
  end

  @doc false
  def delegate_project_dir do
    Path.expand("../../../support/citadel_spine_harness", __DIR__)
  end

  defp run_child_mix(args) do
    {_stream, status} =
      System.cmd(
        mix_executable(),
        ["stack_lab.production_e2e_check" | args],
        cd: delegate_project_dir(),
        stderr_to_stdout: true,
        into: IO.stream(:stdio, :line)
      )

    status
  end

  defp mix_executable do
    System.find_executable("mix") || "mix"
  end
end
