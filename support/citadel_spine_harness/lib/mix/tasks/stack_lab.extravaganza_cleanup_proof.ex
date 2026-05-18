defmodule Mix.Tasks.StackLab.ExtravaganzaCleanupProof do
  @moduledoc """
  Runs the destructive Extravaganza GitHub PR cleanup product-path proof.
  """

  use Mix.Task

  alias StackLab.CitadelSpineHarness.ExtravaganzaCleanupProof

  @shortdoc "Run the Extravaganza destructive cleanup product proof"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case ExtravaganzaCleanupProof.run(args) do
      {:ok, receipt} ->
        Mix.shell().info("Extravaganza cleanup proof passed")
        Mix.shell().info("receipt_file=#{receipt.receipt_file}")
        Mix.shell().info("approved_write_repo=#{receipt.approved_write_repo}")
        Mix.shell().info("run_label=#{receipt.run_label}")

      {:error, reason} ->
        Mix.raise("Extravaganza cleanup proof failed: #{inspect(reason)}")
    end
  end
end
