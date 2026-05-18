defmodule Mix.Tasks.StackLab.RuntimeBoundary.Scan do
  @moduledoc """
  Runs the runtime-boundary scanner.
  """
  use Mix.Task

  alias StackLab.RuntimeBoundaryScanner

  @shortdoc "Runs the runtime-boundary scanner"

  @impl Mix.Task
  def run(args) do
    {opts, paths, invalid} =
      OptionParser.parse(args,
        strict: [
          all_target_repos: :boolean,
          baseline_ok: :boolean,
          help: :boolean,
          path: :keep,
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
    |> RuntimeBoundaryScanner.scan(mode: scan_mode(opts))
    |> handle_scan_result(opts)
  end

  defp scan_mode(opts) do
    if opts[:baseline_ok], do: :baseline, else: :hard_gate
  end

  defp handle_scan_result({:ok, receipt}, opts) do
    output = if opts[:summary], do: RuntimeBoundaryScanner.summary(receipt), else: receipt

    Mix.shell().info(
      "runtime_boundary_receipt: " <> inspect(output, pretty: true, limit: :infinity)
    )

    if receipt.status == :open_defect do
      Mix.raise("runtime-boundary gate found #{length(receipt.findings)} finding(s)")
    end
  end

  defp handle_scan_result({:error, reason}, _opts) do
    Mix.raise("runtime-boundary gate failed: #{inspect(reason)}")
  end

  defp requested_paths(opts, positional_paths) do
    option_paths = opts |> Keyword.get_values(:path) |> List.flatten()
    paths = option_paths ++ positional_paths

    cond do
      opts[:all_target_repos] -> RuntimeBoundaryScanner.all_target_paths()
      paths != [] -> paths
      true -> Mix.raise("Provide --all-target-repos or at least one --path/path argument")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix stack_lab.runtime_boundary.scan --all-target-repos [--baseline-ok] [--summary]
    mix stack_lab.runtime_boundary.scan --path /home/home/p/g/n/mezzanine/core/workspace_engine

    Use --baseline-ok only while recording runtime-boundary inventory.
    """)
  end
end
