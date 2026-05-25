defmodule Mix.Tasks.StackLab.GnTen.NodeLab.Status do
  @moduledoc "Reports the current gn-ten node-lab run state."

  use Mix.Task

  alias StackLab.GnTenNodeLab.{RunState, Runner}

  @shortdoc "Reports gn-ten node-lab status"

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

    {:ok, receipt} = Runner.status(state_path: Keyword.get(opts, :state, RunState.default_path()))
    print(receipt, Keyword.get(opts, :json, false))
  end

  defp print(receipt, true), do: Mix.shell().info(Jason.encode!(receipt, pretty: true))

  defp print(receipt, false) do
    Mix.shell().info("stack_lab.gn_ten.node_lab.status #{receipt["status"]}")
    Mix.shell().info("state=#{receipt["state_path"]}")
  end
end
