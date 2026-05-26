defmodule Mix.Tasks.StackLab.GnTen.NodeLab.Attach do
  @moduledoc "Prints a redacted debug attach receipt for a gn-ten node-lab node."

  use Mix.Task

  alias StackLab.GnTenNodeLab.{Runner, RunState}

  @shortdoc "Prints a redacted gn-ten node-lab attach recipe"

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

    case Runner.attach(node_id, runner_opts) do
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
    Mix.shell().info("stack_lab.gn_ten.node_lab.attach #{receipt["status"]}")
    Mix.shell().info("node=#{receipt["node"]}")
    Mix.shell().info("cookie=<redacted>")
  end

  defp print(receipt, false, :error) do
    Mix.shell().error("stack_lab.gn_ten.node_lab.attach failed")
    Mix.shell().error("failures=#{inspect(receipt["failures"])}")
  end
end
