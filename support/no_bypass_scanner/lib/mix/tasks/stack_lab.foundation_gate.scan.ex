defmodule Mix.Tasks.StackLab.FoundationGate.Scan do
  @moduledoc """
  Runs the Phase 0A foundation gate scanner.
  """
  use Mix.Task

  alias StackLab.FoundationGateScanner

  @shortdoc "Runs the Phase 0A foundation gate scanner"

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

    cond do
      opts[:help] ->
        print_help()

      invalid != [] ->
        Mix.raise("Invalid options: #{inspect(invalid)}")

      true ->
        scan_paths = requested_paths(opts, paths)
        mode = if opts[:baseline_ok], do: :baseline, else: :hard_gate

        case FoundationGateScanner.scan(scan_paths, mode: mode) do
          {:ok, receipt} ->
            output = if opts[:summary], do: FoundationGateScanner.summary(receipt), else: receipt
            IO.inspect(output, label: "foundation_gate_receipt", pretty: true, limit: :infinity)

            if receipt.status == :open_defect do
              Mix.raise("foundation gate found #{length(receipt.findings)} finding(s)")
            end

          {:error, reason} ->
            Mix.raise("foundation gate failed: #{inspect(reason)}")
        end
    end
  end

  defp requested_paths(opts, positional_paths) do
    option_paths = opts |> Keyword.get_values(:path) |> List.flatten()
    paths = option_paths ++ positional_paths

    cond do
      opts[:all_target_repos] -> FoundationGateScanner.all_target_paths()
      paths != [] -> paths
      true -> Mix.raise("Provide --all-target-repos or at least one --path/path argument")
    end
  end

  defp print_help do
    Mix.shell().info("""
    mix stack_lab.foundation_gate.scan --all-target-repos [--baseline-ok] [--summary]
    mix stack_lab.foundation_gate.scan --path /home/home/p/g/n/app_kit/core/app_kit_core

    Use --baseline-ok only for the Phase 0A current-state inventory. Phase work must run
    this scanner without --baseline-ok against touched/new foundation paths.
    """)
  end
end
