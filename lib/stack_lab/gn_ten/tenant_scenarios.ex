defmodule StackLab.GnTen.TenantScenarios do
  @moduledoc """
  Provider-free tenant isolation scenarios for the gn-ten proof matrix.

  These scenarios are pure local fixtures. They prove the shape of tenant
  scoping and lease matching without claiming database row-level security,
  production isolation, or audit-grade evidence.
  """

  @schema_version "gn_ten_tenant_isolation_v1"
  @scenario_ids ~w(tenant_isolation_read tenant_isolation_write tenant_lease_handling)

  @spec report() :: map()
  def report do
    tenant_a = "tenant-a"
    tenant_b = "tenant-b"

    %{
      schema_version: @schema_version,
      profile: "assembled_offline",
      provider_free?: true,
      proof_posture: proof_posture(),
      scenarios: [
        read_scenario(tenant_a, tenant_b),
        write_scenario(tenant_a, tenant_b),
        lease_scenario(tenant_a, tenant_b)
      ]
    }
  end

  @spec validate_report(map()) :: :ok | {:error, [map()]}
  def validate_report(report) when is_map(report) do
    failures =
      []
      |> require_equal("tenant_bad_schema", report[:schema_version], @schema_version)
      |> require_equal("tenant_bad_profile", report[:profile], "assembled_offline")
      |> require_equal("tenant_not_provider_free", report[:provider_free?], true)
      |> validate_posture(report[:proof_posture])
      |> validate_scenarios(report[:scenarios])

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_report(_report), do: {:error, [%{code: "tenant_invalid_report"}]}

  defp read_scenario(tenant_a, tenant_b) do
    records = [
      %{id: "doc-a", tenant_id: tenant_a, value: "a-owned"},
      %{id: "doc-b", tenant_id: tenant_b, value: "b-owned"}
    ]

    visible = tenant_read(records, tenant_a)
    cross_tenant_result = tenant_fetch(records, tenant_a, "doc-b")

    %{
      id: "tenant_isolation_read",
      owner_repo: "stack_lab",
      tenant_id: tenant_a,
      outcome: "passed",
      evidence: %{
        visible_ids: Enum.map(visible, & &1.id),
        cross_tenant_read: cross_tenant_result
      },
      does_not_prove: common_non_claims()
    }
  end

  defp write_scenario(tenant_a, tenant_b) do
    record = %{id: "doc-b", tenant_id: tenant_b, value: "b-owned"}
    denied = tenant_write(record, tenant_a, %{value: "takeover"})
    allowed = tenant_write(%{record | tenant_id: tenant_a}, tenant_a, %{value: "a-owned-next"})

    %{
      id: "tenant_isolation_write",
      owner_repo: "stack_lab",
      tenant_id: tenant_a,
      outcome: "passed",
      evidence: %{
        cross_tenant_write: denied,
        same_tenant_write: allowed
      },
      does_not_prove: common_non_claims()
    }
  end

  defp lease_scenario(tenant_a, tenant_b) do
    lease = %{lease_id: "lease-a", tenant_id: tenant_a, credential_ref_id: "cred-a"}

    %{
      id: "tenant_lease_handling",
      owner_repo: "stack_lab",
      tenant_id: tenant_a,
      outcome: "passed",
      evidence: %{
        same_tenant_use: use_lease(lease, tenant_a),
        cross_tenant_use: use_lease(lease, tenant_b)
      },
      does_not_prove: common_non_claims()
    }
  end

  defp tenant_read(records, tenant_id) do
    Enum.filter(records, &(&1.tenant_id == tenant_id))
  end

  defp tenant_fetch(records, tenant_id, id) do
    case Enum.find(records, &(&1.id == id and &1.tenant_id == tenant_id)) do
      nil -> "denied"
      _record -> "allowed"
    end
  end

  defp tenant_write(%{tenant_id: tenant_id} = record, tenant_id, attrs) do
    {:ok, Map.merge(record, attrs)}
  end

  defp tenant_write(_record, _tenant_id, _attrs), do: {:error, :tenant_mismatch}

  defp use_lease(%{tenant_id: tenant_id}, tenant_id), do: "allowed"
  defp use_lease(_lease, _tenant_id), do: "denied"

  defp proof_posture do
    %{
      authoritative_audit?: false,
      production_deployment_proven?: false,
      row_level_security_proven?: false,
      safe_action: "use_as_provider_free_tenant_fixture"
    }
  end

  defp common_non_claims do
    [
      "production row-level security",
      "audit-grade tenant isolation",
      "live provider credential handling"
    ]
  end

  defp validate_posture(failures, %{} = posture) do
    if posture.authoritative_audit? == false and
         posture.production_deployment_proven? == false and
         posture.row_level_security_proven? == false do
      failures
    else
      [failure("tenant_bad_posture", posture: posture) | failures]
    end
  end

  defp validate_posture(failures, posture),
    do: [failure("tenant_bad_posture", posture: posture) | failures]

  defp validate_scenarios(failures, scenarios) when is_list(scenarios) do
    present = scenarios |> Enum.map(& &1[:id]) |> Enum.sort()

    failures
    |> require_equal("tenant_missing_scenarios", present, Enum.sort(@scenario_ids))
    |> validate_scenario_outcomes(scenarios)
  end

  defp validate_scenarios(failures, _scenarios) do
    [failure("tenant_missing_scenarios", scenarios: @scenario_ids) | failures]
  end

  defp validate_scenario_outcomes(failures, scenarios) do
    Enum.reduce(scenarios, failures, fn scenario, acc ->
      if scenario[:outcome] == "passed" and scenario_passed?(scenario) do
        acc
      else
        [failure("tenant_scenario_failed", scenario: scenario[:id]) | acc]
      end
    end)
  end

  defp scenario_passed?(%{id: "tenant_isolation_read", evidence: evidence}) do
    evidence.visible_ids == ["doc-a"] and evidence.cross_tenant_read == "denied"
  end

  defp scenario_passed?(%{id: "tenant_isolation_write", evidence: evidence}) do
    match?({:error, :tenant_mismatch}, evidence.cross_tenant_write) and
      match?({:ok, %{tenant_id: "tenant-a"}}, evidence.same_tenant_write)
  end

  defp scenario_passed?(%{id: "tenant_lease_handling", evidence: evidence}) do
    evidence.same_tenant_use == "allowed" and evidence.cross_tenant_use == "denied"
  end

  defp scenario_passed?(_scenario), do: false

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected),
    do: [failure(code, expected: expected, actual: actual) | failures]

  defp failure(code, attrs), do: Map.new([{:code, code} | attrs])
end
