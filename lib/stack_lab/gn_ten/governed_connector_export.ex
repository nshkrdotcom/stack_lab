defmodule StackLab.GnTen.GovernedConnectorExport do
  @moduledoc """
  Deterministic governed connector compliance export fixture.

  The fixture is provider-free and ref-only. It proves that governed connector
  export evidence can be regenerated deterministically without raw secrets,
  native auth material, prompt bodies, untrusted content bodies, or provider
  payload bodies in public artifacts.
  """

  alias GroundPlane.Boundary.Codec, as: BoundaryCodec

  @schema_version "gn_ten_governed_connector_export_v1"
  @profile "assembled_offline"
  @tenant_ref "tenant://stack-lab/governed-export"
  @installation_ref "installation://stack-lab/governed-export/github"
  @authority_ref "authority://stack-lab/governed-export/policy"
  @trace_ref "trace://stack-lab/governed-export/github/fixture"
  @source_trace_ref "source-trace://stack-lab/governed-export/github/fixture"
  @release_manifest_ref "release-manifest://stack-lab/gn-ten/governed-export/v1"
  @evidence_anchor_ref "evidence://stack-lab/gn-ten/governed-export/v1"
  @export_ref "export://stack-lab/governed-connector-export/github/v1"
  @exporter_ref "exporter://aitrace/governed-compliance/offline"
  @export_context_ref "export-context://stack-lab/governed-connector-export/github/v1"
  @connector_binding_ref "connector-binding://stack-lab/github/governed-export"
  @credential_lease_ref "credential-lease://stack-lab/github/governed-export"
  @lower_receipt_ref "lower-receipt://github/governed-export/succeeded"
  @redaction_ref "redaction://stack-lab/governed-connector-export/ref-only"
  @connector_manifest_ref "manifest://jido/connectors/github/governed-export"
  @operation_policy_ref "operation-policy://stack-lab/github/governed-export"
  @replay_bundle_ref "replay-bundle://stack-lab/governed-connector-export/github/v1"
  @codec_ref "ground-plane.boundary.codec.v1"
  @forbidden_public_keys [
    "api_key",
    "access_token",
    "refresh_token",
    "client_secret",
    "provider_token",
    "credential_material",
    "native_auth_material",
    "private_key",
    "secret",
    "token",
    "raw_prompt",
    "prompt_body",
    "provider_payload",
    "provider_response_body",
    "raw_payload",
    "raw_body",
    "untrusted_content_body"
  ]
  @denied_public_payload_keys [
    "api_key",
    "access_token",
    "refresh_token",
    "client_secret",
    "provider_token",
    "credential_material",
    "native_auth_material",
    "private_key",
    "raw_prompt",
    "prompt_body",
    "provider_payload",
    "provider_response_body",
    "raw_payload",
    "raw_body",
    "untrusted_content_body"
  ]

  @spec bundle() :: map()
  def bundle do
    base = base_bundle()
    bundle_hash = BoundaryCodec.digest(base)
    spill_hash = BoundaryCodec.digest(spill_hash_shape(base, bundle_hash))

    base
    |> Map.put("bundle_hash", bundle_hash)
    |> Map.put("spill_hash", spill_hash)
  end

  @spec validate_bundle(map()) :: :ok | {:error, [map()]}
  def validate_bundle(bundle) when is_map(bundle) do
    failures =
      []
      |> require_equal("export_bad_schema", bundle["schema_version"], @schema_version)
      |> require_equal("export_bad_profile", bundle["profile"], @profile)
      |> validate_export_context(bundle["export_context"])
      |> validate_source_trace(bundle["source_trace"])
      |> validate_replay_export(bundle["replay_export"])
      |> validate_audit_refs(bundle["audit_refs"])
      |> validate_hashes(bundle)
      |> validate_canonical_codec(bundle)
      |> validate_redaction(bundle)

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_bundle(_bundle), do: {:error, [%{code: "export_invalid_bundle"}]}

  @spec forbidden_public_key_paths(map()) :: [[String.t()]]
  def forbidden_public_key_paths(bundle) when is_map(bundle) do
    collect_forbidden_key_paths(bundle, [])
  end

  defp base_bundle do
    %{
      "schema_version" => @schema_version,
      "profile" => @profile,
      "provider_free" => true,
      "export_ref" => @export_ref,
      "release_manifest_ref" => @release_manifest_ref,
      "evidence_anchor_ref" => @evidence_anchor_ref,
      "canonical_boundary_codec_ref" => @codec_ref,
      "export_context" => export_context(),
      "source_trace" => source_trace(),
      "audit_refs" => audit_refs(),
      "public_payload" => public_payload(),
      "replay_export" => replay_export(),
      "redaction_summary" => redaction_summary()
    }
  end

  defp export_context do
    %{
      "kind" => "governed_aitrace_export_context",
      "export_context_ref" => @export_context_ref,
      "exporter_ref" => @exporter_ref,
      "tenant_ref" => @tenant_ref,
      "installation_ref" => @installation_ref,
      "authority_ref" => @authority_ref,
      "trace_ref" => @trace_ref,
      "release_manifest_ref" => @release_manifest_ref,
      "evidence_anchor_ref" => @evidence_anchor_ref,
      "ambient_exporters_allowed" => false
    }
  end

  defp source_trace do
    %{
      "source_trace_ref" => @source_trace_ref,
      "trace_ref" => @trace_ref,
      "tenant_ref" => @tenant_ref,
      "replay_addressable" => true
    }
  end

  defp audit_refs do
    %{
      "tenant_ref" => @tenant_ref,
      "installation_ref" => @installation_ref,
      "authority_ref" => @authority_ref,
      "connector_manifest_ref" => @connector_manifest_ref,
      "connector_binding_ref" => @connector_binding_ref,
      "credential_lease_ref" => @credential_lease_ref,
      "lower_receipt_refs" => [@lower_receipt_ref],
      "operation_policy_ref" => @operation_policy_ref,
      "redaction_ref" => @redaction_ref
    }
  end

  defp public_payload do
    %{
      "operation_class" => "connector.compliance_export",
      "connector_family" => "github",
      "connector_binding_ref" => @connector_binding_ref,
      "credential_lease_ref" => @credential_lease_ref,
      "lower_receipt_ref" => @lower_receipt_ref,
      "provider_object_refs" => ["provider-object-ref://github/pull-request/redacted-57"],
      "prompt_ref" => "prompt://stack-lab/governed-export/redacted",
      "untrusted_content_ref" => "content-ref://stack-lab/governed-export/untrusted/redacted",
      "redaction_ref" => @redaction_ref
    }
  end

  defp replay_export do
    %{
      "replay_bundle_ref" => @replay_bundle_ref,
      "export_context_ref" => @export_context_ref,
      "source_trace_ref" => @source_trace_ref,
      "source_tenant_ref" => @tenant_ref,
      "tenant_ref" => @tenant_ref,
      "trace_ref" => @trace_ref,
      "release_manifest_ref" => @release_manifest_ref,
      "evidence_anchor_ref" => @evidence_anchor_ref
    }
  end

  defp redaction_summary do
    %{
      "secret_material_public" => false,
      "native_auth_public" => false,
      "prompt_bodies_public" => false,
      "provider_bodies_public" => false,
      "untrusted_content_bodies_public" => false,
      "denied_public_payload_keys" => @denied_public_payload_keys
    }
  end

  defp spill_hash_shape(base, bundle_hash) do
    %{
      "schema_version" => "gn_ten_governed_connector_export_spill_v1",
      "export_ref" => base["export_ref"],
      "bundle_hash" => bundle_hash,
      "canonical_boundary_codec_ref" => @codec_ref
    }
  end

  defp validate_export_context(failures, %{} = context) do
    failures
    |> require_equal(
      "export_missing_governed_context",
      context["kind"],
      "governed_aitrace_export_context"
    )
    |> require_present("export_missing_exporter_ref", context["exporter_ref"])
    |> require_present("export_missing_export_context_ref", context["export_context_ref"])
    |> require_equal(
      "export_ambient_exporters_allowed",
      context["ambient_exporters_allowed"],
      false
    )
    |> require_present("export_missing_tenant_ref", context["tenant_ref"])
    |> require_present("export_missing_installation_ref", context["installation_ref"])
    |> require_present("export_missing_authority_ref", context["authority_ref"])
    |> require_present("export_missing_trace_ref", context["trace_ref"])
  end

  defp validate_export_context(failures, _context) do
    [failure("export_missing_governed_context") | failures]
  end

  defp validate_source_trace(failures, %{} = source_trace) do
    failures
    |> require_present("export_missing_source_trace_ref", source_trace["source_trace_ref"])
    |> require_present("export_missing_source_trace_tenant_ref", source_trace["tenant_ref"])
  end

  defp validate_source_trace(failures, _source_trace) do
    [failure("export_missing_source_trace") | failures]
  end

  defp validate_replay_export(failures, %{} = replay_export) do
    failures
    |> require_present("export_missing_replay_bundle_ref", replay_export["replay_bundle_ref"])
    |> require_present("export_missing_replay_tenant_ref", replay_export["tenant_ref"])
    |> require_equal(
      "export_replay_cross_tenant",
      replay_export["source_tenant_ref"],
      replay_export["tenant_ref"]
    )
  end

  defp validate_replay_export(failures, _replay_export) do
    [failure("export_missing_replay_export") | failures]
  end

  defp validate_audit_refs(failures, %{} = audit_refs) do
    failures
    |> require_present(
      "export_missing_connector_binding_ref",
      audit_refs["connector_binding_ref"]
    )
    |> require_present("export_missing_credential_lease_ref", audit_refs["credential_lease_ref"])
    |> require_nonempty_list(
      "export_missing_lower_receipt_refs",
      audit_refs["lower_receipt_refs"]
    )
    |> require_present("export_missing_redaction_ref", audit_refs["redaction_ref"])
  end

  defp validate_audit_refs(failures, _audit_refs) do
    [failure("export_missing_audit_refs") | failures]
  end

  defp validate_hashes(failures, %{} = bundle) do
    base = Map.drop(bundle, ["bundle_hash", "spill_hash"])

    case boundary_digest(base) do
      {:ok, expected_bundle_hash} ->
        expected_spill_hash = BoundaryCodec.digest(spill_hash_shape(base, expected_bundle_hash))

        failures
        |> require_equal(
          "export_bundle_hash_mismatch",
          bundle["bundle_hash"],
          expected_bundle_hash
        )
        |> require_equal("export_spill_hash_mismatch", bundle["spill_hash"], expected_spill_hash)

      {:error, reason} ->
        [failure("export_bundle_hash_unverifiable", reason: inspect(reason)) | failures]
    end
  end

  defp validate_canonical_codec(failures, %{} = bundle) do
    case BoundaryCodec.encode(Map.drop(bundle, ["bundle_hash", "spill_hash"])) do
      {:ok, encoded} when is_binary(encoded) ->
        failures

      {:error, reason} ->
        [failure("export_boundary_codec_rejected", reason: inspect(reason)) | failures]
    end
  end

  defp validate_redaction(failures, %{} = bundle) do
    forbidden_paths = collect_forbidden_key_paths(bundle, [])

    if forbidden_paths == [] do
      failures
    else
      [failure("export_public_artifact_leak", paths: forbidden_paths) | failures]
    end
  end

  defp collect_forbidden_key_paths(%{} = map, path) do
    Enum.flat_map(map, fn {key, value} ->
      key_string = to_string(key)
      next_path = [key_string | path]

      if forbidden_public_key?(key_string) do
        [Enum.reverse(next_path)]
      else
        collect_forbidden_key_paths(value, next_path)
      end
    end)
  end

  defp collect_forbidden_key_paths(list, path) when is_list(list) do
    Enum.flat_map(list, &collect_forbidden_key_paths(&1, path))
  end

  defp collect_forbidden_key_paths(_value, _path), do: []

  defp forbidden_public_key?(key) do
    normalized = String.downcase(key)
    normalized in @forbidden_public_keys
  end

  defp boundary_digest(term) do
    case BoundaryCodec.encode(term) do
      {:ok, encoded} ->
        digest =
          "sha256:" <>
            (encoded
             |> then(&:crypto.hash(:sha256, &1))
             |> Base.encode16(case: :lower))

        {:ok, digest}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp require_present(failures, _code, value) when is_binary(value) and value != "", do: failures

  defp require_present(failures, code, value),
    do: [failure(code, actual: inspect(value)) | failures]

  defp require_nonempty_list(failures, _code, [_ | _]), do: failures

  defp require_nonempty_list(failures, code, value),
    do: [failure(code, actual: inspect(value)) | failures]

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected),
    do: [failure(code, expected: inspect(expected), actual: inspect(actual)) | failures]

  defp failure(code, attrs \\ []), do: Map.new([{:code, code} | attrs])
end
