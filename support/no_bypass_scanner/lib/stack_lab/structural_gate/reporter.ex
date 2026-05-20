defmodule StackLab.StructuralGate.Reporter do
  @moduledoc """
  Receipt summary helpers for the structural scanner.
  """

  alias StackLab.StructuralGateScanner.Receipt

  @spec summary(Receipt.t()) :: map()
  def summary(%Receipt{} = receipt) do
    %{
      scanner: receipt.scanner,
      scanner_version: receipt.scanner_version,
      mode: receipt.mode,
      status: receipt.status,
      target_scope_status: receipt.target_scope_status,
      target_repos: receipt.target_roots |> Map.keys() |> Enum.sort(),
      checked_path_count: length(receipt.checked_paths),
      skipped_path_count: length(receipt.skipped_paths),
      zones: receipt.zones,
      finding_count: length(receipt.findings),
      findings_by_rule: count_by(receipt.findings, & &1.rule),
      proof_bundle_count: length(receipt.proof_bundles),
      proof_bundles_by_status: count_by(receipt.proof_bundles, & &1.status),
      proof_bundles_by_entrypoint_kind: count_by(receipt.proof_bundles, & &1.entrypoint_kind),
      proof_bundles_by_operation: count_by(receipt.proof_bundles, & &1.operation_name),
      remote_boundary: receipt.remote_boundary
    }
  end

  defp count_by(values, fun) do
    Enum.reduce(values, %{}, fn value, counts ->
      Map.update(counts, fun.(value), 1, &(&1 + 1))
    end)
  end
end
