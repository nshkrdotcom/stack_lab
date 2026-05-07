defmodule StackLab.Examples.PersistenceModeRoundtripTest do
  use ExUnit.Case, async: true

  alias GroundPlane.PersistencePolicy.Redaction
  alias StackLab.Examples.PersistenceModeRoundtrip

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

  test "proves all required profiles without default live dependencies" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    assert receipt.status == :pass
    assert receipt.matrix_scan.status == :pass

    assert Enum.map(receipt.profile_receipts, & &1.profile_id) == [
             :mickey_mouse,
             :memory_debug,
             :integration_postgres,
             :full_debug_tracked
           ]

    assert receipt.provider_dependency? == false
    assert receipt.postgres_dependency? == false
    assert receipt.temporal_dependency? == false
    assert receipt.object_store_dependency? == false
    assert receipt.network_dependency? == false
    assert receipt.external_substrate_dependency? == false
    assert receipt.debug_sidecar_dependency? == false
  end

  test "proves memory default without live durable dependencies" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    memory = profile_receipt(receipt, :mickey_mouse)

    assert memory.selected_tier == :memory_ephemeral
    assert memory.capture_level == :off
    assert memory.durable_opt_in? == false
    assert memory.preflight == :ok
    assert memory.restart_claim == :none
  end

  test "proves memory debug remains memory storage with redacted bounded capture" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    memory_debug = profile_receipt(receipt, :memory_debug)

    assert memory_debug.selected_tier == :memory_ephemeral
    assert memory_debug.capture_level == :redacted_debug
    assert memory_debug.durable_opt_in? == false
    assert memory_debug.preflight == :ok
    assert memory_debug.debug_result.mutated? == true
    assert memory_debug.restart_claim == :none
  end

  test "proves durable profiles require explicit capability and tag" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    for profile_id <- [:integration_postgres, :full_debug_tracked] do
      durable = profile_receipt(receipt, profile_id)

      assert durable.selected_tier == :postgres_shared
      assert durable.durable_opt_in?
      assert durable.durable_tag == "persistence-durable-opt-in"
      assert durable.preflight == :ok
      assert durable.restart_claim == :durable
    end
  end

  test "profile switch changes storage behavior without changing authority semantics" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    authority_refs =
      receipt.profile_receipts
      |> Enum.map(& &1.authority_semantics_ref)
      |> MapSet.new()

    memory_refs =
      receipt.profile_receipts
      |> Enum.filter(&(&1.selected_tier == :memory_ephemeral))
      |> Enum.map(& &1.storage_behavior_ref)
      |> MapSet.new()

    durable_refs =
      receipt.profile_receipts
      |> Enum.reject(&(&1.selected_tier == :memory_ephemeral))
      |> Enum.map(& &1.storage_behavior_ref)
      |> MapSet.new()

    assert receipt.storage_behavior_switch?
    assert receipt.authority_semantics_stable?
    assert MapSet.size(authority_refs) == 1
    assert MapSet.disjoint?(memory_refs, durable_refs)
  end

  test "maps every PERSIST fixture to source test scanner docs and receipts" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    assert receipt.fixture_refs == @fixture_refs
    assert receipt.matrix_scan.fixture_refs == @fixture_refs

    mapped_refs = Enum.map(receipt.fixture_mappings, & &1.fixture_ref)
    assert mapped_refs == @fixture_refs

    for mapping <- receipt.fixture_mappings do
      assert mapping.source_paths != []
      assert mapping.test_paths != []
      assert mapping.scanner_rules != []
      assert mapping.docs_paths != []
      assert mapping.receipt_paths != []
    end
  end

  test "proves debug capture uses only refs hashes and metadata" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    assert receipt.matrix_scan.status == :pass

    for profile <- receipt.profile_receipts do
      Enum.each(Redaction.forbidden_keys(), fn forbidden_key ->
        refute Map.has_key?(profile.debug_event, forbidden_key)
      end)
    end
  end

  test "records gn-ten persistence receipt fields for every profile" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    for profile <- receipt.profile_receipts do
      assert profile.gn_ten_receipt.selected_persistence_profile == profile.profile_id
      assert profile.gn_ten_receipt.selected_tier == profile.selected_tier
      assert profile.gn_ten_receipt.store_set_id == profile.store_set_id
      assert profile.gn_ten_receipt.capture_level == profile.capture_level
      assert profile.gn_ten_receipt.proof_command == "mix test --color"
      assert profile.gn_ten_receipt.storage_behavior_ref == profile.storage_behavior_ref
      assert profile.gn_ten_receipt.authority_semantics_ref == profile.authority_semantics_ref
      assert profile.gn_ten_receipt.restart_claim == profile.restart_claim
    end
  end

  defp profile_receipt(receipt, profile_id) do
    Enum.find(receipt.profile_receipts, &(&1.profile_id == profile_id))
  end
end
