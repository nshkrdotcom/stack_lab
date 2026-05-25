defmodule Mix.Tasks.StackLab.GnTen.Distributed.Prove do
  @moduledoc "Runs local distributed gn-ten proof scenarios."
  @shortdoc "Runs local distributed gn-ten proof scenarios"

  use Mix.Task

  alias StackLab.Examples.GnTenDistributedStack

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          profile: :string,
          topology: :string,
          json: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    case Keyword.get(opts, :profile, "context_6_node") do
      "context_6_node" ->
        run_context(opts)

      "router_model_6_node" ->
        run_router_model(opts)

      other ->
        Mix.raise("unsupported distributed proof profile: #{other}")
    end
  end

  defp run_context(opts) do
    json? = Keyword.get(opts, :json, false)

    proof_opts =
      opts
      |> Keyword.take([:topology])
      |> Enum.map(fn {:topology, path} -> {:topology_path, path} end)

    case GnTenDistributedStack.run_context_6_node(proof_opts) do
      {:ok, receipt} when json? ->
        Mix.shell().info(GnTenDistributedStack.to_json!(receipt))

      {:ok, receipt} ->
        Mix.shell().info("status=#{receipt.status}")
        Mix.shell().info("receipt_ref=#{receipt.receipt_ref}")
        Mix.shell().info("topology_ref=#{receipt.topology_ref}")

      {:error, reason} ->
        Mix.raise("distributed proof failed: #{inspect(reason)}")
    end
  end

  defp run_router_model(opts) do
    json? = Keyword.get(opts, :json, false)

    proof_opts =
      opts
      |> Keyword.take([:topology])
      |> Enum.map(fn {:topology, path} -> {:topology_path, path} end)

    case GnTenDistributedStack.run_router_model_6_node(proof_opts) do
      {:ok, receipt} when json? ->
        Mix.shell().info(GnTenDistributedStack.to_json!(receipt))

      {:ok, receipt} ->
        Mix.shell().info("status=#{receipt.status}")
        Mix.shell().info("receipt_ref=#{receipt.receipt_ref}")
        Mix.shell().info("topology_ref=#{receipt.topology_ref}")

      {:error, reason} ->
        Mix.raise("distributed proof failed: #{inspect(reason)}")
    end
  end
end
