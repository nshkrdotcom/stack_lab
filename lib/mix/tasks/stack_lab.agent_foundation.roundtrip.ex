defmodule Mix.Tasks.StackLab.AgentFoundation.Roundtrip do
  @moduledoc """
  Runs the deterministic StackLab agent foundation proof from the workspace root.
  """
  @shortdoc "Runs the deterministic agent foundation proof"

  use Mix.Task

  @impl true
  def run(args) do
    example_dir = Path.expand("examples/agent_foundation_roundtrip", File.cwd!())

    {output, status} =
      System.cmd("mix", ["stack_lab.agent_foundation.roundtrip" | args],
        cd: example_dir,
        env: [{"MIX_ENV", to_string(Mix.env())}],
        stderr_to_stdout: true
      )

    if status == 0 do
      Mix.shell().info(String.trim_trailing(output))
    else
      Mix.raise(String.trim_trailing(output))
    end
  end
end
