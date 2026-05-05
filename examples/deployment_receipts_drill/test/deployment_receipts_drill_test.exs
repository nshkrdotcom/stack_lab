defmodule StackLab.Examples.DeploymentReceiptsDrillTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.DeploymentReceiptsDrill
  alias StackLab.GnTenControlPlane
  alias StackLab.SpecCell

  test "scenario records Phase 16 deployment proof cases" do
    scenario = DeploymentReceiptsDrill.scenario()

    assert scenario.name == :deployment_receipts_drill
    assert scenario.owner_phase == "Phase 16"
    assert scenario.acceptance_fixture == "UAA-048"

    assert Enum.sort(Map.keys(scenario.cases)) == [
             :app_kit_readback,
             :auth_authority_startup,
             :connector_binding_migration,
             :credential_lease_migration,
             :durable_restart_rollback,
             :provider_account_migration,
             :redacted_trace_export,
             :revocation_propagation,
             :target_attach_migration
           ]

    assert %{repo: "mezzanine", command: "just dev-up"} in scenario.temporal_substrate_commands

    assert %{repo: "mezzanine", command: "just dev-status"} in scenario.temporal_substrate_commands

    refute Enum.any?(scenario.temporal_substrate_commands, fn command ->
             String.contains?(command.command, "server start-dev")
           end)
  end

  test "receipt manifest covers every deployment proof section" do
    manifest = DeploymentReceiptsDrill.receipt_manifest()

    assert map_size(manifest.component_versions) >= 8
    assert Enum.count(manifest.migrations) == 4
    assert Enum.count(manifest.config_schema) == 5
    assert Enum.count(manifest.secret_contract) == 4
    assert Enum.count(manifest.scanner_results) >= 6
    assert Enum.count(manifest.smoke_commands) >= 3
    assert Enum.count(manifest.rollback_plan) >= 6
    assert Enum.count(manifest.proof_refs) >= 4
    assert Enum.count(manifest.drills) == 9
    assert Enum.count(manifest.durable_micro_state) == 2

    assert Enum.all?(manifest.drills, &(&1.state == :passed))
    assert manifest.raw_material_present? == false
  end

  test "receipt validation rejects missing sections and unredacted fields" do
    assert :ok =
             DeploymentReceiptsDrill.validate_receipt(DeploymentReceiptsDrill.receipt_manifest())

    receipt_without_rollback =
      DeploymentReceiptsDrill.receipt_manifest()
      |> Map.put(:rollback_plan, [])

    assert {:error, [:rollback_plan]} =
             DeploymentReceiptsDrill.validate_receipt(receipt_without_rollback)

    receipt_with_unredacted_field =
      DeploymentReceiptsDrill.receipt_manifest()
      |> Map.put(:raw_access_material, "not-redacted")

    assert {:error, [:raw_access_material]} =
             DeploymentReceiptsDrill.validate_receipt(receipt_with_unredacted_field)
  end

  test "execute returns green SpecCell and gn-ten receipts" do
    assert {:ok, proof} = DeploymentReceiptsDrill.execute()

    assert proof.acceptance_fixture == "UAA-048"
    assert Enum.all?(proof.spec_cells, &match?(%SpecCell{owner_repo: "stack_lab"}, &1))
    assert Enum.all?(proof.spec_cells, &SpecCell.complete?/1)

    assert Enum.any?(proof.receipts, fn receipt ->
             match?(%GnTenControlPlane{requirement_id: "UAA-048", state: "passed"}, receipt)
           end)

    refute Enum.any?(proof.receipts, &GnTenControlPlane.release_blocking?/1)
  end

  test "redacted projection removes unredacted fields from nested receipts" do
    projected =
      DeploymentReceiptsDrill.redacted_projection(%{
        deployment_ref: "deployment://phase16/stack-lab",
        raw_access_material: "not-redacted",
        nested: [%{authorization_header: "not-redacted", state: :passed}]
      })

    refute Map.has_key?(projected, :raw_access_material)
    assert [%{state: :passed} = nested] = projected.nested
    refute Map.has_key?(nested, :authorization_header)
  end
end
