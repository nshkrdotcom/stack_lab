defmodule Mix.Tasks.GnTen.Topology.Freeze do
  @moduledoc "Validates and records the frozen v2 gn-ten distributed topology catalog."

  use Mix.Task

  alias StackLab.GnTen.DistributedTopology

  @shortdoc "Validates the gn-ten distributed topology freeze"

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

    case DistributedTopology.validate_canonical() do
      {:ok, receipt} ->
        path =
          opts
          |> Keyword.get(:receipt, DistributedTopology.default_receipt_path())
          |> then(&DistributedTopology.write_receipt!(receipt, &1))

        print_success(receipt, path, Keyword.get(opts, :json, false))

      {:error, failures} ->
        print_failure(failures, Keyword.get(opts, :json, false))
        exit({:shutdown, 1})
    end
  end

  defp print_success(receipt, path, true) do
    receipt
    |> Map.put("receipt_path", path)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_success(receipt, path, false) do
    Mix.shell().info("gn_ten.topology.freeze passed")
    Mix.shell().info("receipt=#{path}")
    Mix.shell().info("receipt_ref=#{receipt["receipt_ref"]}")
    Mix.shell().info("topology_count=#{receipt["topology_count"]}")
  end

  defp print_failure(failures, true) do
    %{status: :fail, failures: failures}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_failure(failures, false) do
    Mix.shell().error("gn_ten.topology.freeze failed")
    Enum.each(failures, &Mix.shell().error("  #{inspect(&1)}"))
  end
end
