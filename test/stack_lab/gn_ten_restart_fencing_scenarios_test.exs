defmodule StackLab.GnTen.RestartFencingScenariosTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.RestartFencingScenarios

  test "provider-free restart and fencing scenarios validate" do
    report = RestartFencingScenarios.report()

    assert :ok = RestartFencingScenarios.validate_report(report)
    assert report.schema_version == "gn_ten_restart_fencing_v1"
    assert report.profile == "assembled_offline"
    assert report[:provider_free?] == true

    assert Enum.map(report.scenarios, & &1.id) == [
             "active_delayed_retry_duplicate_dispatch",
             "stale_installation_revision",
             "revoked_lease_restart_fence"
           ]
  end

  test "validator rejects unsafe restart posture claims" do
    report =
      RestartFencingScenarios.report()
      |> put_in([:proof_posture, :production_deployment_proven?], true)

    assert {:error, failures} = RestartFencingScenarios.validate_report(report)
    assert Enum.any?(failures, &(&1.code == "restart_bad_posture"))
  end
end
