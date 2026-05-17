defmodule Mix.Tasks.StackLab.StructuralGate.Scan do
  @moduledoc """
  Runs the Phase 6A structural scanner gate.
  """
  use Mix.Task

  alias StackLab.StructuralGateScanner

  @shortdoc "Runs the Phase 6A structural scanner gate"

  @impl Mix.Task
  def run(args) do
    {opts, paths, invalid} =
      OptionParser.parse(args,
        strict: [
          all_target_repos: :boolean,
          baseline_ok: :boolean,
          help: :boolean,
          path: :keep,
          remote_deployment: :boolean,
          summary: :boolean
        ]
      )

    if opts[:help] do
      print_help()
    else
      run_scan(opts, paths, invalid)
    end
  end

  defp run_scan(_opts, _paths, invalid) when invalid != [] do
    Mix.raise("Invalid options: #{inspect(invalid)}")
  end

  defp run_scan(opts, paths, _invalid) do
    opts
    |> requested_paths(paths)
    |> StructuralGateScanner.scan(
      mode: scan_mode(opts),
      remote_deployment?: opts[:remote_deployment] == true
    )
    |> handle_scan_result(opts)
  end

  defp scan_mode(opts) do
    if opts[:baseline_ok], do: :baseline, else: :hard_gate
  end

  defp handle_scan_result({:ok, receipt}, opts) do
    output = if opts[:summary], do: StructuralGateScanner.summary(receipt), else: receipt

    Mix.shell().info(
      "structural_gate_receipt: " <> inspect(output, pretty: true, limit: :infinity)
    )

    if receipt.status == :open_defect do
      Mix.raise("structural gate found #{length(receipt.findings)} finding(s)")
    end
  end

  defp handle_scan_result({:error, reason}, _opts) do
    Mix.raise("structural gate failed: #{inspect(reason)}")
  end

  defp requested_paths(opts, positional_paths) do
    option_paths = opts |> Keyword.get_values(:path) |> List.flatten()
    paths = option_paths ++ positional_paths

    cond do
      opts[:all_target_repos] -> StructuralGateScanner.all_target_paths()
      paths != [] -> paths
      true -> Mix.raise("Provide --all-target-repos or at least one --path/path argument")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix stack_lab.structural_gate.scan --all-target-repos [--baseline-ok] [--summary]
    mix stack_lab.structural_gate.scan --path /home/home/p/g/n/app_kit/core/app_kit_core

    Use --baseline-ok for current legacy inventory only. Phase work must run this scanner
    without --baseline-ok against touched generic paths.
    """)
  end
end
