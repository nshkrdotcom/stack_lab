defmodule StackLab.NoBypassScanner do
  @moduledoc """
  Product no-bypass scanner receipt contracts.
  """

  defmodule Finding do
    @moduledoc """
    Product no-bypass scanner finding.
    """
    @enforce_keys [:rule, :reason]
    @type t :: %__MODULE__{rule: atom(), reason: atom(), details: map()}
    defstruct [:rule, :reason, details: %{}]
  end

  defmodule Receipt do
    @moduledoc """
    Product no-bypass scanner receipt.
    """
    @enforce_keys [
      :receipt_ref,
      :fixture_ref,
      :scanner_ref,
      :owner_repo,
      :package_path,
      :target_code_paths,
      :status,
      :checked_rules,
      :approved_facade_refs,
      :proof_refs,
      :scanner_refs,
      :findings
    ]
    @type t :: %__MODULE__{
            receipt_ref: String.t(),
            fixture_ref: String.t(),
            scanner_ref: String.t(),
            owner_repo: String.t(),
            package_path: String.t(),
            target_code_paths: [String.t()],
            status: :pass | :open_defect,
            checked_rules: [atom()],
            approved_facade_refs: [String.t()],
            proof_refs: [String.t()],
            scanner_refs: [String.t()],
            findings: [Finding.t()]
          }
    defstruct @enforce_keys
  end

  @fixture_ref "UAA-043"
  @scanner_ref "stack-lab.product-no-bypass-scanner.v1"
  @rules [
    :direct_provider_sdk_calls,
    :direct_generated_sdk_calls,
    :direct_env_auth_lookup,
    :direct_runtime_mutation,
    :direct_db_access,
    :direct_trace_writes
  ]
  @known_fields [
                  :owner_repo,
                  :package_path,
                  :target_code_paths,
                  :approved_facade_refs,
                  :proof_refs,
                  :scanner_refs,
                  :signals,
                  :rules
                ] ++ @rules

  @spec rules() :: [atom()]
  def rules, do: @rules

  @spec scan(map() | keyword()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)
    requested_rules = Map.get(attrs, :rules, @rules)

    case unknown_rules(requested_rules) do
      [] ->
        signals = normalize(Map.get(attrs, :signals, %{}))
        findings = Enum.flat_map(requested_rules, &rule_findings(&1, signals))

        {:ok,
         %Receipt{
           receipt_ref: receipt_ref(attrs),
           fixture_ref: @fixture_ref,
           scanner_ref: @scanner_ref,
           owner_repo: Map.fetch!(attrs, :owner_repo),
           package_path: Map.fetch!(attrs, :package_path),
           target_code_paths: Map.fetch!(attrs, :target_code_paths),
           status: status(findings),
           checked_rules: requested_rules,
           approved_facade_refs: List.wrap(Map.get(attrs, :approved_facade_refs, [])),
           proof_refs: List.wrap(Map.get(attrs, :proof_refs, [])),
           scanner_refs: List.wrap(Map.get(attrs, :scanner_refs, [])),
           findings: findings
         }}

      values ->
        {:error, {:unknown_no_bypass_rules, values}}
    end
  end

  defp unknown_rules(rules), do: Enum.reject(rules, &(&1 in @rules))

  defp rule_findings(rule, signals) do
    case signal_fields(Map.get(signals, rule, [])) do
      [] ->
        []

      fields ->
        [finding(rule, :product_bypass_signal_present, %{field_names: fields})]
    end
  end

  defp signal_fields(value) when is_map(value), do: Map.keys(value)
  defp signal_fields(value) when is_list(value), do: value
  defp signal_fields(value) when value in [true, :present], do: [:present]
  defp signal_fields(_value), do: []

  defp receipt_ref(attrs) do
    package = attrs |> Map.fetch!(:package_path) |> String.replace("/", "-")
    "product-no-bypass-receipt://#{Map.fetch!(attrs, :owner_repo)}/#{package}"
  end

  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect
  defp finding(rule, reason, details), do: %Finding{rule: rule, reason: reason, details: details}

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {string_key(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp string_key(key), do: Enum.find(@known_fields, key, &(Atom.to_string(&1) == key))
end
