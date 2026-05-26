defmodule Mix.Tasks.StackLab.GnTen.NodeLab.Down do
  @moduledoc "Clears gn-ten node-lab run state after a proof run."

  use Mix.Task

  alias StackLab.GnTenNodeLab.{Runner, RunState}

  @shortdoc "Clears gn-ten node-lab run state"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          state: :string,
          json: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    runner_opts = [state_path: Keyword.get(opts, :state, RunState.default_path())]

    case Runner.down(runner_opts) do
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
    Mix.shell().info("stack_lab.gn_ten.node_lab.down #{receipt["status"]}")
    Mix.shell().info("state=#{receipt["state_path"]}")
  end

  defp print(receipt, false, :error) do
    Mix.shell().error("stack_lab.gn_ten.node_lab.down failed")
    Mix.shell().error("failures=#{inspect(receipt["failures"])}")
  end
end
