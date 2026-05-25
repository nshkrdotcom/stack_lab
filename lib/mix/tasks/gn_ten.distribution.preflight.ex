defmodule Mix.Tasks.GnTen.Distribution.Preflight do
  @moduledoc "Runs the v2 local Erlang distribution preflight."

  use Mix.Task

  alias StackLab.GnTen.DistributionPreflight

  @shortdoc "Runs the gn-ten distributed preflight"

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
      receipt_path: Keyword.get(opts, :receipt, DistributionPreflight.default_receipt_path())
    ]

    case DistributionPreflight.run(preflight_opts) do
      {:ok, receipt} ->
        print_success(receipt, Keyword.get(opts, :json, false))

      {:error, receipt} ->
        print_failure(receipt, Keyword.get(opts, :json, false))
        exit({:shutdown, 1})
    end
  end

  defp print_success(receipt, true) do
    receipt
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_success(receipt, false) do
    Mix.shell().info("gn_ten.distribution.preflight passed")
    Mix.shell().info("receipt=#{receipt["receipt_path"]}")
    Mix.shell().info("receipt_ref=#{receipt["receipt_ref"]}")
  end

  defp print_failure(receipt, true) do
    receipt
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_failure(receipt, false) do
    Mix.shell().error("gn_ten.distribution.preflight failed")
    Mix.shell().error("receipt=#{receipt["receipt_path"]}")
    Mix.shell().error("failures=#{inspect(receipt["failures"])}")
  end
end
