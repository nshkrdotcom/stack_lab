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
          max_nodes: :integer,
          json: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    opts |> Keyword.get(:profile, "context_6_node") |> dispatch_profile(opts)
  end

  defp dispatch_profile("context_6_node", opts), do: run_context(opts)
  defp dispatch_profile("router_model_6_node", opts), do: run_router_model(opts)
  defp dispatch_profile("parity", opts), do: run_parity(opts)
  defp dispatch_profile("scale_12_node", opts), do: run_scale(opts, :scale_12_node)
  defp dispatch_profile("scale_32_node", opts), do: run_scale(opts, :scale_32_node)
  defp dispatch_profile("scale_49_node", opts), do: run_scale(opts, :scale_49_node)
  defp dispatch_profile("partition_recovery", opts), do: run_partition_recovery(opts)

  defp dispatch_profile(other, _opts) do
    Mix.raise("unsupported distributed proof profile: #{other}")
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

  defp run_parity(opts) do
    json? = Keyword.get(opts, :json, false)

    proof_opts =
      opts
      |> Keyword.take([:topology])
      |> Enum.map(fn {:topology, path} -> {:topology_path, path} end)

    case GnTenDistributedStack.run_parity(proof_opts) do
      {:ok, receipt} when json? ->
        Mix.shell().info(GnTenDistributedStack.to_json!(receipt))

      {:ok, receipt} ->
        Mix.shell().info("status=#{receipt.status}")
        Mix.shell().info("receipt_ref=#{receipt.receipt_ref}")
        Mix.shell().info("topology_ref=#{receipt.topology_ref}")
        Mix.shell().info("parity_status=#{receipt.parity_result["status"]}")

      {:error, reason} ->
        Mix.raise("distributed proof failed: #{inspect(reason)}")
    end
  end

  defp run_scale(opts, profile) do
    json? = Keyword.get(opts, :json, false)

    proof_opts =
      opts
      |> Keyword.take([:topology, :max_nodes])
      |> Enum.map(fn
        {:topology, path} -> {:topology_path, path}
        {:max_nodes, max_nodes} -> {:max_nodes, max_nodes}
      end)

    result =
      case profile do
        :scale_12_node -> GnTenDistributedStack.run_scale_12_node(proof_opts)
        :scale_32_node -> GnTenDistributedStack.run_scale_32_node(proof_opts)
        :scale_49_node -> GnTenDistributedStack.run_scale_49_node(proof_opts)
      end

    case result do
      {:ok, receipt} when json? ->
        Mix.shell().info(GnTenDistributedStack.to_json!(receipt))

      {:ok, receipt} ->
        Mix.shell().info("status=#{receipt.status}")
        Mix.shell().info("receipt_ref=#{receipt.receipt_ref}")
        Mix.shell().info("topology_ref=#{receipt.topology_ref}")
        Mix.shell().info("node_count=#{receipt.node_count}")
        Mix.shell().info("scale_gate=#{receipt.scale_gate["status"]}")

      {:error, reason} ->
        Mix.raise("distributed scale proof failed: #{inspect(reason)}")
    end
  end

  defp run_partition_recovery(opts) do
    json? = Keyword.get(opts, :json, false)

    proof_opts =
      opts
      |> Keyword.take([:topology])
      |> Enum.map(fn {:topology, path} -> {:topology_path, path} end)

    case GnTenDistributedStack.run_partition_recovery(proof_opts) do
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
