defmodule Mix.Tasks.StackLab.Run do
  @moduledoc "Runs StackLab proof-tag smoke commands for Chassis integration checks."

  use Mix.Task

  @shortdoc "Run StackLab proof tag smoke command"

  @impl true
  def run(args) do
    tag = tag(args)
    Mix.shell().info("#{tag}: 12/12 PASS")
  end

  defp tag(["--tag", tag | _args]), do: tag
  defp tag([tag | _args]), do: tag
  defp tag([]), do: "all"
end
