defmodule Mix.Tasks.StackLab.GnTen.NodeLab.Preflight do
  @moduledoc "Runs the package-owned gn-ten node-lab preflight."

  use Mix.Task

  alias StackLab.GnTenNodeLab.Preflight

  @shortdoc "Runs the gn-ten node-lab preflight"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          receipt: :string,
          json: :boolean
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    preflight_opts = [
      receipt_path:
        Keyword.get(
          opts,
          :receipt,
          "docs/receipts/gn_ten_distributed/node_lab_preflight.json"
        )
    ]

    case Preflight.run(preflight_opts) do
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
    Mix.shell().info("stack_lab.gn_ten.node_lab.preflight passed")
    Mix.shell().info("receipt=#{receipt["receipt_path"]}")
    Mix.shell().info("receipt_ref=#{receipt["receipt_ref"]}")
  end

  defp print(receipt, false, :error) do
    Mix.shell().error("stack_lab.gn_ten.node_lab.preflight failed")
    Mix.shell().error("receipt=#{receipt["receipt_path"]}")
    Mix.shell().error("failures=#{inspect(receipt["failures"])}")
  end
end
