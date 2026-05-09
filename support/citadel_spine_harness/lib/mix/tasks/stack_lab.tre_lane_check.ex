defmodule Mix.Tasks.StackLab.TreLaneCheck do
  @moduledoc """
  Runs the neutral StackLab TRE lower-lane acceptance check.
  """

  use Mix.Task

  alias StackLab.CitadelSpineHarness.TreLaneAcceptance

  @shortdoc "Run the neutral TRE lower-lane acceptance check"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case run_check(args) do
      {:ok, receipt} ->
        Mix.shell().info("TRE lane check passed")
        Mix.shell().info("receipt_file=#{receipt.receipt_path}")
        Mix.shell().info("scenario_id=#{receipt.scenario_id}")
        Mix.shell().info("runtime_profile=#{receipt.runtime_profile.runtime_profile_ref}")

      {:error, reason} ->
        Mix.raise("TRE lane check failed: #{inspect(reason)}")
    end
  end

  @doc false
  def run_check(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [
          receipt_file: :string,
          runner_path: :string
        ]
      )

    case invalid do
      [] ->
        run_opts = runner_opts(opts)

        case_name =
          if opts[:runner_path], do: :installed_rex_runner, else: :deterministic_fixture_runner

        with {:ok, receipt} <- TreLaneAcceptance.run_case(case_name, run_opts),
             receipt <- Map.put(receipt, :receipt_path, receipt_path(opts)),
             :ok <- write_receipt(receipt.receipt_path, receipt) do
          {:ok, receipt}
        end

      invalid ->
        {:error, {:invalid_options, invalid}}
    end
  end

  defp runner_opts(opts) do
    case opts[:runner_path] do
      nil -> []
      runner_path -> [runner_path: runner_path]
    end
  end

  defp receipt_path(opts), do: opts[:receipt_file] || "priv/receipts/tre_lane_receipt_v1.json"

  defp write_receipt(path, receipt) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, json} <- Jason.encode(receipt, pretty: true) do
      File.write(path, json <> "\n")
    end
  end
end
