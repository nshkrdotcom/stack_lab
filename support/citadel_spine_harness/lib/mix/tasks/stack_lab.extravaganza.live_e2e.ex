defmodule Mix.Tasks.StackLab.Extravaganza.LiveE2e do
  @moduledoc """
  Runs the opt-in dynamic live provider E2E proof for the Extravaganza non-UI lane.
  """

  use Mix.Task

  alias StackLab.CitadelSpineHarness.ExtravaganzaLiveE2E

  @shortdoc "Run Extravaganza's dynamic live provider E2E proof"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case ExtravaganzaLiveE2E.run(args) do
      {:ok, receipt} ->
        Mix.shell().info("Extravaganza dynamic live provider E2E passed")
        Mix.shell().info("receipt_file=#{receipt.receipt_file}")
        Mix.shell().info("github_repo=#{receipt.github.repo}")
        Mix.shell().info("run_label=#{receipt.run_label}")

      {:error, reason} ->
        Mix.raise("Extravaganza dynamic live provider E2E failed: #{inspect(reason)}")
    end
  end
end
