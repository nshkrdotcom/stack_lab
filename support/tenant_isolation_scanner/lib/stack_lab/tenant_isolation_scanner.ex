defmodule StackLab.TenantIsolationScanner do
  @moduledoc """
  Tenant isolation scanner receipt contracts.
  """

  defmodule Finding do
    @moduledoc """
    Tenant isolation scanner finding.
    """
    @enforce_keys [:rule, :reason]
    @type t :: %__MODULE__{rule: atom(), reason: atom(), details: map()}
    defstruct [:rule, :reason, details: %{}]
  end

  defmodule Receipt do
    @moduledoc """
    Tenant isolation scanner receipt.
    """
    @enforce_keys [
      :receipt_ref,
      :fixture_ref,
      :scanner_ref,
      :owner_repo,
      :package_path,
      :target_code_paths,
      :status,
      :required_refs,
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
            required_refs: [atom()],
            proof_refs: [String.t()],
            scanner_refs: [String.t()],
            findings: [Finding.t()]
          }
    defstruct @enforce_keys
  end

  @fixture_ref "UAA-041"
  @scanner_ref "stack-lab.tenant-isolation-scanner.v1"

  @fact_kinds [
    :credential_lease,
    :provider_account,
    :connector_binding,
    :target_attach,
    :session,
    :event,
    :trace,
    :receipt,
    :product_projection,
    :memory_fact,
    :micro_state,
    :deployment_artifact
  ]

  @required_refs [:tenant_ref, :owner_repo, :package_path, :target_code_paths]
  @known_fields @required_refs ++ [:facts, :proof_refs, :scanner_refs]

  @spec required_refs() :: [atom()]
  def required_refs, do: @required_refs

  @spec scan(map() | keyword()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) or is_list(attrs) do
    attrs = normalize(attrs)

    with [] <- unknown_fact_kinds(attrs),
         [] <- missing_required(attrs) do
      findings = facts(attrs) |> Enum.flat_map(&fact_findings(&1, Map.fetch!(attrs, :tenant_ref)))

      {:ok,
       %Receipt{
         receipt_ref: receipt_ref(attrs),
         fixture_ref: @fixture_ref,
         scanner_ref: @scanner_ref,
         owner_repo: Map.fetch!(attrs, :owner_repo),
         package_path: Map.fetch!(attrs, :package_path),
         target_code_paths: Map.fetch!(attrs, :target_code_paths),
         status: status(findings),
         required_refs: @required_refs,
         proof_refs: List.wrap(Map.get(attrs, :proof_refs, [])),
         scanner_refs: List.wrap(Map.get(attrs, :scanner_refs, [])),
         findings: findings
       }}
    else
      {:unknown, values} -> {:error, {:unknown_tenant_fact_kinds, values}}
      missing when is_list(missing) -> {:error, {:missing_tenant_scan_refs, missing}}
    end
  end

  defp unknown_fact_kinds(attrs) do
    attrs
    |> facts()
    |> Enum.map(&Map.get(&1, :kind))
    |> Enum.reject(&(&1 in @fact_kinds))
    |> case do
      [] -> []
      values -> {:unknown, values}
    end
  end

  defp fact_findings(fact, tenant_ref) do
    []
    |> missing_tenant_finding(fact)
    |> cross_tenant_finding(fact, tenant_ref)
  end

  defp missing_tenant_finding(findings, fact) do
    if present?(Map.get(fact, :tenant_ref)) do
      findings
    else
      [finding(:tenant_scope, :missing_tenant_ref, %{kind: Map.get(fact, :kind)}) | findings]
    end
  end

  defp cross_tenant_finding(findings, fact, tenant_ref) do
    fact_tenant = Map.get(fact, :tenant_ref)

    if present?(fact_tenant) and fact_tenant != tenant_ref do
      [
        finding(:tenant_scope, :cross_tenant_ref, %{
          kind: Map.get(fact, :kind),
          tenant_ref: fact_tenant
        })
        | findings
      ]
    else
      findings
    end
  end

  defp facts(attrs), do: attrs |> Map.get(:facts, []) |> Enum.map(&normalize/1)
  defp missing_required(attrs), do: Enum.reject(@required_refs, &present?(Map.get(attrs, &1)))

  defp receipt_ref(attrs) do
    package = attrs |> Map.fetch!(:package_path) |> String.replace("/", "-")
    "tenant-isolation-receipt://#{Map.fetch!(attrs, :owner_repo)}/#{package}"
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

  defp string_key(key),
    do: Enum.find(@known_fields ++ [:kind, :ref, :secret], key, &same?(&1, key))

  defp same?(field, key), do: Atom.to_string(field) == key

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value) when is_list(value), do: value != []
  defp present?(value), do: not is_nil(value)
end
