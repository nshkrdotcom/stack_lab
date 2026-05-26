defmodule Mix.Tasks.StackLab.GnTen.NodeLab.Probe do
  @moduledoc "Reads the last gn-ten node-lab run state for a logical node."

  use Mix.Task

  alias StackLab.GnTenNodeLab.{Runner, RunState}

  @shortdoc "Probes a gn-ten node-lab logical node"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          node: :string,
          state: :string,
          json: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    node_id = Keyword.get(opts, :node) || Mix.raise("expected --node <logical_node_id>")
    runner_opts = [state_path: Keyword.get(opts, :state, RunState.default_path())]

    case Runner.probe(node_id, runner_opts) do
      {:ok, receipt} ->
        print(receipt, Keyword.get(opts, :json, false), :info)

      {:error, receipt} ->
        print(receipt, Keyword.get(opts, :json, false), :error)
        exit({:shutdown, 1})
    end
  end

  defp print(receipt, true, level) do
    encoded = Jason.encode!(receipt, pretty: true)
    if level == :error, do: Mix.shell().error(encoded), else: Mix.shell().info(encoded)
  end

  defp print(receipt, false, :info) do
    Mix.shell().info("stack_lab.gn_ten.node_lab.probe #{receipt["status"]}")
    Mix.shell().info("node=#{receipt["node"]}")
  end

  defp print(receipt, false, :error) do
    Mix.shell().error("stack_lab.gn_ten.node_lab.probe failed")
    Mix.shell().error("failures=#{inspect(receipt["failures"])}")
  end
end
