defmodule StackLab.GnTen.ConnectorCompanionRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.ConnectorCompanionRoundtrip

  test "assembled companion connector roundtrip validates all Phase E fixtures" do
    report = ConnectorCompanionRoundtrip.report()

    assert :ok = ConnectorCompanionRoundtrip.validate_report(report)
    assert report.schema_version == "phase_e_connector_companion_roundtrip_v1"
    assert report.profile == "assembled_offline"
    assert report[:provider_free?] == true
    assert report.repos_checked == ["jido_integration", "app_kit", "stack_lab"]
    assert report.explicit_app_config.auto_discovery? == false
    assert report.admission_record.admission_status == "admitted"
    assert report.app_kit_projection.contract_name == "AppKit.ConnectorAdmissionProjection.v1"

    assert Enum.map(report.fixtures, & &1.id) == [
             "CONN-001",
             "CONN-002",
             "CONN-003",
             "CONN-004",
             "CONN-005",
             "CONN-006",
             "CONN-007",
             "CONN-008"
           ]
  end

  test "validator rejects package auto discovery claims" do
    report =
      ConnectorCompanionRoundtrip.report()
      |> put_in([:explicit_app_config, :auto_discovery?], true)

    assert {:error, failures} = ConnectorCompanionRoundtrip.validate_report(report)
    assert Enum.any?(failures, &(&1.code == "companion_auto_discovery_enabled"))
  end

  test "validator rejects public credential-shaped keys" do
    report =
      ConnectorCompanionRoundtrip.report()
      |> put_in([:app_kit_projection, :provider_account_id], "provider-account:tenant-alpha")

    assert {:error, failures} = ConnectorCompanionRoundtrip.validate_report(report)
    assert Enum.any?(failures, &(&1.code == "companion_public_artifact_leak"))
  end
end
