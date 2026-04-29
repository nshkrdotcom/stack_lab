defmodule StackLab.GnTen.ConnectorScenariosTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.ConnectorScenarios

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
             "prompt_injection_defense"
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
end
