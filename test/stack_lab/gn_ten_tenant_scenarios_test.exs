defmodule StackLab.GnTen.TenantScenariosTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.TenantScenarios

  test "provider-free tenant scenarios validate" do
    report = TenantScenarios.report()

    assert :ok = TenantScenarios.validate_report(report)
    assert report.schema_version == "gn_ten_tenant_isolation_v1"
    assert report.profile == "assembled_offline"
    assert report[:provider_free?] == true

    assert Enum.map(report.scenarios, & &1.id) == [
             "tenant_isolation_read",
             "tenant_isolation_write",
             "tenant_lease_handling"
           ]
  end

  test "validator rejects unsafe posture claims" do
    report =
      TenantScenarios.report()
      |> put_in([:proof_posture, :production_deployment_proven?], true)

    assert {:error, failures} = TenantScenarios.validate_report(report)
    assert Enum.any?(failures, &(&1.code == "tenant_bad_posture"))
  end
end
