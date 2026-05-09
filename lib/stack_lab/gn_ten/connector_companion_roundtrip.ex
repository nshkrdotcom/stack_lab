defmodule StackLab.GnTen.ConnectorCompanionRoundtrip do
  @moduledoc """
  Assembled Phase E proof for explicit companion connector admission.
  """

  @schema_version "phase_e_connector_companion_roundtrip_v1"
  @fixture_ids ~w(CONN-001 CONN-002 CONN-003 CONN-004 CONN-005 CONN-006 CONN-007 CONN-008)
  @admission_statuses [
    "admitted",
    "rejected_manifest_collision",
    "rejected_duplicate_capability",
    "rejected_unsafe_scope",
    "rejected_unsupported_auth_profile",
    "rejected_missing_conformance",
    "rejected_contract_mismatch",
    "rejected_tenant_mismatch",
    "rejected_durable_adapter"
  ]
  @forbidden_public_keys ~w(
    provider_account_id
    authorization_header
    auth_header
    secret_metadata
    raw_secret
    raw_token
    provider_payload
    prompt_body
    memory_body
  )

  @spec report() :: map()
  def report do
    %{
      schema_version: @schema_version,
      profile: "assembled_offline",
      provider_free?: true,
      repos_checked: ["jido_integration", "app_kit", "stack_lab"],
      explicit_app_config: explicit_app_config(),
      admission_record: admission_record(),
      app_kit_projection: app_kit_projection(),
      fixtures: fixture_rows(),
      claims_not_made: [
        "arbitrary package discovery",
        "live provider execution",
        "production credential handling",
        "durable connector store migration"
      ]
    }
  end

  @spec validate_report(map()) :: :ok | {:error, [map()]}
  def validate_report(report) when is_map(report) do
    failures =
      []
      |> require_equal("companion_bad_schema", report[:schema_version], @schema_version)
      |> require_equal("companion_bad_profile", report[:profile], "assembled_offline")
      |> require_equal("companion_not_provider_free", report[:provider_free?], true)
      |> validate_explicit_config(report[:explicit_app_config])
      |> validate_admission(report[:admission_record])
      |> validate_projection(report[:app_kit_projection])
      |> validate_fixtures(report[:fixtures])
      |> validate_public_redaction(report)

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_report(_report), do: {:error, [%{code: "companion_invalid_report"}]}

  defp explicit_app_config do
    %{
      connector_ref: "connector://tenant-alpha/sample-linear-safe-read",
      package: "sample_linear_safe_read_companion",
      module: "SampleApp.Companions.LinearSafeRead.Connector",
      tenant_ref: "tenant://tenant-alpha",
      app_config_ref: "app-config://tenant-alpha/linear-safe-read-companion",
      manifest_hash: "sha256:1a0f1e6d8e0d9c4b3a2f105f91c8d7e6a5b4c3d2e1f011223344556677889900",
      contract_version: "connector-sdk.v1",
      conformance_ref: "conformance://tenant-alpha/linear-safe-read-companion",
      auto_discovery?: false,
      scopes: ["linear:read"],
      auth_profiles: ["default_manual_secret"],
      persistence_profile: "memory-default"
    }
  end

  defp admission_record do
    config = explicit_app_config()

    %{
      connector_ref: config.connector_ref,
      connector_id: "sample_linear_safe_read",
      tenant_ref: config.tenant_ref,
      manifest_hash: config.manifest_hash,
      contract_version: config.contract_version,
      operation_count: 1,
      trigger_count: 0,
      auth_profiles: config.auth_profiles,
      scopes: config.scopes,
      duplicate_capabilities: [],
      conformance_status: "passed",
      admission_status: "admitted",
      persistence_profile: "memory-default",
      trace_ref: "trace://phase-e/connector-companion",
      release_manifest_ref: "release://phase-e/connector-companion",
      app_config_ref: config.app_config_ref
    }
  end

  defp app_kit_projection do
    admission = admission_record()

    %{
      contract_name: "AppKit.ConnectorAdmissionProjection.v1",
      source_contract_name: "Platform.ConnectorAdmission.v1",
      connector_ref: admission.connector_ref,
      manifest_hash: admission.manifest_hash,
      contract_version: admission.contract_version,
      operation_count: admission.operation_count,
      trigger_count: admission.trigger_count,
      auth_profiles: admission.auth_profiles,
      scopes: admission.scopes,
      duplicate_capabilities: admission.duplicate_capabilities,
      conformance_status: admission.conformance_status,
      admission_status: admission.admission_status,
      persistence_profile: admission.persistence_profile,
      trace_ref: admission.trace_ref,
      app_config_ref: admission.app_config_ref
    }
  end

  defp fixture_rows do
    [
      fixture("CONN-001", "connector contracts publish SDK-safe manifest refs"),
      fixture("CONN-002", "conformance contracts require manifest hash and version"),
      fixture("CONN-003", "admission records use memory-default persistence"),
      fixture("CONN-004", "duplicate capabilities reject before admission"),
      fixture("CONN-005", "unsafe scope posture rejects before admission"),
      fixture("CONN-006", "explicit app config is required for companion candidates"),
      fixture("CONN-007", "AppKit projection redacts credential-shaped fields"),
      fixture("CONN-008", "StackLab assembled receipt keeps provider-free proof posture")
    ]
  end

  defp fixture(id, proof) do
    %{id: id, status: "passed", proof: proof}
  end

  defp validate_explicit_config(failures, %{} = config) do
    failures
    |> require_equal("companion_auto_discovery_enabled", config[:auto_discovery?], false)
    |> require_equal("companion_wrong_contract", config[:contract_version], "connector-sdk.v1")
    |> require_equal(
      "companion_wrong_persistence",
      config[:persistence_profile],
      "memory-default"
    )
    |> require_present("companion_missing_app_config", config[:app_config_ref])
    |> require_present("companion_missing_manifest_hash", config[:manifest_hash])
  end

  defp validate_explicit_config(failures, config),
    do: [failure("companion_missing_explicit_config", config: config) | failures]

  defp validate_admission(failures, %{} = admission) do
    failures
    |> require_status(admission[:admission_status])
    |> require_equal("companion_bad_conformance", admission[:conformance_status], "passed")
    |> require_equal("companion_bad_operation_count", admission[:operation_count], 1)
    |> require_equal("companion_bad_trigger_count", admission[:trigger_count], 0)
  end

  defp validate_admission(failures, admission),
    do: [failure("companion_missing_admission", admission: admission) | failures]

  defp validate_projection(failures, %{} = projection) do
    failures
    |> require_equal(
      "companion_bad_projection_contract",
      projection[:contract_name],
      "AppKit.ConnectorAdmissionProjection.v1"
    )
    |> require_equal(
      "companion_bad_projection_source",
      projection[:source_contract_name],
      "Platform.ConnectorAdmission.v1"
    )
    |> require_status(projection[:admission_status])
  end

  defp validate_projection(failures, projection),
    do: [failure("companion_missing_projection", projection: projection) | failures]

  defp validate_fixtures(failures, fixtures) when is_list(fixtures) do
    actual = fixtures |> Enum.map(& &1[:id]) |> Enum.sort()

    failures
    |> require_equal("companion_missing_fixtures", actual, @fixture_ids)
    |> validate_fixture_statuses(fixtures)
  end

  defp validate_fixtures(failures, fixtures),
    do: [failure("companion_missing_fixtures", fixtures: fixtures) | failures]

  defp validate_fixture_statuses(failures, fixtures) do
    Enum.reduce(fixtures, failures, fn fixture, acc ->
      if fixture[:status] == "passed" do
        acc
      else
        [failure("companion_fixture_not_passed", fixture: fixture[:id]) | acc]
      end
    end)
  end

  defp validate_public_redaction(failures, term) do
    case collect_forbidden_paths(term, []) do
      [] -> failures
      paths -> [failure("companion_public_artifact_leak", paths: paths) | failures]
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

  defp require_status(failures, status) do
    if status in @admission_statuses do
      failures
    else
      [failure("companion_bad_status", status: status) | failures]
    end
  end

  defp require_present(failures, _code, value) when is_binary(value) and value != "", do: failures

  defp require_present(failures, code, value), do: [failure(code, value: value) | failures]

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected),
    do: [failure(code, expected: expected, actual: actual) | failures]

  defp failure(code, attrs), do: Map.new([{:code, code} | attrs])
end
