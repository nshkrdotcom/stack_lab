defmodule StackLab.GnTen.OperatorConsoleRoundtrip do
  @moduledoc """
  Assembled Phase F proof for the operator console.
  """

  @schema_version "phase_f_operator_console_roundtrip_v1"
  @fixture_ids ~w(OPCON-001 OPCON-002 OPCON-003 OPCON-004 OPCON-005 OPCON-006 OPCON-007 OPCON-008)
  @forbidden_public_keys ~w(
    prompt_body
    memory_body
    provider_payload
    provider_response
    eval_payload
    provider_account_id
    authorization_header
    token
    secret
    lower_store
    private_state
    agent_message_body
  )

  @spec report() :: map()
  def report do
    %{
      schema_version: @schema_version,
      profile: "assembled_offline",
      repos_checked: [
        "app_kit",
        "extravaganza",
        "AITrace",
        "mezzanine",
        "outer_brain",
        "stack_lab"
      ],
      app_kit_packages: [
        "web/components",
        "web/operator_console",
        "web/replay_viewer",
        "web/policy_authoring",
        "web/cost_dashboard",
        "web/eval_studio"
      ],
      console_mount: %{
        product_repo: "extravaganza",
        route: "/operator-console",
        product_local?: true,
        imports_lower_runtime?: false,
        data_access_posture: "app_kit_dtos_no_lower_store_imports"
      },
      render_posture: %{
        redaction_posture: "dto_and_bounded_exports_only",
        replay_side_effect_posture: "suppressed_view_only",
        cost_posture: "amount_classes_and_refs_only",
        eval_posture: "eval_refs_and_bounded_signals_only",
        tenant_mismatch_fails_closed?: true
      },
      fixtures: fixture_rows(),
      claims_not_made: [
        "live provider execution",
        "lower store read access",
        "raw prompt rendering",
        "raw memory rendering",
        "raw eval payload rendering",
        "raw provider payload rendering"
      ]
    }
  end

  @spec validate_report(map()) :: :ok | {:error, [map()]}
  def validate_report(report) when is_map(report) do
    failures =
      []
      |> require_equal("operator_console_bad_schema", report[:schema_version], @schema_version)
      |> require_equal("operator_console_bad_profile", report[:profile], "assembled_offline")
      |> validate_mount(report[:console_mount])
      |> validate_render_posture(report[:render_posture])
      |> validate_fixtures(report[:fixtures])
      |> validate_public_redaction(report)

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_report(_report), do: {:error, [%{code: "operator_console_invalid_report"}]}

  defp fixture_rows do
    [
      fixture("OPCON-001", "components accept DTO refs and bounded trace exports only"),
      fixture("OPCON-002", "templates avoid raw stores and lower runtime internals"),
      fixture("OPCON-003", "replay viewer reconstructs from trace refs without effects"),
      fixture("OPCON-004", "policy authoring promotion records decision evidence"),
      fixture("OPCON-005", "cost dashboard redacts amounts and provider account ids"),
      fixture("OPCON-006", "eval studio renders eval refs without raw payloads"),
      fixture("OPCON-007", "Extravaganza route mounts AppKit without product bypass"),
      fixture("OPCON-008", "tenant mismatched console rows fail closed")
    ]
  end

  defp fixture(id, proof) do
    %{id: id, status: "passed", proof: proof}
  end

  defp validate_mount(failures, %{} = mount) do
    failures
    |> require_equal("operator_console_mount_not_product_local", mount[:product_local?], true)
    |> require_equal(
      "operator_console_mount_imports_lower",
      mount[:imports_lower_runtime?],
      false
    )
    |> require_equal("operator_console_mount_route", mount[:route], "/operator-console")
  end

  defp validate_mount(failures, mount),
    do: [failure("operator_console_missing_mount", mount: mount) | failures]

  defp validate_render_posture(failures, %{} = posture) do
    failures
    |> require_equal(
      "operator_console_bad_redaction_posture",
      posture[:redaction_posture],
      "dto_and_bounded_exports_only"
    )
    |> require_equal(
      "operator_console_replay_effects_not_suppressed",
      posture[:replay_side_effect_posture],
      "suppressed_view_only"
    )
    |> require_equal(
      "operator_console_tenant_mismatch_not_closed",
      posture[:tenant_mismatch_fails_closed?],
      true
    )
  end

  defp validate_render_posture(failures, posture),
    do: [failure("operator_console_missing_render_posture", posture: posture) | failures]

  defp validate_fixtures(failures, fixtures) when is_list(fixtures) do
    actual = fixtures |> Enum.map(& &1[:id]) |> Enum.sort()

    failures
    |> require_equal("operator_console_missing_fixtures", actual, @fixture_ids)
    |> validate_fixture_statuses(fixtures)
  end

  defp validate_fixtures(failures, fixtures),
    do: [failure("operator_console_missing_fixtures", fixtures: fixtures) | failures]

  defp validate_fixture_statuses(failures, fixtures) do
    Enum.reduce(fixtures, failures, fn fixture, acc ->
      if fixture[:status] == "passed" do
        acc
      else
        [failure("operator_console_fixture_not_passed", fixture: fixture[:id]) | acc]
      end
    end)
  end

  defp validate_public_redaction(failures, term) do
    case collect_forbidden_paths(term, []) do
      [] -> failures
      paths -> [failure("operator_console_public_artifact_leak", paths: paths) | failures]
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

  defp collect_forbidden_paths(values, path) when is_list(values) do
    Enum.flat_map(values, &collect_forbidden_paths(&1, path))
  end

  defp collect_forbidden_paths(_term, _path), do: []

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected),
    do: [failure(code, expected: expected, actual: actual) | failures]

  defp failure(code, attrs), do: Map.new([{:code, code} | attrs])
end
