defmodule StackLab.Examples.PersistenceModeRoundtripTest do
  use ExUnit.Case, async: true

  alias GroundPlane.PersistencePolicy.Redaction
  alias StackLab.Examples.PersistenceModeRoundtrip

  test "proves memory default without live durable dependencies" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    memory = profile_receipt(receipt, :mickey_mouse)

    assert receipt.status == :pass
    assert receipt.provider_dependency? == false
    assert receipt.postgres_dependency? == false
    assert receipt.temporal_dependency? == false
    assert receipt.external_substrate_dependency? == false
    assert memory.selected_tier == :memory_ephemeral
    assert memory.durable_opt_in? == false
    assert memory.preflight == :ok
  end

  test "proves durable opt-in with explicit capability and tag" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    durable = profile_receipt(receipt, :integration_postgres)

    assert durable.selected_tier == :postgres_shared
    assert durable.durable_opt_in?
    assert durable.durable_tag == "persistence-durable-opt-in"
    assert durable.preflight == :ok
  end

  test "proves debug capture uses only refs, hashes, and metadata" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    assert receipt.matrix_scan.status == :pass

    for profile <- receipt.profile_receipts do
      Enum.each(Redaction.forbidden_keys(), fn forbidden_key ->
        refute Map.has_key?(profile.debug_event, forbidden_key)
      end)
    end
  end

  test "records gn-ten persistence receipt fields" do
    assert {:ok, receipt} = PersistenceModeRoundtrip.run()

    memory = profile_receipt(receipt, :mickey_mouse)

    assert memory.gn_ten_receipt.selected_persistence_profile == :mickey_mouse
    assert memory.gn_ten_receipt.selected_tier == :memory_ephemeral
    assert memory.gn_ten_receipt.store_set_id == :mickey_mouse_memory
    assert memory.gn_ten_receipt.capture_level == :off
    assert memory.gn_ten_receipt.proof_command == "mix test"
  end

  defp profile_receipt(receipt, profile_id) do
    Enum.find(receipt.profile_receipts, &(&1.profile_id == profile_id))
  end
end
