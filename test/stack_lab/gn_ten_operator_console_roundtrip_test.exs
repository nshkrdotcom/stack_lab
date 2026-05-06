defmodule StackLab.GnTen.OperatorConsoleRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.OperatorConsoleRoundtrip

  test "assembled operator console roundtrip validates all Phase F fixtures" do
    report = OperatorConsoleRoundtrip.report()

    assert :ok = OperatorConsoleRoundtrip.validate_report(report)
    assert report.schema_version == "phase_f_operator_console_roundtrip_v1"
    assert report.profile == "assembled_offline"
    assert report.console_mount.product_local? == true
    assert report.console_mount.imports_lower_runtime? == false
    assert report.render_posture.tenant_mismatch_fails_closed? == true

    assert Enum.map(report.fixtures, & &1.id) == [
             "OPCON-001",
             "OPCON-002",
             "OPCON-003",
             "OPCON-004",
             "OPCON-005",
             "OPCON-006",
             "OPCON-007",
             "OPCON-008"
           ]
  end

  test "validator rejects product bypass and tenant mismatch gaps" do
    mount_gap =
      OperatorConsoleRoundtrip.report()
      |> put_in([:console_mount, :imports_lower_runtime?], true)

    assert {:error, mount_failures} = OperatorConsoleRoundtrip.validate_report(mount_gap)
    assert Enum.any?(mount_failures, &(&1.code == "operator_console_mount_imports_lower"))

    tenant_gap =
      OperatorConsoleRoundtrip.report()
      |> put_in([:render_posture, :tenant_mismatch_fails_closed?], false)

    assert {:error, tenant_failures} = OperatorConsoleRoundtrip.validate_report(tenant_gap)
    assert Enum.any?(tenant_failures, &(&1.code == "operator_console_tenant_mismatch_not_closed"))
  end

  test "validator rejects public raw projection keys" do
    report =
      OperatorConsoleRoundtrip.report()
      |> put_in([:render_posture, :provider_account_id], "provider-account:private")

    assert {:error, failures} = OperatorConsoleRoundtrip.validate_report(report)
    assert Enum.any?(failures, &(&1.code == "operator_console_public_artifact_leak"))
  end
end
