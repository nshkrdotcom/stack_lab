defmodule Mix.Tasks.StackLab.ProviderSmokeCheck do
  @moduledoc """
  Runs the opt-in provider smoke check for the Extravaganza non-UI lane.
  """

  use Mix.Task

  alias StackLab.CitadelSpineHarness.ProviderSmokeCheck

  @shortdoc "Run the provider smoke check"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case ProviderSmokeCheck.run(args) do
      {:ok, receipt} ->
        Mix.shell().info("Provider smoke check passed")
        Mix.shell().info("receipt_file=#{receipt.receipt_file}")
        Mix.shell().info("github_repo=#{receipt.github.repo}")
        Mix.shell().info("run_label=#{receipt.run_label}")

      {:error, reason} ->
        Mix.raise("Provider smoke check failed: #{inspect(reason)}")
    end
  end
end
