defmodule StackLab.PersistenceMatrixScannerTest do
  use ExUnit.Case, async: true

  alias GroundPlane.PersistencePolicy.Redaction
  alias StackLab.PersistenceMatrixScanner

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

  test "passes complete profile matrix persistence facts" do
    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(scan_input())

    assert receipt.status == :pass
    assert receipt.findings == []
    assert receipt.fixture_refs == @fixture_refs
    assert Enum.map(receipt.fixture_mappings, & &1.fixture_ref) == @fixture_refs
  end

  test "requires a mickey mouse memory-default fact" do
    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(scan_input(persistence_facts: durable_facts()))

    assert has_finding?(receipt, :memory_default, :missing_mickey_mouse_fact)
  end

  test "requires complete profile coverage" do
    facts = [memory_fact(), memory_debug_fact(), integration_postgres_fact()]

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(scan_input(persistence_facts: facts))

    assert has_finding?(receipt, :profile_coverage, {:missing_profile, :full_debug_tracked})
  end

  test "rejects default durable substrate requirements" do
    fact =
      memory_fact()
      |> Map.put(:provider_dependency_by_default?, true)
      |> Map.put(:postgres_required_by_default?, true)
      |> Map.put(:temporal_required_by_default?, true)
      |> Map.put(:object_store_required_by_default?, true)
      |> Map.put(:network_required_by_default?, true)
      |> Map.put(:debug_sidecar_required_by_default?, true)
      |> Map.put(:optional_external_required_by_default?, true)

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(
               scan_input(persistence_facts: [fact, memory_debug_fact()] ++ durable_facts())
             )

    assert has_finding?(receipt, :no_default_provider, :provider_dependency_by_default)
    assert has_finding?(receipt, :no_default_postgres, :postgres_required_by_default)
    assert has_finding?(receipt, :temporal_disabled_by_default, :temporal_required_by_default)
    assert has_finding?(receipt, :no_default_object_store, :object_store_required_by_default)
    assert has_finding?(receipt, :no_default_network, :network_required_by_default)
    assert has_finding?(receipt, :no_default_debug_sidecar, :debug_sidecar_required_by_default)

    assert has_finding?(
             receipt,
             :optional_external_substrate_disabled_by_default,
             :optional_external_required_by_default
           )
  end

  test "requires durable opt-in tags for durable tiers" do
    fact =
      integration_postgres_fact()
      |> Map.put(:durable_opt_in?, false)
      |> Map.delete(:durable_tag)

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(
               scan_input(
                 persistence_facts: [memory_fact(), memory_debug_fact(), fact, full_debug_fact()]
               )
             )

    assert has_finding?(receipt, :durable_opt_in_tag, :durable_opt_in_missing)
    assert has_finding?(receipt, :durable_opt_in_tag, :durable_tag_missing)
  end

  test "requires storage behavior to change across memory and durable profiles" do
    facts =
      [memory_fact(), memory_debug_fact(), integration_postgres_fact(), full_debug_fact()]
      |> Enum.map(&Map.put(&1, :storage_behavior_ref, "storage-behavior://unchanged"))

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(scan_input(persistence_facts: facts))

    assert has_finding?(receipt, :storage_behavior_switch, :storage_behavior_not_changed)
  end

  test "requires stable authority semantics across profiles" do
    facts =
      [memory_fact(), memory_debug_fact(), integration_postgres_fact(), full_debug_fact()]
      |> List.update_at(3, &Map.put(&1, :authority_semantics_ref, "authority://changed"))

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(scan_input(persistence_facts: facts))

    assert has_finding?(receipt, :authority_semantics_stable, :authority_semantics_changed)
  end

  test "requires restart claims to match memory and durable tiers" do
    memory = Map.put(memory_fact(), :restart_claim, :restart_safe)
    durable = Map.put(integration_postgres_fact(), :restart_claim, :none)

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(
               scan_input(
                 persistence_facts: [memory, memory_debug_fact(), durable, full_debug_fact()]
               )
             )

    assert has_finding?(
             receipt,
             :restart_claim_classification,
             :memory_profile_claimed_restart_safety
           )

    assert has_finding?(
             receipt,
             :restart_claim_classification,
             :durable_profile_missing_restart_claim
           )
  end

  test "rejects raw debug capture fields" do
    forbidden_key = hd(Redaction.forbidden_keys())

    fact =
      memory_fact()
      |> Map.put(:debug_events, [Map.put(%{safe_ref: "trace://safe"}, forbidden_key, "raw")])

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(
               scan_input(persistence_facts: [fact, memory_debug_fact()] ++ durable_facts())
             )

    assert has_finding?(receipt, :debug_redaction, {:forbidden_raw_field, forbidden_key})
  end

  test "requires knob docs product no-bypass and gn-ten receipt fields" do
    fact =
      memory_fact()
      |> Map.put(:knob_docs, [])
      |> Map.put(:product_direct_lower_store_imports, ["Mezzanine.Repo"])
      |> put_in([:gn_ten_receipt, :proof_command], nil)

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(
               scan_input(persistence_facts: [fact, memory_debug_fact()] ++ durable_facts())
             )

    assert has_finding?(receipt, :knob_docs, :missing_knob_docs)
    assert has_finding?(receipt, :product_no_bypass, :direct_lower_store_import)
    assert has_finding?(receipt, :gn_ten_proof_command_field, :missing_gn_ten_field)
  end

  test "requires complete PERSIST fixture mappings" do
    mappings =
      fixture_mappings()
      |> Enum.reject(&(&1.fixture_ref == "PERSIST-020"))
      |> List.update_at(0, &Map.put(&1, :docs_paths, []))

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(scan_input(fixture_mappings: mappings))

    assert has_finding?(
             receipt,
             :complete_fixture_mapping,
             {:missing_fixture_mapping, "PERSIST-020"}
           )

    assert has_finding?(
             receipt,
             :complete_fixture_mapping,
             {:incomplete_fixture_mapping, :docs_paths}
           )
  end

  defp has_finding?(receipt, rule, reason) do
    Enum.any?(receipt.findings, fn finding ->
      finding.rule == rule and finding.reason == reason
    end)
  end

  defp scan_input(overrides \\ []) do
    %{
      owner_repo: "stack_lab",
      package_path: "examples/persistence_mode_roundtrip",
      persistence_facts: Keyword.get(overrides, :persistence_facts, complete_facts()),
      fixture_mappings: Keyword.get(overrides, :fixture_mappings, fixture_mappings())
    }
  end

  defp complete_facts do
    [memory_fact(), memory_debug_fact(), integration_postgres_fact(), full_debug_fact()]
  end

  defp durable_facts do
    [integration_postgres_fact(), full_debug_fact()]
  end

  defp memory_fact do
    fact(
      :mickey_mouse,
      :memory_ephemeral,
      :mickey_mouse_memory,
      :off,
      false,
      nil,
      "storage-behavior://memory_ephemeral/mickey_mouse_memory",
      :none
    )
    |> Map.put(:memory_default?, true)
  end

  defp memory_debug_fact do
    fact(
      :memory_debug,
      :memory_ephemeral,
      :mickey_mouse_memory,
      :redacted_debug,
      false,
      nil,
      "storage-behavior://memory_ephemeral/mickey_mouse_memory",
      :none
    )
  end

  defp integration_postgres_fact do
    fact(
      :integration_postgres,
      :postgres_shared,
      :integration_postgres,
      :refs_only,
      true,
      "persistence-durable-opt-in",
      "storage-behavior://postgres_shared/integration_postgres",
      :durable
    )
  end

  defp full_debug_fact do
    fact(
      :full_debug_tracked,
      :postgres_shared,
      :full_debug_tracked,
      :full_debug,
      true,
      "persistence-durable-opt-in",
      "storage-behavior://postgres_shared/full_debug_tracked",
      :durable
    )
  end

  defp fact(
         profile,
         tier,
         store_set,
         capture_level,
         durable?,
         durable_tag,
         storage_ref,
         restart_claim
       ) do
    %{
      profile_id: profile,
      selected_tier: tier,
      store_set_id: store_set,
      capture_level: capture_level,
      proof_command: "mix test --color",
      memory_default?: false,
      provider_dependency_by_default?: false,
      postgres_required_by_default?: false,
      temporal_required_by_default?: false,
      object_store_required_by_default?: false,
      network_required_by_default?: false,
      optional_external_required_by_default?: false,
      debug_sidecar_required_by_default?: false,
      debug_capture_redacted?: true,
      durable_opt_in?: durable?,
      durable_tag: durable_tag,
      storage_behavior_ref: storage_ref,
      authority_semantics_ref: "authority-semantics://phase-10/governed-provider/decision-v1",
      restart_claim: restart_claim,
      knob_docs: [knob_doc()],
      product_direct_lower_store_imports: [],
      debug_events: [%{safe_ref: "trace://profile", hash_ref: "hash://profile"}],
      gn_ten_receipt: gn_ten_receipt(profile, tier, store_set, capture_level)
    }
  end

  defp knob_doc do
    %{
      name: "persistence_profile",
      type: "atom",
      default: ":mickey_mouse",
      validation: "built-in profile",
      examples: [":mickey_mouse", ":memory_debug", ":integration_postgres", ":full_debug_tracked"],
      test_refs: ["support/persistence_matrix_scanner"]
    }
  end

  defp gn_ten_receipt(profile, tier, store_set, capture_level) do
    %{
      selected_persistence_profile: profile,
      selected_tier: tier,
      store_set_id: store_set,
      capture_level: capture_level,
      proof_command: "mix test --color"
    }
  end

  defp fixture_mappings do
    Enum.map(@fixture_refs, fn fixture_ref ->
      %{
        fixture_ref: fixture_ref,
        source_paths: ["examples/persistence_mode_roundtrip/lib/roundtrip.ex"],
        test_paths: ["examples/persistence_mode_roundtrip/test/roundtrip_test.exs"],
        scanner_rules: [:complete_fixture_mapping],
        docs_paths: ["examples/persistence_mode_roundtrip/README.md"],
        receipt_paths: ["receipt.fixture_mappings"]
      }
    end)
  end
end
