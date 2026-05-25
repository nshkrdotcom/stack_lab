defmodule StackLab.GnTenNodeLab.EnvelopeScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTenNodeLab.EnvelopeScanner

  test "passes a valid distributed envelope" do
    receipt = EnvelopeScanner.scan(valid_envelope())

    assert receipt["status"] == "pass"
    assert receipt["findings"] == []
    assert receipt["tenant_ref"] == "tenant://demo"
  end

  test "fails missing required distributed fields" do
    receipt =
      valid_envelope()
      |> Map.drop([:tenant_ref, :idempotency_key, :origin_node_ref, :redaction_class])
      |> EnvelopeScanner.scan()

    assert receipt["status"] == "open_defect"
    assert_has_reason(receipt, "missing_required_field")
  end

  test "requires schema, authority, and trace evidence" do
    receipt =
      valid_envelope()
      |> Map.drop([:schema_version, :authority_ref, :trace_ref])
      |> EnvelopeScanner.scan()

    assert_has_rule(receipt, "missing_schema")
    assert_has_rule(receipt, "missing_authority")
    assert_has_rule(receipt, "missing_trace")
  end

  test "allows explicit authority-not-required posture" do
    receipt =
      valid_envelope()
      |> Map.delete(:authority_ref)
      |> Map.put(:authority_required?, false)
      |> EnvelopeScanner.scan()

    refute_has_rule(receipt, "missing_authority")
  end

  test "flags stale schema versions" do
    receipt =
      valid_envelope()
      |> Map.put(:schema_version, "context_packet.v0")
      |> EnvelopeScanner.scan(supported_schema_versions: ["context_packet.v1"])

    assert_has_rule(receipt, "version_mismatch")
  end

  test "flags cross-tenant read fields" do
    receipt =
      valid_envelope()
      |> Map.put(:read_tenant_ref, "tenant://other")
      |> EnvelopeScanner.scan()

    assert_has_rule(receipt, "cross_tenant_read")
  end

  test "flags raw prompt and provider payload fields" do
    receipt =
      valid_envelope()
      |> Map.put(:payload, %{raw_prompt: "secret prompt", provider_payload: %{messages: []}})
      |> EnvelopeScanner.scan()

    assert_has_rule(receipt, "payload_not_allowed")
  end

  test "flags local-only runtime terms" do
    receipt =
      valid_envelope()
      |> Map.put(:payload, %{pid: self(), callback: fn -> :ok end})
      |> EnvelopeScanner.scan()

    assert_has_rule(receipt, "local_only_term")
  end

  test "flags direct lower imports in envelope facts" do
    receipt =
      valid_envelope()
      |> Map.put(:direct_lower_import, "JidoIntegration.ProviderRegistry")
      |> EnvelopeScanner.scan()

    assert_has_rule(receipt, "direct_lower_import")
  end

  defp valid_envelope do
    %{
      schema_version: "context_packet.v1",
      tenant_ref: "tenant://demo",
      correlation_ref: "corr://demo/1",
      idempotency_key: "idempotency://demo/1",
      origin_node_ref: "node://stack_lab/controller",
      target_profile: "outer_brain_context",
      authority_ref: "authority://demo/grant/1",
      redaction_class: "bounded",
      payload_mode: "refs_only",
      trace_ref: "trace://demo/1",
      issued_at: "2026-05-25T00:00:00Z",
      payload: %{context_packet_ref: "context-packet://demo/1"}
    }
  end

  defp assert_has_rule(receipt, rule) do
    assert Enum.any?(receipt["findings"], &(&1["rule"] == rule))
  end

  defp refute_has_rule(receipt, rule) do
    refute Enum.any?(receipt["findings"], &(&1["rule"] == rule))
  end

  defp assert_has_reason(receipt, reason) do
    assert Enum.any?(receipt["findings"], &(&1["reason"] == reason))
  end
end
