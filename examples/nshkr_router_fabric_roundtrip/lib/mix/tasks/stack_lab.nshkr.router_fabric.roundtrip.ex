defmodule Mix.Tasks.StackLab.Nshkr.RouterFabric.Roundtrip do
  @moduledoc "Runs the deterministic NSHKR router fabric roundtrip proof."
  @shortdoc "Runs the deterministic NSHKR router fabric proof"

  use Mix.Task

  alias StackLab.Examples.NSHKRRouterFabricRoundtrip

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    json? = "--json" in args

    case NSHKRRouterFabricRoundtrip.run() do
      {:ok, receipt} when json? ->
        Mix.shell().info(NSHKRRouterFabricRoundtrip.to_json!(receipt))

      {:ok, receipt} ->
        Mix.shell().info("status=#{receipt.status}")
        Mix.shell().info("receipt_ref=#{receipt.receipt_ref}")
        Mix.shell().info("route_decision_ref=#{receipt.route_decision_ref}")
        Mix.shell().info("model_receipt_ref=#{receipt.model_receipt_ref}")

      {:error, reason} ->
        Mix.raise("NSHKR router fabric roundtrip failed: #{inspect(reason)}")
    end
  end
end
