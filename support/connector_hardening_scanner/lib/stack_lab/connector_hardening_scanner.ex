defmodule StackLab.ConnectorHardeningScanner do
  @moduledoc """
  Ref-only connector hardening scanner for governed SDK paths.

  The scanner consumes explicit facts from tests, fixtures, or repo-local QC
  helpers. It records field names and proof refs, never raw credential values.
  """

  defmodule Finding do
    @moduledoc false

    @enforce_keys [:rule, :reason]
    defstruct rule: nil, reason: nil, details: %{}
  end

  defmodule Receipt do
    @moduledoc false

    @enforce_keys [
      :receipt_ref,
      :fixture_ref,
      :scanner_ref,
      :owner_repo,
      :package_path,
      :target_code_paths,
      :status,
      :checked_rules,
      :required_refs,
      :proof_refs,
      :findings
    ]
    defstruct @enforce_keys
  end

  @scanner_ref "stack-lab.connector-hardening-scanner.v1"
  @fixture_ref "UAA-042"

  @rules [
    :env_reads,
    :token_storage,
    :direct_http_clients,
    :generated_runtime_schema,
    :auth_parser,
    :operation_dispatch,
    :retries,
    :webhooks,
    :pagination,
    :telemetry,
    :binding_refs,
    :lease_refs,
    :admission_refs,
    :tenant_refs,
    :target_refs,
    :redaction_refs
  ]

  @forbidden_signal_rules [:env_reads, :token_storage, :direct_http_clients]

  @proof_rules [
    :generated_runtime_schema,
    :auth_parser,
    :operation_dispatch,
    :retries,
    :webhooks,
    :pagination,
    :telemetry
  ]

  @required_refs [
    :tenant_ref,
    :provider_account_ref,
    :connector_instance_ref,
    :credential_handle_ref,
    :credential_lease_ref,
    :target_ref,
    :request_scope_ref,
    :operation_policy_ref,
    :redaction_ref
  ]

  @ref_rule_fields %{
    binding_refs: [:provider_account_ref, :connector_instance_ref, :credential_handle_ref],
    lease_refs: [:credential_lease_ref],
    admission_refs: [:request_scope_ref, :operation_policy_ref],
    tenant_refs: [:tenant_ref],
    target_refs: [:target_ref],
    redaction_refs: [:redaction_ref]
  }

  @type rule :: atom()
  @type attrs :: map() | keyword()

  @spec rules() :: [rule()]
  def rules, do: @rules

  @spec required_refs() :: [atom()]
  def required_refs, do: @required_refs

  @spec scan(attrs()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)
    requested_rules = Map.get(attrs, :rules, @rules)

    with :ok <- validate_rules(requested_rules),
         {:ok, owner_repo} <- required_binary(attrs, :owner_repo),
         {:ok, package_path} <- required_binary(attrs, :package_path),
         {:ok, target_code_paths} <- required_list(attrs, :target_code_paths) do
      refs = normalize(Map.get(attrs, :refs, %{}))
      proof_refs = normalize(Map.get(attrs, :proof_refs, %{}))
      signals = normalize(Map.get(attrs, :signals, %{}))

      findings =
        requested_rules
        |> Enum.flat_map(&evaluate_rule(&1, refs, proof_refs, signals))
        |> Enum.reverse()

      {:ok,
       %Receipt{
         receipt_ref: receipt_ref(owner_repo, package_path),
         fixture_ref: Map.get(attrs, :fixture_ref, @fixture_ref),
         scanner_ref: @scanner_ref,
         owner_repo: owner_repo,
         package_path: package_path,
         target_code_paths: target_code_paths,
         status: status(findings),
         checked_rules: requested_rules,
         required_refs: @required_refs,
         proof_refs: proof_refs,
         findings: findings
       }}
    end
  end

  @spec receipt!(attrs()) :: Receipt.t()
  def receipt!(attrs) do
    case scan(attrs) do
      {:ok, receipt} -> receipt
      {:error, reason} -> raise ArgumentError, "invalid connector scan: #{inspect(reason)}"
    end
  end

  defp evaluate_rule(rule, _refs, _proof_refs, signals) when rule in @forbidden_signal_rules do
    case signal_fields(Map.get(signals, rule, [])) do
      [] ->
        []

      fields ->
        [
          finding(rule, :forbidden_signal_present, %{
            field_names: fields,
            count: length(fields)
          })
        ]
    end
  end

  defp evaluate_rule(rule, _refs, proof_refs, _signals) when rule in @proof_rules do
    if present?(Map.get(proof_refs, rule)) do
      []
    else
      [finding(rule, :missing_proof_ref, %{required_proof_ref: rule})]
    end
  end

  defp evaluate_rule(rule, refs, _proof_refs, _signals) do
    missing =
      rule
      |> then(&Map.fetch!(@ref_rule_fields, &1))
      |> Enum.reject(&present?(Map.get(refs, &1)))

    case missing do
      [] -> []
      fields -> [finding(rule, :missing_required_refs, %{missing_refs: fields})]
    end
  end

  defp validate_rules(rules) when is_list(rules) do
    unknown = Enum.reject(rules, &(&1 in @rules))

    case unknown do
      [] -> :ok
      invalid -> {:error, {:unknown_rules, invalid}}
    end
  end

  defp validate_rules(_rules), do: {:error, :rules_must_be_a_list}

  defp required_binary(attrs, field) do
    case Map.get(attrs, field) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value -> {:error, {:missing_required_field, field, value}}
    end
  end

  defp required_list(attrs, field) do
    case Map.get(attrs, field) do
      [_ | _] = values -> {:ok, values}
      value -> {:error, {:missing_required_field, field, value}}
    end
  end

  defp normalize(attrs) when is_list(attrs), do: attrs |> Map.new() |> normalize()

  defp normalize(attrs) when is_map(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {string_key_to_atom(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp string_key_to_atom(key) do
    candidates = @rules ++ @required_refs ++ [:owner_repo, :package_path, :target_code_paths]

    Enum.find(candidates, key, fn candidate -> Atom.to_string(candidate) == key end)
  end

  defp signal_fields(value) when is_map(value), do: Map.keys(value)
  defp signal_fields(value) when is_list(value), do: value
  defp signal_fields(value) when value in [true, :present], do: [:present]
  defp signal_fields(_value), do: []

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value), do: not is_nil(value)

  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp finding(rule, reason, details), do: %Finding{rule: rule, reason: reason, details: details}

  defp receipt_ref(owner_repo, package_path) do
    path = String.replace(package_path, "/", "-")
    "connector-hardening-receipt://#{owner_repo}/#{path}"
  end
end
