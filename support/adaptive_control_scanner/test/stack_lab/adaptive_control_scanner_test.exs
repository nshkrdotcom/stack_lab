defmodule StackLab.AdaptiveControlScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.AdaptiveControlScanner

  test "passes complete adaptive-control facts" do
    assert {:ok, receipt} =
             AdaptiveControlScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/adaptive_control_engine",
               adaptive_control_facts: [complete_fact()]
             })

    assert receipt.status == :pass
    assert "AOC-040" in receipt.fixture_refs
    assert receipt.findings == []
  end

  test "passes Phase 14 provider, SDK, persistence, and debug sidecar facts" do
    assert {:ok, receipt} =
             AdaptiveControlScanner.scan(%{
               owner_repo: "stack_lab",
               package_path: "support/adaptive_control_scanner",
               adaptive_control_facts: [complete_fact()],
               provider_adapter_facts: [provider_adapter_fact()],
               persistence_facts: [persistence_fact()],
               debug_sidecar_facts: [debug_sidecar_fact()]
             })

    assert receipt.status == :pass
    assert "AOC-045" in receipt.fixture_refs
    assert "AOC-046" in receipt.fixture_refs
    assert "AOC-047" in receipt.fixture_refs
    assert "PERSIST-AOC-006" in receipt.fixture_refs
    assert "PERSIST-AOC-007" in receipt.fixture_refs
  end

  test "requires trace, dataset, candidate, gate, promotion, rollback, stale rejection, projection, and receipt refs" do
    assert {:ok, receipt} =
             AdaptiveControlScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/adaptive_control_engine",
               adaptive_control_facts: [%{}]
             })

    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.rule) == [
             :trinity_trace_refs,
             :eval_dataset_refs,
             :replay_dataset_refs,
             :gepa_target_refs,
             :candidate_refs,
             :shadow_gate_refs,
             :canary_gate_refs,
             :approval_refs,
             :promotion_refs,
             :rollback_refs,
             :stale_artifact_rejection_refs,
             :appkit_projection_refs,
             :receipt_refs
           ]
  end

  test "rejects raw adaptive-control payloads and unredacted trace posture" do
    fact =
      complete_fact()
      |> Map.put(:trace_redaction, :raw)
      |> Map.put(:provider_payload, %{body: "hidden"})

    assert {:ok, receipt} =
             AdaptiveControlScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/adaptive_control_engine",
               adaptive_control_facts: [fact]
             })

    assert has_finding?(receipt, :trinity_trace_refs, :trace_refs_not_redacted)
    assert has_finding?(receipt, :raw_payload, {:forbidden_raw_field, :provider_payload})
  end

  defp has_finding?(receipt, rule, reason) do
    Enum.any?(receipt.findings, fn finding ->
      finding.rule == rule and finding.reason == reason
    end)
  end

  defp complete_fact do
    %{
      trinity_trace_refs: ["trace://trinity/repair"],
      eval_dataset_refs: ["eval-dataset://trinity/repair"],
      replay_dataset_refs: ["replay-dataset://trinity/repair"],
      gepa_target_refs: ["gepa-target://role-prompt"],
      candidate_refs: ["candidate://role-worker/v2"],
      shadow_gate_refs: ["shadow://candidate/worker/v2"],
      canary_gate_refs: ["canary://candidate/worker/v2"],
      approval_refs: ["approval://operator/worker/v2"],
      promotion_refs: ["promotion://candidate/worker/v2"],
      rollback_refs: ["rollback://candidate/worker/v1"],
      stale_artifact_rejection_refs: ["stale-rejection://candidate/worker/v1"],
      appkit_projection_refs: ["appkit://adaptive-control/worker"],
      receipt_refs: ["adaptive-control-receipt://worker"],
      trace_redaction: :redacted
    }
  end

  defp provider_adapter_fact do
    %{
      live_provider_gate_ref: "live-provider-gate://phase14/openai",
      gepa_proof_ref: "proof://phase6/gepa",
      trinity_proof_ref: "proof://phase8/trinity",
      adaptive_control_proof_ref: "proof://phase13/adaptive-control",
      disposable_credential_lease_ref: "credential-lease://phase14/openai/disposable",
      cleanup_ref: "cleanup://phase14/openai/disposable",
      provider_account_ref: "provider-account://phase14/openai/disposable",
      model_profile_ref: "model-profile://phase14/openai/proposer",
      operation_policy_ref: "operation-policy://phase14/live-provider/propose",
      pristine_operation_ref: "pristine-operation://github/issues/list",
      connector_admission_ref: "connector-admission://tenant-1/github",
      prismatic_operation_ref: "prismatic-operation://linear/viewer",
      operation_name: "Viewer",
      workspace_ref: "workspace://tenant-1/product",
      token_family_ref: "token-family://tenant-1/linear/api-token",
      subject_ref: "subject://tenant-1/operator/ada",
      trace_ref: "trace://phase14/provider-adapter",
      redaction_ref: "redaction://phase14/provider-adapter",
      live_network_required?: false,
      raw_material_present?: false
    }
  end

  defp persistence_fact do
    %{
      profile_id: :integration_postgres,
      store_category: :debug_capture,
      selected_tier: :postgres,
      migration_ref: "migration://phase14/debug-capture",
      substrate_ref: "postgres-substrate://phase14/integration",
      partition_ref: "partition://tenant-1/debug",
      retention_ref: "retention://tenant-1/debug",
      fail_closed_condition: :missing_substrate_or_migration,
      receipt_ref: "persistence-profile://phase14/integration-postgres"
    }
  end

  defp debug_sidecar_fact do
    %{
      debug_tap_ref: "debug-tap://tenant-1/redacted",
      trace_ref: "trace://phase14/debug",
      summary_ref: "summary://phase14/debug",
      state_ref: "state://phase14/debug",
      payload_hash_ref: "hash://phase14/debug",
      capture_level: :debug_redacted,
      raw_material_present?: false
    }
  end
end
