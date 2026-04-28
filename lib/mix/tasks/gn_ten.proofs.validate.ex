defmodule Mix.Tasks.GnTen.Proofs.Validate do
  @moduledoc "Validates the gn-ten proof matrix ledger."

  use Mix.Task

  alias StackLab.GnTen.ProofMatrix

  @shortdoc "Validates gn-ten proof matrix"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args, strict: [json: :boolean, ledger: :string])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    ledger_path = Keyword.get(opts, :ledger, ProofMatrix.default_path())
    json? = Keyword.get(opts, :json, false)

    case ProofMatrix.validate(ledger_path) do
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
    Mix.shell().info("gn_ten.proofs.validate passed")
    Mix.shell().info("proofs=#{report.proof_count}")
    Mix.shell().info("implemented=#{report.implemented_count}")
    Mix.shell().info("missing_proof=#{report.missing_proof_count}")

    if report.highest_risk_missing_proof do
      Mix.shell().info("highest_risk_missing_proof=#{report.highest_risk_missing_proof}")
    end
  end

  defp print_failure(report, true) do
    report
    |> Map.put(:status, :fail)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_failure(report, false) do
    Mix.shell().error("gn_ten.proofs.validate failed")
    Enum.each(report.failures, &Mix.shell().error("  #{inspect(&1)}"))
  end
end
