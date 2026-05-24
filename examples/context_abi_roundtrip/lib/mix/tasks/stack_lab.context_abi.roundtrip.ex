defmodule Mix.Tasks.StackLab.ContextAbi.Roundtrip do
  @moduledoc "Runs the deterministic Context ABI roundtrip proof."
  @shortdoc "Runs the deterministic Context ABI roundtrip proof"

  use Mix.Task

  alias StackLab.Examples.ContextABIRoundtrip

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    json? = "--json" in args

    case ContextABIRoundtrip.run() do
      {:ok, receipt} when json? ->
        Mix.shell().info(ContextABIRoundtrip.to_json!(receipt))

      {:ok, receipt} ->
        Mix.shell().info("status=#{receipt.status}")
        Mix.shell().info("receipt_ref=#{receipt.receipt_ref}")
        Mix.shell().info("context_packet_ref=#{receipt.context_packet_ref}")
        Mix.shell().info("model_receipt_ref=#{receipt.model_receipt_ref}")

      {:error, reason} ->
        Mix.raise("context ABI roundtrip failed: #{inspect(reason)}")
    end
  end
end
