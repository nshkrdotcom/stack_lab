defmodule StackLab.ConnectorHardeningScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.ConnectorHardeningScanner
  alias StackLab.ConnectorHardeningScanner.Finding
  alias StackLab.ConnectorHardeningScanner.Receipt

  test "emits a passing receipt for governed connector evidence" do
    assert {:ok, %Receipt{} = receipt} =
             ConnectorHardeningScanner.scan(valid_attrs())

    assert receipt.status == :pass
    assert receipt.fixture_ref == "UAA-042"
    assert receipt.owner_repo == "github_ex"
    assert receipt.package_path == "."
    assert receipt.target_code_paths == ["lib/github_ex/governed_authority.ex"]
    assert receipt.required_refs == ConnectorHardeningScanner.required_refs()
    assert receipt.findings == []
  end

  test "reports env, token storage, direct client, and missing ref defects" do
    attrs =
      valid_attrs(
        signals: %{
          env_reads: %{"GITHUB_TOKEN" => "raw-env-value"},
          token_storage: [:oauth_token_file],
          direct_http_clients: [:req],
          provider_payload_projection: [:response_body]
        },
        refs: %{
          tenant_ref: "tenant://tenant-1",
          installation_ref: "installation://tenant-1/github/http/default",
          trace_ref: "trace://tenant-1/github/http/operation",
          provider_account_ref: "provider-account://tenant-1/github/default",
          connector_instance_ref: "connector-instance://tenant-1/github/default",
          connector_binding_ref: "",
          credential_handle_ref: "credential-handle://tenant-1/github/default",
          credential_lease_ref: "",
          target_ref: "",
          connector_admission_ref: "",
          request_scope_ref: "request-scope://tenant-1/github/user",
          operation_policy_ref: "operation-policy://tenant-1/github/user",
          redaction_ref: ""
        }
      )

    assert {:ok, %Receipt{status: :open_defect, findings: findings}} =
             ConnectorHardeningScanner.scan(attrs)

    assert %Finding{rule: :env_reads, details: %{field_names: ["GITHUB_TOKEN"]}} =
             find_rule(findings, :env_reads)

    assert %Finding{rule: :token_storage, details: %{field_names: [:oauth_token_file]}} =
             find_rule(findings, :token_storage)

    assert %Finding{rule: :direct_http_clients, details: %{field_names: [:req]}} =
             find_rule(findings, :direct_http_clients)

    assert %Finding{rule: :provider_payload_projection, details: %{field_names: [:response_body]}} =
             find_rule(findings, :provider_payload_projection)

    assert %Finding{rule: :binding_refs, details: %{missing_refs: [:connector_binding_ref]}} =
             find_rule(findings, :binding_refs)

    assert %Finding{rule: :lease_refs, details: %{missing_refs: [:credential_lease_ref]}} =
             find_rule(findings, :lease_refs)

    assert %Finding{rule: :admission_refs, details: %{missing_refs: [:connector_admission_ref]}} =
             find_rule(findings, :admission_refs)

    assert %Finding{rule: :target_refs, details: %{missing_refs: [:target_ref]}} =
             find_rule(findings, :target_refs)

    assert %Finding{rule: :redaction_refs, details: %{missing_refs: [:redaction_ref]}} =
             find_rule(findings, :redaction_refs)

    refute inspect(findings) |> String.contains?("raw-env-value")
  end

  test "requires proof refs for runtime, parser, dispatch, retry, webhook, pagination, and telemetry rules" do
    attrs =
      valid_attrs(
        proof_refs: %{
          generated_runtime_schema: "proof://github/generated-runtime-schema",
          auth_parser: "",
          operation_dispatch: "proof://github/operation-dispatch",
          retries: "proof://github/retries",
          webhooks: "proof://github/webhooks",
          pagination: "proof://github/pagination",
          telemetry: nil
        }
      )

    assert {:ok, %Receipt{status: :open_defect, findings: findings}} =
             ConnectorHardeningScanner.scan(attrs)

    assert find_rule(findings, :auth_parser).reason == :missing_proof_ref
    assert find_rule(findings, :telemetry).reason == :missing_proof_ref
    refute Enum.any?(findings, &(&1.rule == :generated_runtime_schema))
  end

  test "rejects unknown rules" do
    assert {:error, {:unknown_rules, [:pattern_scan]}} =
             ConnectorHardeningScanner.scan(valid_attrs(rules: [:env_reads, :pattern_scan]))
  end

  defp find_rule(findings, rule) do
    Enum.find(findings, &(&1.rule == rule))
  end

  defp valid_attrs(overrides \\ []) do
    attrs = %{
      owner_repo: "github_ex",
      package_path: ".",
      target_code_paths: ["lib/github_ex/governed_authority.ex"],
      refs: %{
        tenant_ref: "tenant://tenant-1",
        installation_ref: "installation://tenant-1/github/http/default",
        trace_ref: "trace://tenant-1/github/http/operation",
        provider_account_ref: "provider-account://tenant-1/github/default",
        connector_instance_ref: "connector-instance://tenant-1/github/default",
        connector_binding_ref: "connector-binding://tenant-1/github/default",
        credential_handle_ref: "credential-handle://tenant-1/github/default",
        credential_lease_ref: "credential-lease://tenant-1/github/default",
        target_ref: "target://tenant-1/github/rest",
        connector_admission_ref: "connector-admission://tenant-1/github/http/issues",
        request_scope_ref: "request-scope://tenant-1/github/user",
        operation_policy_ref: "operation-policy://tenant-1/github/user",
        redaction_ref: "redaction://tenant-1/github/default"
      },
      proof_refs: %{
        generated_runtime_schema: "proof://github/generated-runtime-schema",
        auth_parser: "proof://github/auth-parser",
        operation_dispatch: "proof://github/operation-dispatch",
        retries: "proof://github/retries",
        webhooks: "proof://github/webhooks",
        pagination: "proof://github/pagination",
        telemetry: "proof://github/telemetry"
      },
      signals: %{
        env_reads: [],
        token_storage: [],
        direct_http_clients: [],
        provider_payload_projection: []
      }
    }

    Map.merge(attrs, Map.new(overrides))
  end
end
