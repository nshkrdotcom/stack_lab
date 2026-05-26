defmodule Mix.Tasks.StackLab.GnTen.NodeLab.Up do
  @moduledoc "Boots a gn-ten node-lab topology and writes a run receipt."

  use Mix.Task

  alias StackLab.GnTenNodeLab.{Runner, RunState}

  @shortdoc "Boots a gn-ten node-lab topology"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          topology: :string,
          state: :string,
          json: :boolean,
          keep: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")

    topology =
      Keyword.get(opts, :topology) ||
        Mix.raise("expected --topology <path>")

    runner_opts = [
      state_path: Keyword.get(opts, :state, RunState.default_path()),
      keep?: Keyword.get(opts, :keep, false)
    ]

    case Runner.up(topology, runner_opts) do
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
    Mix.shell().info("stack_lab.gn_ten.node_lab.up #{receipt["status"]}")
    Mix.shell().info("state=#{receipt["state_path"]}")
  end

  defp print(receipt, false, :error) do
    Mix.shell().error("stack_lab.gn_ten.node_lab.up failed")
    Mix.shell().error("failures=#{inspect(receipt["failures"])}")
  end
end
