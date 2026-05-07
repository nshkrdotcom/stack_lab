defmodule StackLab.PersistenceMatrixScannerTest do
  use ExUnit.Case, async: true

  alias GroundPlane.PersistencePolicy.Redaction
  alias StackLab.PersistenceMatrixScanner

  test "passes complete memory and durable persistence facts" do
    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "examples/persistence_mode_roundtrip",
               persistence_facts: [memory_fact(), durable_fact()]
             })

    assert receipt.status == :pass
    assert receipt.findings == []
    assert "PERSIST-001" in receipt.fixture_refs
    assert "PERSIST-015" in receipt.fixture_refs
    assert "PERSIST-016" in receipt.fixture_refs
    assert "PERSIST-020" in receipt.fixture_refs
  end

  test "requires a mickey mouse memory-default fact" do
    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "examples/persistence_mode_roundtrip",
               persistence_facts: [durable_fact()]
             })

    assert has_finding?(receipt, :memory_default, :missing_mickey_mouse_fact)
  end

  test "rejects default durable substrate requirements" do
    fact =
      memory_fact()
      |> Map.put(:postgres_required_by_default?, true)
      |> Map.put(:temporal_required_by_default?, true)
      |> Map.put(:optional_external_required_by_default?, true)

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "examples/persistence_mode_roundtrip",
               persistence_facts: [fact, durable_fact()]
             })

    assert has_finding?(receipt, :no_default_postgres, :postgres_required_by_default)
    assert has_finding?(receipt, :temporal_disabled_by_default, :temporal_required_by_default)

    assert has_finding?(
             receipt,
             :optional_external_substrate_disabled_by_default,
             :optional_external_required_by_default
           )
  end

  test "requires durable opt-in tags for durable tiers" do
    fact =
      durable_fact()
      |> Map.put(:durable_opt_in?, false)
      |> Map.delete(:durable_tag)

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "examples/persistence_mode_roundtrip",
               persistence_facts: [memory_fact(), fact]
             })

    assert has_finding?(receipt, :durable_opt_in_tag, :durable_opt_in_missing)
    assert has_finding?(receipt, :durable_opt_in_tag, :durable_tag_missing)
  end

  test "rejects raw debug capture fields" do
    forbidden_key = hd(Redaction.forbidden_keys())

    fact =
      memory_fact()
      |> Map.put(:debug_events, [Map.put(%{safe_ref: "trace://safe"}, forbidden_key, "raw")])

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "examples/persistence_mode_roundtrip",
               persistence_facts: [fact, durable_fact()]
             })

    assert has_finding?(receipt, :debug_redaction, {:forbidden_raw_field, forbidden_key})
  end

  test "requires knob docs, product no-bypass, and gn-ten receipt fields" do
    fact =
      memory_fact()
      |> Map.put(:knob_docs, [])
      |> Map.put(:product_direct_lower_store_imports, ["Mezzanine.Repo"])
      |> put_in([:gn_ten_receipt, :proof_command], nil)

    assert {:ok, receipt} =
             PersistenceMatrixScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "examples/persistence_mode_roundtrip",
               persistence_facts: [fact, durable_fact()]
             })

    assert has_finding?(receipt, :knob_docs, :missing_knob_docs)
    assert has_finding?(receipt, :product_no_bypass, :direct_lower_store_import)
    assert has_finding?(receipt, :gn_ten_proof_command_field, :missing_gn_ten_field)
  end

  defp has_finding?(receipt, rule, reason) do
    Enum.any?(receipt.findings, fn finding ->
      finding.rule == rule and finding.reason == reason
    end)
  end

  defp memory_fact do
    %{
      profile_id: :mickey_mouse,
      selected_tier: :memory_ephemeral,
      store_set_id: :mickey_mouse_memory,
      capture_level: :off,
      proof_command: "mix test",
      memory_default?: true,
      postgres_required_by_default?: false,
      temporal_required_by_default?: false,
      optional_external_required_by_default?: false,
      debug_capture_redacted?: true,
      durable_opt_in?: false,
      durable_tag: nil,
      knob_docs: [knob_doc()],
      product_direct_lower_store_imports: [],
      debug_events: [%{safe_ref: "trace://memory/default", hash_ref: "hash://memory/default"}],
      gn_ten_receipt: gn_ten_receipt(:mickey_mouse, :memory_ephemeral, :mickey_mouse_memory, :off)
    }
  end

  defp durable_fact do
    %{
      profile_id: :integration_postgres,
      selected_tier: :postgres_shared,
      store_set_id: :integration_postgres,
      capture_level: :refs_only,
      proof_command: "mix test",
      memory_default?: false,
      postgres_required_by_default?: false,
      temporal_required_by_default?: false,
      optional_external_required_by_default?: false,
      debug_capture_redacted?: true,
      durable_opt_in?: true,
      durable_tag: "persistence-durable-opt-in",
      knob_docs: [knob_doc()],
      product_direct_lower_store_imports: [],
      debug_events: [%{safe_ref: "trace://postgres/opt-in", hash_ref: "hash://postgres/opt-in"}],
      gn_ten_receipt:
        gn_ten_receipt(:integration_postgres, :postgres_shared, :integration_postgres, :refs_only)
    }
  end

  defp knob_doc do
    %{
      name: "persistence_profile",
      type: "atom",
      default: ":mickey_mouse",
      validation: "built-in profile",
      examples: [":mickey_mouse", ":integration_postgres"],
      test_refs: ["support/persistence_matrix_scanner"]
    }
  end

  defp gn_ten_receipt(profile, tier, store_set, capture_level) do
    %{
      selected_persistence_profile: profile,
      selected_tier: tier,
      store_set_id: store_set,
      capture_level: capture_level,
      proof_command: "mix test"
    }
  end
end
