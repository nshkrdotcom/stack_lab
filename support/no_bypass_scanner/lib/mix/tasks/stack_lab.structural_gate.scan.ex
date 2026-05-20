defmodule Mix.Tasks.StackLab.StructuralGate.Scan do
  @moduledoc """
  Runs the Phase 6A structural scanner gate.
  """
  use Mix.Task

  alias StackLab.StructuralGate.TargetRoots
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
          summary: :boolean,
          target_root: :keep
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
      remote_deployment?: opts[:remote_deployment] == true,
      target_roots: target_roots(opts)
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
      opts[:all_target_repos] ->
        opts |> target_roots() |> TargetRoots.all_paths()

      paths != [] ->
        paths

      true ->
        Mix.raise("Provide --all-target-repos or at least one --path/path argument")
    end
  end

  defp target_roots(opts) do
    case Keyword.get_values(opts, :target_root) do
      [] -> StructuralGateScanner.target_roots()
      roots -> parse_target_roots!(roots)
    end
  end

  defp parse_target_roots!(roots) do
    roots
    |> Enum.map(&parse_target_root!/1)
    |> Map.new()
  end

  defp parse_target_root!(value) do
    case String.split(value, "=", parts: 2) do
      [repo, path] when repo != "" and path != "" -> {repo, path}
      _ -> Mix.raise("Invalid --target-root #{inspect(value)}; expected repo=/absolute/path")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix stack_lab.structural_gate.scan --all-target-repos [--baseline-ok] [--summary]
    mix stack_lab.structural_gate.scan --path /home/home/p/g/n/app_kit/core/app_kit_core
    mix stack_lab.structural_gate.scan --target-root app_kit=/tmp/app_kit --path /tmp/app_kit/core

    Use --baseline-ok for current legacy inventory only. Phase work must run this scanner
    without --baseline-ok against touched generic paths.
    """)
  end
end
