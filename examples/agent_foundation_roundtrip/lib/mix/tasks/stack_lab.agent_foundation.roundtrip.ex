defmodule Mix.Tasks.StackLab.AgentFoundation.Roundtrip do
  @moduledoc "Runs the deterministic StackLab agent foundation proof."
  @shortdoc "Runs the deterministic agent foundation proof"

  use Mix.Task

  alias StackLab.AgentFoundationRoundtrip

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    deterministic? = "--deterministic" in args
    json? = "--json" in args

    case AgentFoundationRoundtrip.run(%{deterministic?: deterministic?}) do
      {:ok, receipt} when json? ->
        Mix.shell().info(AgentFoundationRoundtrip.to_json!(receipt))

      {:ok, receipt} ->
        Mix.shell().info("status=#{receipt.status}")
        Mix.shell().info("receipt_ref=#{receipt.receipt_ref}")

      {:error, reason} ->
        Mix.raise("agent foundation roundtrip failed: #{inspect(reason)}")
    end
  end
end
