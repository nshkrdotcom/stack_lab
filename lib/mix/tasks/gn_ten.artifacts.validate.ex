defmodule Mix.Tasks.GnTen.Artifacts.Validate do
  @moduledoc "Validates the gn-ten contract artifact ledger."

  use Mix.Task

  alias StackLab.GnTen.ContractArtifacts

  @shortdoc "Validates gn-ten contract artifacts"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args, strict: [json: :boolean, ledger: :string])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    ledger_path = Keyword.get(opts, :ledger, ContractArtifacts.default_path())
    json? = Keyword.get(opts, :json, false)

    case ContractArtifacts.validate(ledger_path) do
      {:ok, report} ->
        print_success(report, json?)

      {:error, report} ->
        print_failure(report, json?)
        exit({:shutdown, 1})
    end
  end

  defp print_success(report, true) do
    report
    |> Map.put(:status, :pass)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_success(report, false) do
    Mix.shell().info("gn_ten.artifacts.validate passed")
    Mix.shell().info("artifacts=#{report.artifact_count}")
    Mix.shell().info("stale=#{report.stale_count}")

    Enum.each(report.warnings, fn warning ->
      Mix.shell().info("  warning: #{inspect(warning)}")
    end)
  end

  defp print_failure(report, true) do
    report
    |> Map.put(:status, :fail)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_failure(report, false) do
    Mix.shell().error("gn_ten.artifacts.validate failed")
    Enum.each(report.failures, &Mix.shell().error("  #{inspect(&1)}"))
  end
end
