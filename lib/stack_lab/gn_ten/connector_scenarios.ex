defmodule StackLab.GnTen.ConnectorScenarios do
  @moduledoc """
  Provider-free connector hardening scenarios for the gn-ten proof matrix.

  These scenarios are pure local fixtures. They prove connector-boundary shape
  without calling live providers or storing provider payloads, raw prompts,
  tokens, or secrets in public artifacts.
  """

  @schema_version "gn_ten_connector_hardening_v1"
  @scenario_ids ~w(
    connector_provider_free
    connector_secret_lease
    connector_token_budget
    prompt_injection_defense
  )
  @forbidden_public_keys ~w(
    raw_prompt
    provider_payload
    secret
    api_key
    access_token
    refresh_token
    provider_token
  )

  @spec report() :: map()
  def report do
    %{
      schema_version: @schema_version,
      profile: "assembled_offline",
      provider_free?: true,
      proof_posture: proof_posture(),
      scenarios: [
        provider_free_scenario(),
        secret_lease_scenario(),
        token_budget_scenario(),
        prompt_injection_scenario()
      ]
    }
  end

  @spec validate_report(map()) :: :ok | {:error, [map()]}
  def validate_report(report) when is_map(report) do
    failures =
      []
      |> require_equal("connector_bad_schema", report[:schema_version], @schema_version)
      |> require_equal("connector_bad_profile", report[:profile], "assembled_offline")
      |> require_equal("connector_not_provider_free", report[:provider_free?], true)
      |> validate_posture(report[:proof_posture])
      |> validate_scenarios(report[:scenarios])
      |> validate_public_redaction(report)

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_report(_report), do: {:error, [%{code: "connector_invalid_report"}]}

  defp provider_free_scenario do
    normalized = normalize_fixture_response(%{status: 200, body_ref: "fixture://connector/ok"})

    %{
      id: "connector_provider_free",
      owner_repo: "stack_lab",
      outcome: "passed",
      evidence: %{
        fixture_lane: "provider_free",
        normalized_status: normalized.status,
        public_body_ref: normalized.body_ref
      },
      does_not_prove: common_non_claims()
    }
  end

  defp secret_lease_scenario do
    lease = %{lease_handle: "lease://connector/github/demo", expires_in_seconds: 300}

    %{
      id: "connector_secret_lease",
      owner_repo: "stack_lab",
      outcome: "passed",
      evidence: %{
        public_seam_keys: Map.keys(lease),
        raw_secret_available?: false,
        lease_expiring?: lease.expires_in_seconds <= 300
      },
      does_not_prove: common_non_claims()
    }
  end

  defp token_budget_scenario do
    result = enforce_budget(%{max_tokens: 128, requested_tokens: 256})

    %{
      id: "connector_token_budget",
      owner_repo: "stack_lab",
      outcome: "passed",
      evidence: %{
        requested_tokens: 256,
        max_tokens: 128,
        result: result
      },
      does_not_prove: common_non_claims()
    }
  end

  defp prompt_injection_scenario do
    result =
      validate_tool_selection(%{
        untrusted_content_ref: "fixture://connector/injection",
        requested_tool: "connector.git_hub.issue.create",
        attempted_policy_override?: true,
        allowed_tools: ["connector.git_hub.issue.read"]
      })

    %{
      id: "prompt_injection_defense",
      owner_repo: "stack_lab",
      outcome: "passed",
      evidence: %{
        untrusted_content_ref: "fixture://connector/injection",
        selected_action: result,
        policy_changed?: false
      },
      does_not_prove: common_non_claims()
    }
  end

  defp normalize_fixture_response(%{status: status, body_ref: body_ref}) do
    %{status: status, body_ref: body_ref}
  end

  defp enforce_budget(%{requested_tokens: requested, max_tokens: max}) when requested > max do
    "budget_exhausted_fallback"
  end

  defp enforce_budget(_budget), do: "allowed"

  defp validate_tool_selection(%{attempted_policy_override?: true}), do: "rejected"

  defp validate_tool_selection(%{requested_tool: tool, allowed_tools: tools}) do
    if tool in tools, do: "allowed", else: "rejected"
  end

  defp proof_posture do
    %{
      authoritative_audit?: false,
      production_deployment_proven?: false,
      live_provider_proven?: false,
      raw_provider_payload_public?: false,
      safe_action: "use_as_provider_free_connector_fixture"
    }
  end

  defp common_non_claims do
    [
      "live provider behavior",
      "production credential handling",
      "audit-grade connector evidence",
      "provider billing correctness"
    ]
  end

  defp validate_posture(failures, %{} = posture) do
    if posture.authoritative_audit? == false and
         posture.production_deployment_proven? == false and
         posture.live_provider_proven? == false and
         posture.raw_provider_payload_public? == false do
      failures
    else
      [failure("connector_bad_posture", posture: posture) | failures]
    end
  end

  defp validate_posture(failures, posture),
    do: [failure("connector_bad_posture", posture: posture) | failures]

  defp validate_scenarios(failures, scenarios) when is_list(scenarios) do
    present = scenarios |> Enum.map(& &1[:id]) |> Enum.sort()

    failures
    |> require_equal("connector_missing_scenarios", present, Enum.sort(@scenario_ids))
    |> validate_scenario_outcomes(scenarios)
  end

  defp validate_scenarios(failures, _scenarios) do
    [failure("connector_missing_scenarios", scenarios: @scenario_ids) | failures]
  end

  defp validate_scenario_outcomes(failures, scenarios) do
    Enum.reduce(scenarios, failures, fn scenario, acc ->
      if scenario[:outcome] == "passed" and scenario_passed?(scenario) do
        acc
      else
        [failure("connector_scenario_failed", scenario: scenario[:id]) | acc]
      end
    end)
  end

  defp scenario_passed?(%{id: "connector_provider_free", evidence: evidence}) do
    evidence.fixture_lane == "provider_free" and evidence.normalized_status == 200
  end

  defp scenario_passed?(%{id: "connector_secret_lease", evidence: evidence}) do
    Enum.sort(evidence.public_seam_keys) == [:expires_in_seconds, :lease_handle] and
      evidence.raw_secret_available? == false and evidence.lease_expiring? == true
  end

  defp scenario_passed?(%{id: "connector_token_budget", evidence: evidence}) do
    evidence.requested_tokens > evidence.max_tokens and
      evidence.result == "budget_exhausted_fallback"
  end

  defp scenario_passed?(%{id: "prompt_injection_defense", evidence: evidence}) do
    evidence.selected_action == "rejected" and evidence.policy_changed? == false
  end

  defp scenario_passed?(_scenario), do: false

  defp validate_public_redaction(failures, term) do
    term
    |> collect_forbidden_paths([])
    |> case do
      [] -> failures
      paths -> [failure("connector_public_artifact_leak", paths: paths) | failures]
    end
  end

  defp collect_forbidden_paths(%{} = map, path) do
    Enum.flat_map(map, fn {key, value} ->
      key_string = key |> to_string() |> String.trim_leading(":")
      next_path = [key_string | path]

      if key_string in @forbidden_public_keys do
        [Enum.reverse(next_path)]
      else
        collect_forbidden_paths(value, next_path)
      end
    end)
  end

  defp collect_forbidden_paths(list, path) when is_list(list) do
    Enum.flat_map(list, &collect_forbidden_paths(&1, path))
  end

  defp collect_forbidden_paths(_term, _path), do: []

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected),
    do: [failure(code, expected: expected, actual: actual) | failures]

  defp failure(code, attrs), do: Map.new([{:code, code} | attrs])
end
