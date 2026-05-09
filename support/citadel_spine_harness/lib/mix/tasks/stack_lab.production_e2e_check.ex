defmodule Mix.Tasks.StackLab.ProductionE2ECheck do
  @moduledoc """
  Runs the StackLab Extravaganza production-path acceptance check.
  """

  use Mix.Task

  alias StackLab.CitadelSpineHarness.ProductionE2E

  @shortdoc "Run the Extravaganza production E2E acceptance check"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case run_check(args) do
      {:ok, receipt} ->
        Mix.shell().info("Production E2E check passed")
        Mix.shell().info("receipt_file=#{receipt.receipt_path}")
        Mix.shell().info("scenario_id=#{receipt.scenario_id}")
        Mix.shell().info("runtime_profile=#{receipt.runtime_profile.runtime_profile_ref}")

      {:error, reason} ->
        Mix.raise("Production E2E check failed: #{inspect(reason)}")
    end
  end

  defp run_check(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          receipt_file: :string,
          live_provider_mutation: :boolean,
          authorize_live_provider_mutation: :boolean
        ]
      )

    case invalid do
      [] ->
        case_name =
          if opts[:live_provider_mutation],
            do: :live_provider_mutation,
            else: :deterministic_offline_fixture

        run_opts = [
          receipt_path: opts[:receipt_file] || "priv/receipts/production_e2e_receipt_v1.json",
          live_provider_mutation_authorized?: opts[:authorize_live_provider_mutation] == true
        ]

        with {:ok, receipt} <- ProductionE2E.run_case(case_name, run_opts),
             :ok <- write_receipt(receipt.receipt_path, receipt) do
          {:ok, receipt}
        end

      invalid ->
        {:error, {:invalid_options, invalid}}
    end
  end

  defp write_receipt(path, receipt) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, json} <- Jason.encode(receipt, pretty: true) do
      File.write(path, json <> "\n")
    end
  end
end
