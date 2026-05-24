defmodule StackLab.ContextABIScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.ContextABIScanner

  test "passes a complete ref-only Context ABI handoff" do
    assert {:ok, receipt} =
             ContextABIScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "examples/context_abi_roundtrip",
               context_packets: [packet()],
               context_compile_receipts: [compile_receipt()],
               authority_grants: [grant()],
               admission_receipts: [admission_receipt()],
               route_decisions: [route_decision()],
               render_results: [render_result()],
               model_invocation_receipts: [model_receipt()],
               appkit_projections: [%{context_packet_ref: packet().context_packet_ref}],
               aitrace_facts: [%{trace_ref: packet().trace_ref}]
             })

    assert receipt.status == :pass
    assert receipt.findings == []
    assert :render_handoff_contract in receipt.checked_rules
  end

  test "requires context packet hashes and render refs" do
    bad_packet = Map.delete(packet(), :packet_hash)
    bad_render = Map.delete(render_result(), :provider_payload_ref)

    assert {:ok, receipt} =
             ContextABIScanner.scan(%{
               context_packets: [bad_packet],
               context_compile_receipts: [compile_receipt()],
               authority_grants: [grant()],
               admission_receipts: [admission_receipt()],
               route_decisions: [route_decision()],
               render_results: [bad_render],
               model_invocation_receipts: [model_receipt()],
               appkit_projections: [%{context_packet_ref: packet().context_packet_ref}],
               aitrace_facts: [%{trace_ref: packet().trace_ref}]
             })

    assert receipt.status == :open_defect
    assert has_finding?(receipt, :context_packet_contract, {:missing_required_ref, :packet_hash})

    assert has_finding?(
             receipt,
             :render_handoff_contract,
             {:missing_required_ref, :provider_payload_ref}
           )
  end

  test "rejects raw prompt and provider payload fields anywhere in the scan" do
    assert {:ok, receipt} =
             ContextABIScanner.scan(%{
               context_packets: [packet()],
               context_compile_receipts: [compile_receipt()],
               authority_grants: [grant()],
               admission_receipts: [admission_receipt()],
               route_decisions: [route_decision()],
               render_results: [render_result()],
               model_invocation_receipts: [model_receipt()],
               appkit_projections: [%{context_packet_ref: packet().context_packet_ref}],
               aitrace_facts: [%{trace_ref: packet().trace_ref}],
               proof_metadata: %{raw_prompt: "nope"}
             })

    assert receipt.status == :open_defect
    assert has_finding?(receipt, :no_raw_context_payloads, {:forbidden_raw_field, "raw_prompt"})
  end

  test "detects cross-tenant handoff facts" do
    assert {:ok, receipt} =
             ContextABIScanner.scan(%{
               context_packets: [packet()],
               context_compile_receipts: [compile_receipt()],
               authority_grants: [%{grant() | tenant_ref: "tenant://other"}],
               admission_receipts: [admission_receipt()],
               route_decisions: [route_decision()],
               render_results: [render_result()],
               model_invocation_receipts: [model_receipt()],
               appkit_projections: [%{context_packet_ref: packet().context_packet_ref}],
               aitrace_facts: [%{trace_ref: packet().trace_ref}]
             })

    assert receipt.status == :open_defect
    assert has_finding?(receipt, :tenant_consistency, :cross_tenant_refs)
  end

  defp has_finding?(receipt, rule, reason) do
    Enum.any?(receipt.findings, &(&1.rule == rule and &1.reason == reason))
  end

  defp packet do
    %{
      tenant_ref: "tenant://a",
      context_packet_ref: "context-packet://a",
      packet_hash: sha("a"),
      user_request_ref: "artifact://request/a",
      system_instruction_ref: "artifact://system/a",
      memory_refs: ["memory://a"],
      budget_ref: "budget://a",
      model_class_allowlist: ["model-class://fixture"],
      route_policy_ref: "route-policy://fixture",
      trace_ref: "trace://a"
    }
  end

  defp compile_receipt do
    %{
      receipt_ref: "context-packet-receipt://a",
      context_packet_ref: packet().context_packet_ref,
      tenant_ref: packet().tenant_ref,
      status: :compiled,
      packet_hash: packet().packet_hash,
      trace_ref: packet().trace_ref
    }
  end

  defp grant do
    %{
      authority_ref: "authority://a",
      tenant_ref: packet().tenant_ref,
      allowed_model_classes: packet().model_class_allowlist,
      route_policy_ref: packet().route_policy_ref,
      trace_ref: packet().trace_ref
    }
  end

  defp admission_receipt do
    %{
      receipt_ref: "packet-admission://a",
      context_packet_ref: packet().context_packet_ref,
      workflow_ref: "workflow://a",
      tenant_ref: packet().tenant_ref,
      authority_ref: grant().authority_ref,
      packet_hash: packet().packet_hash,
      status: :admitted,
      idempotency_key: "idem://a",
      trace_ref: packet().trace_ref
    }
  end

  defp route_decision do
    %{
      route_decision_ref: "route-decision://a",
      selected_route_kind: :fixture,
      selected_model_profile_ref: "model-class://fixture",
      route_policy_ref: packet().route_policy_ref,
      trace_ref: packet().trace_ref
    }
  end

  defp render_result do
    %{
      tenant_ref: packet().tenant_ref,
      workflow_ref: admission_receipt().workflow_ref,
      context_packet_ref: packet().context_packet_ref,
      route_decision_ref: route_decision().route_decision_ref,
      prompt_artifact_ref: "prompt-artifact://a",
      provider_payload_ref: "provider-payload://a",
      payload_hash: sha("b"),
      provider_family: "fixture",
      trace_ref: packet().trace_ref
    }
  end

  defp model_receipt do
    %{
      receipt_ref: "jido-model-invocation-receipt://a",
      invocation_ref: "model-invocation://a",
      tenant_ref: packet().tenant_ref,
      status: :ok,
      context_packet_ref: packet().context_packet_ref,
      route_decision_ref: route_decision().route_decision_ref,
      prompt_artifact_ref: render_result().prompt_artifact_ref,
      provider_payload_ref: render_result().provider_payload_ref,
      payload_hash: render_result().payload_hash,
      model_profile_ref: route_decision().selected_model_profile_ref,
      provider_ref: "provider://fixture",
      endpoint_ref: "endpoint://fixture",
      runtime_ref: "runtime://fixture",
      runtime_kind: "client",
      credential_lease_ref: "credential-lease://fixture",
      trace_ref: packet().trace_ref,
      idempotency_key: "idem://model"
    }
  end

  defp sha(char), do: "sha256:" <> String.duplicate(char, 64)
end
