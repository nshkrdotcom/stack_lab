defmodule StackLab.AIRunLineageScanner.Finding do
  @moduledoc "AI run lineage scanner finding."
  @enforce_keys [:rule, :reason, :path]
  defstruct [:details | @enforce_keys]
  @type t :: %__MODULE__{}
end

defmodule StackLab.AIRunLineageScanner.Receipt do
  @moduledoc "AI run lineage scanner receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_ref,
    :scanner_ref,
    :owner_repo,
    :package_path,
    :status,
    :checked_rules,
    :findings
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.AIRunLineageScanner do
  @moduledoc """
  AI run lineage scanner for adaptive optimization proofs.
  """

  alias StackLab.AIRunLineageScanner.{Finding, Receipt}

  @fixture_ref "AOC-001/AOC-002 phase-8-lineage"
  @scanner_ref "stack-lab.ai-run-lineage-scanner.v1"
  @required_string_rules [
    :ai_run_ref,
    :tenant_ref,
    :authority_ref,
    :parent_run_ref,
    :idempotency_ref,
    :persistence_profile_ref
  ]
  @required_list_rules [:optimization_refs, :trace_refs]
  @rules @required_string_rules ++ @required_list_rules

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = Map.get(attrs, :owner_repo, "stack_lab")
    package_path = Map.get(attrs, :package_path, "unknown")

    findings =
      attrs
      |> Map.get(:run_facts, [])
      |> List.wrap()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {fact, index} -> fact_findings(fact, index) end)

    {:ok,
     %Receipt{
       receipt_ref: receipt_ref(owner_repo, package_path),
       fixture_ref: @fixture_ref,
       scanner_ref: @scanner_ref,
       owner_repo: owner_repo,
       package_path: package_path,
       status: status(findings),
       checked_rules: @rules,
       findings: findings
     }}
  end

  def scan(_attrs), do: {:error, :invalid_ai_run_lineage_scan}

  defp fact_findings(fact, index) when is_map(fact) do
    path = "run_fact:" <> Integer.to_string(index)

    string_findings =
      Enum.flat_map(@required_string_rules, fn field ->
        if present_string?(fetch(fact, field)) do
          []
        else
          [finding(field, :missing_required_ref, path, %{})]
        end
      end)

    list_findings =
      Enum.flat_map(@required_list_rules, fn field ->
        if non_empty_string_list?(fetch(fact, field)) do
          []
        else
          [finding(field, :missing_required_refs, path, %{})]
        end
      end)

    string_findings ++ list_findings
  end

  defp fact_findings(_fact, index),
    do: [finding(:ai_run_ref, :invalid_run_fact, "run_fact:" <> Integer.to_string(index), %{})]

  defp non_empty_string_list?(values) when is_list(values) and values != [] do
    Enum.all?(values, &present_string?/1)
  end

  defp non_empty_string_list?(_values), do: false
  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp fetch(fact, field) do
    string_field = Atom.to_string(field)

    cond do
      Map.has_key?(fact, field) -> Map.fetch!(fact, field)
      Map.has_key?(fact, string_field) -> Map.fetch!(fact, string_field)
      true -> nil
    end
  end

  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp receipt_ref(owner_repo, package_path),
    do: "ai-run-lineage-scan://#{owner_repo}/#{package_path}"

  defp finding(rule, reason, path, details),
    do: %Finding{rule: rule, reason: reason, path: path, details: details}
end
