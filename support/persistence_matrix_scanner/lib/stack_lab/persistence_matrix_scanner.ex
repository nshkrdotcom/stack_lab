defmodule StackLab.PersistenceMatrixScanner.Finding do
  @moduledoc "Persistence matrix scanner finding."
  @enforce_keys [:rule, :reason, :path]
  defstruct [:details | @enforce_keys]
  @type t :: %__MODULE__{}
end

defmodule StackLab.PersistenceMatrixScanner.Receipt do
  @moduledoc "Persistence matrix scanner receipt."
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

defmodule StackLab.PersistenceMatrixScanner do
  @moduledoc """
  Persistence profile matrix scanner.

  The scanner consumes structured facts from deterministic harnesses. It does
  not inspect live infrastructure or own release truth by itself.
  """

  alias GroundPlane.PersistencePolicy
  alias StackLab.PersistenceMatrixScanner.{Finding, Receipt}

  @fixture_refs ["PERSIST-001", "PERSIST-015", "PERSIST-016", "PERSIST-020"]
  @scanner_ref "stack-lab.persistence-matrix-scanner.v1"
  @rules [
    :memory_default,
    :no_default_postgres,
    :temporal_disabled_by_default,
    :optional_external_substrate_disabled_by_default,
    :debug_redaction,
    :durable_opt_in_tag,
    :knob_docs,
    :product_no_bypass,
    :gn_ten_profile_field,
    :gn_ten_tier_field,
    :gn_ten_store_field,
    :gn_ten_capture_field,
    :gn_ten_proof_command_field
  ]
  @gn_ten_fields [
    {:gn_ten_profile_field, :selected_persistence_profile},
    {:gn_ten_tier_field, :selected_tier},
    {:gn_ten_store_field, :store_set_id},
    {:gn_ten_capture_field, :capture_level},
    {:gn_ten_proof_command_field, :proof_command}
  ]

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = Map.get(attrs, :owner_repo, "stack_lab")
    package_path = Map.get(attrs, :package_path, "unknown")
    facts = attrs |> Map.get(:persistence_facts, []) |> List.wrap()

    findings =
      facts
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {fact, index} -> fact_findings(fact, index) end)
      |> Kernel.++(matrix_findings(facts))

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

  def scan(_attrs), do: {:error, :invalid_persistence_matrix_scan}

  defp fact_findings(fact, index) when is_map(fact) do
    path = fact_path(index)

    []
    |> Kernel.++(default_substrate_findings(fact, path))
    |> Kernel.++(memory_fact_findings(fact, path))
    |> Kernel.++(durable_fact_findings(fact, path))
    |> Kernel.++(debug_findings(fact, path))
    |> Kernel.++(knob_doc_findings(fact, path))
    |> Kernel.++(product_no_bypass_findings(fact, path))
    |> Kernel.++(gn_ten_findings(fact, path))
  end

  defp fact_findings(_fact, index) do
    [finding(:memory_default, :invalid_persistence_fact, fact_path(index), %{})]
  end

  defp matrix_findings(facts) do
    [
      if Enum.any?(facts, &memory_profile_fact?/1) do
        nil
      else
        finding(:memory_default, :missing_mickey_mouse_fact, "matrix", %{})
      end,
      if Enum.any?(facts, &durable_profile_fact?/1) do
        nil
      else
        finding(:durable_opt_in_tag, :missing_durable_fact, "matrix", %{})
      end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp default_substrate_findings(fact, path) do
    [
      if fetch(fact, :postgres_required_by_default?, false) do
        finding(:no_default_postgres, :postgres_required_by_default, path, %{})
      end,
      if fetch(fact, :temporal_required_by_default?, false) do
        finding(:temporal_disabled_by_default, :temporal_required_by_default, path, %{})
      end,
      if fetch(fact, :optional_external_required_by_default?, false) do
        finding(
          :optional_external_substrate_disabled_by_default,
          :optional_external_required_by_default,
          path,
          %{}
        )
      end
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp memory_fact_findings(fact, path) do
    if memory_profile_fact?(fact) do
      [
        unless fetch(fact, :selected_tier) == :memory_ephemeral do
          finding(:memory_default, :memory_default_tier_not_memory, path, %{})
        end,
        unless fetch(fact, :memory_default?) == true do
          finding(:memory_default, :memory_default_flag_missing, path, %{})
        end
      ]
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp durable_fact_findings(fact, path) do
    if durable_profile_fact?(fact) do
      [
        unless fetch(fact, :durable_opt_in?) == true do
          finding(:durable_opt_in_tag, :durable_opt_in_missing, path, %{})
        end,
        unless present_value?(fetch(fact, :durable_tag)) do
          finding(:durable_opt_in_tag, :durable_tag_missing, path, %{})
        end
      ]
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp debug_findings(fact, path) do
    redaction =
      if fetch(fact, :debug_capture_redacted?) == true do
        []
      else
        [finding(:debug_redaction, :debug_capture_not_redacted, path, %{})]
      end

    case raw_key(fact) do
      nil -> redaction
      key -> [finding(:debug_redaction, {:forbidden_raw_field, key}, path, %{}) | redaction]
    end
  end

  defp knob_doc_findings(fact, path) do
    docs = List.wrap(fetch(fact, :knob_docs, []))

    cond do
      docs == [] ->
        [finding(:knob_docs, :missing_knob_docs, path, %{})]

      Enum.all?(docs, &complete_knob_doc?/1) ->
        []

      true ->
        [finding(:knob_docs, :incomplete_knob_doc, path, %{})]
    end
  end

  defp product_no_bypass_findings(fact, path) do
    case List.wrap(fetch(fact, :product_direct_lower_store_imports, [])) do
      [] ->
        []

      imports ->
        [finding(:product_no_bypass, :direct_lower_store_import, path, %{imports: imports})]
    end
  end

  defp gn_ten_findings(fact, path) do
    receipt = fetch(fact, :gn_ten_receipt, %{})

    Enum.flat_map(@gn_ten_fields, fn {rule, field} ->
      if present_value?(fetch(receipt, field)) do
        []
      else
        [finding(rule, :missing_gn_ten_field, path, %{field: field})]
      end
    end)
  end

  defp complete_knob_doc?(doc) when is_map(doc) do
    Enum.all?([:name, :type, :default, :validation, :examples, :test_refs], fn field ->
      present_value?(fetch(doc, field))
    end)
  end

  defp complete_knob_doc?(_doc), do: false

  defp memory_profile_fact?(fact) when is_map(fact), do: fetch(fact, :profile_id) == :mickey_mouse
  defp memory_profile_fact?(_fact), do: false

  defp durable_profile_fact?(fact) when is_map(fact) do
    fact
    |> fetch(:selected_tier)
    |> PersistencePolicy.Tier.durable?()
  end

  defp durable_profile_fact?(_fact), do: false

  defp raw_key(%_struct{} = value), do: value |> Map.from_struct() |> raw_key()

  defp raw_key(value) when is_map(value) do
    Enum.find_value(value, fn {key, nested} ->
      if key in PersistencePolicy.Redaction.forbidden_keys() do
        key
      else
        raw_key(nested)
      end
    end)
  end

  defp raw_key(values) when is_list(values), do: Enum.find_value(values, &raw_key/1)
  defp raw_key(_value), do: nil

  defp present_value?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_value?(value) when is_list(value), do: value != []
  defp present_value?(nil), do: false
  defp present_value?(_value), do: true

  defp fetch(fact, field, default \\ nil) do
    string_field = Atom.to_string(field)

    cond do
      is_map(fact) and Map.has_key?(fact, field) -> Map.fetch!(fact, field)
      is_map(fact) and Map.has_key?(fact, string_field) -> Map.fetch!(fact, string_field)
      true -> default
    end
  end

  defp fact_path(index), do: "persistence_fact:" <> Integer.to_string(index)
  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp receipt_ref(owner_repo, package_path),
    do: "persistence-matrix-scan://#{owner_repo}/#{package_path}"

  defp finding(rule, reason, path, details),
    do: %Finding{rule: rule, reason: reason, path: path, details: details}
end
