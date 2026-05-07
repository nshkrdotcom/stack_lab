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
    :fixture_mappings,
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

  @fixture_refs [
    "PERSIST-001",
    "PERSIST-002",
    "PERSIST-003",
    "PERSIST-004",
    "PERSIST-005",
    "PERSIST-006",
    "PERSIST-007",
    "PERSIST-008",
    "PERSIST-009",
    "PERSIST-010",
    "PERSIST-011",
    "PERSIST-012",
    "PERSIST-013",
    "PERSIST-014",
    "PERSIST-015",
    "PERSIST-016",
    "PERSIST-017",
    "PERSIST-018",
    "PERSIST-019",
    "PERSIST-020"
  ]
  @required_profiles [:mickey_mouse, :memory_debug, :integration_postgres, :full_debug_tracked]
  @scanner_ref "stack-lab.persistence-matrix-scanner.v2"
  @rules [
    :memory_default,
    :no_default_provider,
    :no_default_postgres,
    :temporal_disabled_by_default,
    :no_default_object_store,
    :no_default_network,
    :optional_external_substrate_disabled_by_default,
    :no_default_debug_sidecar,
    :debug_redaction,
    :durable_opt_in_tag,
    :knob_docs,
    :product_no_bypass,
    :gn_ten_profile_field,
    :gn_ten_tier_field,
    :gn_ten_store_field,
    :gn_ten_capture_field,
    :gn_ten_proof_command_field,
    :profile_coverage,
    :storage_behavior_switch,
    :authority_semantics_stable,
    :restart_claim_classification,
    :complete_fixture_mapping
  ]
  @gn_ten_fields [
    {:gn_ten_profile_field, :selected_persistence_profile},
    {:gn_ten_tier_field, :selected_tier},
    {:gn_ten_store_field, :store_set_id},
    {:gn_ten_capture_field, :capture_level},
    {:gn_ten_proof_command_field, :proof_command}
  ]
  @fixture_mapping_fields [
    :fixture_ref,
    :source_paths,
    :test_paths,
    :scanner_rules,
    :docs_paths,
    :receipt_paths
  ]

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = fetch(attrs, :owner_repo, "stack_lab")
    package_path = fetch(attrs, :package_path, "unknown")
    facts = attrs |> fetch(:persistence_facts, []) |> List.wrap()
    fixture_mappings = attrs |> fetch(:fixture_mappings, []) |> List.wrap()

    findings =
      facts
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {fact, index} -> fact_findings(fact, index) end)
      |> Kernel.++(matrix_findings(facts))
      |> Kernel.++(fixture_mapping_findings(fixture_mappings))

    {:ok,
     %Receipt{
       receipt_ref: receipt_ref(owner_repo, package_path),
       fixture_refs: @fixture_refs,
       fixture_mappings: fixture_mappings,
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
    |> Kernel.++(storage_behavior_fact_findings(fact, path))
    |> Kernel.++(authority_semantics_fact_findings(fact, path))
    |> Kernel.++(restart_claim_fact_findings(fact, path))
  end

  defp fact_findings(_fact, index) do
    [finding(:memory_default, :invalid_persistence_fact, fact_path(index), %{})]
  end

  defp matrix_findings(facts) do
    []
    |> Kernel.++(memory_matrix_findings(facts))
    |> Kernel.++(profile_coverage_findings(facts))
    |> Kernel.++(storage_behavior_switch_findings(facts))
    |> Kernel.++(authority_semantics_stable_findings(facts))
  end

  defp memory_matrix_findings(facts) do
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

  defp profile_coverage_findings(facts) do
    profiles =
      facts
      |> Enum.filter(&is_map/1)
      |> Enum.map(&fetch(&1, :profile_id))
      |> MapSet.new()

    @required_profiles
    |> Enum.reject(&MapSet.member?(profiles, &1))
    |> Enum.map(fn profile ->
      finding(:profile_coverage, {:missing_profile, profile}, "matrix", %{})
    end)
  end

  defp storage_behavior_switch_findings(facts) do
    memory_refs = storage_behavior_refs(facts, :memory)
    durable_refs = storage_behavior_refs(facts, :durable)

    cond do
      memory_refs == [] or durable_refs == [] ->
        [
          finding(
            :storage_behavior_switch,
            :missing_memory_or_durable_storage_behavior,
            "matrix",
            %{}
          )
        ]

      storage_behavior_changed?(memory_refs, durable_refs) ->
        []

      true ->
        [finding(:storage_behavior_switch, :storage_behavior_not_changed, "matrix", %{})]
    end
  end

  defp authority_semantics_stable_findings(facts) do
    valid_facts = Enum.filter(facts, &is_map/1)
    refs = Enum.map(valid_facts, &fetch(&1, :authority_semantics_ref))

    cond do
      valid_facts == [] ->
        [finding(:authority_semantics_stable, :missing_authority_semantics_ref, "matrix", %{})]

      Enum.any?(refs, &(not present_value?(&1))) ->
        [finding(:authority_semantics_stable, :missing_authority_semantics_ref, "matrix", %{})]

      refs |> MapSet.new() |> MapSet.size() == 1 ->
        []

      true ->
        [finding(:authority_semantics_stable, :authority_semantics_changed, "matrix", %{})]
    end
  end

  defp default_substrate_findings(fact, path) do
    [
      if fetch(fact, :provider_dependency_by_default?, false) do
        finding(:no_default_provider, :provider_dependency_by_default, path, %{})
      end,
      if fetch(fact, :postgres_required_by_default?, false) do
        finding(:no_default_postgres, :postgres_required_by_default, path, %{})
      end,
      if fetch(fact, :temporal_required_by_default?, false) do
        finding(:temporal_disabled_by_default, :temporal_required_by_default, path, %{})
      end,
      if fetch(fact, :object_store_required_by_default?, false) do
        finding(:no_default_object_store, :object_store_required_by_default, path, %{})
      end,
      if fetch(fact, :network_required_by_default?, false) do
        finding(:no_default_network, :network_required_by_default, path, %{})
      end,
      if fetch(fact, :debug_sidecar_required_by_default?, false) do
        finding(:no_default_debug_sidecar, :debug_sidecar_required_by_default, path, %{})
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

  defp storage_behavior_fact_findings(fact, path) do
    if present_value?(fetch(fact, :storage_behavior_ref)) do
      []
    else
      [finding(:storage_behavior_switch, :missing_storage_behavior_ref, path, %{})]
    end
  end

  defp authority_semantics_fact_findings(fact, path) do
    if present_value?(fetch(fact, :authority_semantics_ref)) do
      []
    else
      [finding(:authority_semantics_stable, :missing_authority_semantics_ref, path, %{})]
    end
  end

  defp restart_claim_fact_findings(fact, path) do
    tier = fetch(fact, :selected_tier)
    claim = fetch(fact, :restart_claim)

    cond do
      not present_value?(claim) ->
        [finding(:restart_claim_classification, :missing_restart_claim, path, %{})]

      tier == :memory_ephemeral and claim != :none ->
        [
          finding(
            :restart_claim_classification,
            :memory_profile_claimed_restart_safety,
            path,
            %{restart_claim: claim}
          )
        ]

      PersistencePolicy.Tier.durable?(tier) and claim == :none ->
        [
          finding(
            :restart_claim_classification,
            :durable_profile_missing_restart_claim,
            path,
            %{}
          )
        ]

      true ->
        []
    end
  end

  defp fixture_mapping_findings(fixture_mappings) do
    []
    |> Kernel.++(missing_fixture_mapping_findings(fixture_mappings))
    |> Kernel.++(invalid_fixture_mapping_findings(fixture_mappings))
  end

  defp missing_fixture_mapping_findings(fixture_mappings) do
    mapped_refs =
      fixture_mappings
      |> Enum.filter(&is_map/1)
      |> Enum.map(&fetch(&1, :fixture_ref))
      |> MapSet.new()

    @fixture_refs
    |> Enum.reject(&MapSet.member?(mapped_refs, &1))
    |> Enum.map(fn fixture_ref ->
      finding(
        :complete_fixture_mapping,
        {:missing_fixture_mapping, fixture_ref},
        "fixture_mappings",
        %{}
      )
    end)
  end

  defp invalid_fixture_mapping_findings(fixture_mappings) do
    fixture_mappings
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {mapping, index} -> invalid_fixture_mapping_findings(mapping, index) end)
  end

  defp invalid_fixture_mapping_findings(mapping, _index) when is_map(mapping) do
    fixture_ref = fetch(mapping, :fixture_ref, "unknown")
    path = "fixture_mapping:" <> to_string(fixture_ref)

    unknown_ref =
      if fixture_ref in @fixture_refs do
        []
      else
        [
          finding(
            :complete_fixture_mapping,
            {:unknown_fixture_mapping, fixture_ref},
            path,
            %{}
          )
        ]
      end

    missing_fields =
      @fixture_mapping_fields
      |> Enum.reject(fn field -> present_value?(fetch(mapping, field)) end)
      |> Enum.map(fn field ->
        finding(
          :complete_fixture_mapping,
          {:incomplete_fixture_mapping, field},
          path,
          %{fixture_ref: fixture_ref}
        )
      end)

    unknown_ref ++ missing_fields
  end

  defp invalid_fixture_mapping_findings(_mapping, index) do
    [
      finding(
        :complete_fixture_mapping,
        :invalid_fixture_mapping,
        "fixture_mapping:" <> Integer.to_string(index),
        %{}
      )
    ]
  end

  defp complete_knob_doc?(doc) when is_map(doc) do
    Enum.all?([:name, :type, :default, :validation, :examples, :test_refs], fn field ->
      present_value?(fetch(doc, field))
    end)
  end

  defp complete_knob_doc?(_doc), do: false

  defp storage_behavior_refs(facts, :memory) do
    facts
    |> Enum.filter(&memory_tier_fact?/1)
    |> Enum.map(&fetch(&1, :storage_behavior_ref))
    |> Enum.filter(&present_value?/1)
  end

  defp storage_behavior_refs(facts, :durable) do
    facts
    |> Enum.filter(&durable_profile_fact?/1)
    |> Enum.map(&fetch(&1, :storage_behavior_ref))
    |> Enum.filter(&present_value?/1)
  end

  defp storage_behavior_changed?(memory_refs, durable_refs) do
    Enum.any?(memory_refs, fn memory_ref ->
      Enum.any?(durable_refs, &(&1 != memory_ref))
    end)
  end

  defp memory_tier_fact?(fact) when is_map(fact),
    do: fetch(fact, :selected_tier) == :memory_ephemeral

  defp memory_tier_fact?(_fact), do: false

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
