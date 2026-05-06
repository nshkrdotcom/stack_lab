defmodule StackLab.OptimizationFabricScanner.Finding do
  @moduledoc "Optimization fabric scanner finding."
  @enforce_keys [:rule, :reason, :path]
  defstruct [:details | @enforce_keys]
  @type t :: %__MODULE__{}
end

defmodule StackLab.OptimizationFabricScanner.Receipt do
  @moduledoc "Optimization fabric scanner receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_refs,
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

defmodule StackLab.OptimizationFabricScanner do
  @moduledoc """
  Governed GEPA optimization fabric scanner.
  """

  alias StackLab.OptimizationFabricScanner.{Finding, Receipt}

  @fixture_refs ["AOC-018", "AOC-019", "AOC-042"]
  @scanner_ref "stack-lab.optimization-fabric-scanner.v1"
  @rules [
    :candidate_lineage_refs,
    :eval_dataset_refs,
    :proposer_model_ref,
    :promotion_gate_refs,
    :budget_refs,
    :trace_refs,
    :promotion_refs,
    :rollback_refs,
    :provenance_refs
  ]
  @required_string_rules [:proposer_model_ref]

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = Map.get(attrs, :owner_repo, "stack_lab")
    package_path = Map.get(attrs, :package_path, "unknown")

    findings =
      attrs
      |> Map.get(:optimization_facts, [])
      |> List.wrap()
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {fact, index} -> fact_findings(fact, index) end)

    {:ok,
     %Receipt{
       receipt_ref: receipt_ref(owner_repo, package_path),
       fixture_refs: @fixture_refs,
       scanner_ref: @scanner_ref,
       owner_repo: owner_repo,
       package_path: package_path,
       status: status(findings),
       checked_rules: @rules,
       findings: findings
     }}
  end

  def scan(_attrs), do: {:error, :invalid_optimization_fabric_scan}

  defp fact_findings(fact, index) when is_map(fact) do
    path = "optimization_fact:" <> Integer.to_string(index)

    required_findings =
      Enum.flat_map(@rules, fn field ->
        if required_value_present?(fact, field) do
          []
        else
          [finding(field, missing_reason(field), path, %{})]
        end
      end)

    required_findings ++ redaction_findings(fact, path)
  end

  defp fact_findings(_fact, index) do
    [finding(:candidate_lineage_refs, :invalid_optimization_fact, fact_path(index), %{})]
  end

  defp redaction_findings(fact, path) do
    if fetch(fact, :trace_redaction, :redacted) == :redacted do
      []
    else
      [finding(:trace_refs, :trace_refs_not_redacted, path, %{})]
    end
  end

  defp required_value_present?(fact, field) when field in @required_string_rules do
    present_string?(fetch(fact, field))
  end

  defp required_value_present?(fact, field), do: non_empty_string_list?(fetch(fact, field))

  defp missing_reason(field) when field in @required_string_rules, do: :missing_required_ref
  defp missing_reason(_field), do: :missing_required_refs

  defp non_empty_string_list?(values) when is_list(values) and values != [] do
    Enum.all?(values, &present_string?/1)
  end

  defp non_empty_string_list?(_values), do: false
  defp present_string?(value), do: is_binary(value) and String.trim(value) != ""

  defp fetch(fact, field, default \\ nil) do
    string_field = Atom.to_string(field)

    cond do
      Map.has_key?(fact, field) -> Map.fetch!(fact, field)
      Map.has_key?(fact, string_field) -> Map.fetch!(fact, string_field)
      true -> default
    end
  end

  defp fact_path(index), do: "optimization_fact:" <> Integer.to_string(index)
  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp receipt_ref(owner_repo, package_path),
    do: "optimization-fabric-scan://#{owner_repo}/#{package_path}"

  defp finding(rule, reason, path, details),
    do: %Finding{rule: rule, reason: reason, path: path, details: details}
end
