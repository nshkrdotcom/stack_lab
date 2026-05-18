defmodule StackLab.GnTen.ConnectorScenariosTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.ConnectorScenarios
  alias StackLab.GnTen.GovernedConnectorExport
  alias GroundPlane.Boundary.Codec, as: BoundaryCodec

  test "provider-free connector scenarios validate" do
    report = ConnectorScenarios.report()

    assert :ok = ConnectorScenarios.validate_report(report)
    assert report.schema_version == "gn_ten_connector_hardening_v1"
    assert report.profile == "assembled_offline"
    assert report[:provider_free?] == true

    assert Enum.map(report.scenarios, & &1.id) == [
             "connector_provider_free",
             "connector_secret_lease",
             "connector_token_budget",
             "prompt_injection_defense",
             "governed_connector_export_fixture"
           ]
  end

  test "validator rejects unsafe live-provider claims" do
    report =
      ConnectorScenarios.report()
      |> put_in([:proof_posture, :live_provider_proven?], true)

    assert {:error, failures} = ConnectorScenarios.validate_report(report)
    assert Enum.any?(failures, &(&1.code == "connector_bad_posture"))
  end

  test "validator rejects public secret-shaped keys" do
    report =
      ConnectorScenarios.report()
      |> put_in([:scenarios, Access.at(0), :evidence, :api_key], "sk_live_real_value")

    assert {:error, failures} = ConnectorScenarios.validate_report(report)
    assert Enum.any?(failures, &(&1.code == "connector_public_artifact_leak"))
  end

  test "governed connector export bundle is deterministic and codec-backed" do
    bundle = GovernedConnectorExport.bundle()

    assert bundle == GovernedConnectorExport.bundle()
    assert :ok = GovernedConnectorExport.validate_bundle(bundle)
    assert {:ok, encoded} = BoundaryCodec.encode(Map.drop(bundle, ["bundle_hash", "spill_hash"]))
    assert is_binary(encoded)

    assert bundle["bundle_hash"] ==
             BoundaryCodec.digest(Map.drop(bundle, ["bundle_hash", "spill_hash"]))

    assert bundle["canonical_boundary_codec_ref"] == "ground-plane.boundary.codec.v1"
    assert get_in(bundle, ["export_context", "kind"]) == "governed_aitrace_export_context"
    assert get_in(bundle, ["export_context", "ambient_exporters_allowed"]) == false
    assert is_binary(get_in(bundle, ["audit_refs", "credential_lease_ref"]))
    assert [_ | _] = get_in(bundle, ["audit_refs", "lower_receipt_refs"])
    assert GovernedConnectorExport.forbidden_public_key_paths(bundle) == []
  end

  test "checked-in governed connector export receipt matches generated fixture" do
    fixture =
      "../../docs/receipts/gn_ten_connector/governed_compliance_export.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Jason.decode!()

    assert fixture == GovernedConnectorExport.bundle()
    assert :ok = GovernedConnectorExport.validate_bundle(fixture)
  end

  test "governed connector export rejects ambient or missing export context" do
    ambient_bundle =
      GovernedConnectorExport.bundle()
      |> put_in(["export_context", "ambient_exporters_allowed"], true)

    assert {:error, ambient_failures} = GovernedConnectorExport.validate_bundle(ambient_bundle)
    assert failure_code?(ambient_failures, "export_ambient_exporters_allowed")

    missing_context_bundle = Map.delete(GovernedConnectorExport.bundle(), "export_context")

    assert {:error, missing_failures} =
             GovernedConnectorExport.validate_bundle(missing_context_bundle)

    assert failure_code?(missing_failures, "export_missing_governed_context")
  end

  test "governed connector export requires tenant-bound source and replay traces" do
    missing_source_tenant =
      GovernedConnectorExport.bundle()
      |> update_in(["source_trace"], &Map.delete(&1, "tenant_ref"))

    assert {:error, source_failures} =
             GovernedConnectorExport.validate_bundle(missing_source_tenant)

    assert failure_code?(source_failures, "export_missing_source_trace_tenant_ref")

    cross_tenant_replay =
      GovernedConnectorExport.bundle()
      |> put_in(["replay_export", "source_tenant_ref"], "tenant://other")

    assert {:error, replay_failures} =
             GovernedConnectorExport.validate_bundle(cross_tenant_replay)

    assert failure_code?(replay_failures, "export_replay_cross_tenant")
  end

  test "governed connector export deep-scans nested public payload leaks" do
    leaked_bundle =
      GovernedConnectorExport.bundle()
      |> update_in(["replay_export"], fn replay_export ->
        Map.put(replay_export, "debug_projection", %{
          "provider_payload" => %{"body_ref" => "fixture://raw"}
        })
      end)

    assert {:error, failures} = GovernedConnectorExport.validate_bundle(leaked_bundle)
    assert failure_code?(failures, "export_public_artifact_leak")
    assert ["replay_export", "debug_projection", "provider_payload"] in failure_paths(failures)
  end

  test "governed connector export denies every declared public payload key" do
    denied_keys =
      get_in(GovernedConnectorExport.bundle(), ["redaction_summary", "denied_public_payload_keys"])

    assert Enum.all?(denied_keys, fn key ->
             leaked_bundle =
               GovernedConnectorExport.bundle()
               |> update_in(["public_payload"], &Map.put(&1, key, "fixture://forbidden"))

             {:error, failures} = GovernedConnectorExport.validate_bundle(leaked_bundle)
             key in Enum.map(failure_paths(failures), &List.last/1)
           end)
  end

  defp failure_code?(failures, code) do
    Enum.any?(failures, &(&1.code == code))
  end

  defp failure_paths(failures) do
    failures
    |> Enum.filter(&(&1.code == "export_public_artifact_leak"))
    |> Enum.flat_map(& &1.paths)
  end
end
