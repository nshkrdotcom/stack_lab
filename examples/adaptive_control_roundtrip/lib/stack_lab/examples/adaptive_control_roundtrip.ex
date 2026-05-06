defmodule StackLab.Examples.AdaptiveControlRoundtrip.Receipt do
  @moduledoc "Deterministic adaptive-control roundtrip receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_refs,
    :status,
    :provider_dependency?,
    :adaptive_control_scan,
    :live_provider_gate_ref,
    :openapi_operation_ref,
    :graphql_operation_ref,
    :persistence_profile_ref,
    :debug_sidecar_ref,
    :appkit_projection,
    :trace_dataset_ref,
    :eval_dataset_refs,
    :replay_dataset_refs,
    :gepa_target_refs,
    :candidate_ref,
    :shadow_ref,
    :canary_ref,
    :approval_ref,
    :promotion_ref,
    :rollback_ref,
    :stale_artifact_rejection_refs,
    :trace_refs
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.AdaptiveControlRoundtrip do
  @moduledoc """
  Deterministic closed-loop adaptive-control proof.
  """

  alias AppKit.AdaptiveControlSurface
  alias StackLab.AdaptiveControlScanner
  alias StackLab.Examples.AdaptiveControlRoundtrip.Receipt

  @fixture_refs [
    "AOC-037",
    "AOC-040",
    "AOC-045",
    "AOC-046",
    "AOC-047",
    "PERSIST-AOC-006",
    "PERSIST-AOC-007"
  ]

  @spec run() :: {:ok, Receipt.t()} | {:error, term()}
  def run do
    with {:ok, appkit_projection} <- AdaptiveControlSurface.operator_projection(appkit_attrs()),
         {:ok, scan} <- AdaptiveControlScanner.scan(scanner_input()) do
      {:ok,
       %Receipt{
         receipt_ref: "adaptive-control-roundtrip://phase-13/mock",
         fixture_refs: @fixture_refs,
         status: status([scan]),
         provider_dependency?: false,
         adaptive_control_scan: scan,
         live_provider_gate_ref: "live-provider-gate://phase14/openai",
         openapi_operation_ref: "pristine-operation://github/issues/list",
         graphql_operation_ref: "prismatic-operation://linear/viewer",
         persistence_profile_ref: "persistence-profile://phase14/integration-postgres",
         debug_sidecar_ref: "debug-sidecar://phase14/redacted",
         appkit_projection: appkit_projection,
         trace_dataset_ref: "trace-dataset://trinity/repair",
         eval_dataset_refs: ["eval-dataset://trinity/repair"],
         replay_dataset_refs: ["replay-dataset://trinity/repair"],
         gepa_target_refs: ["gepa-target://role-prompt"],
         candidate_ref: "candidate://role-worker/v2",
         shadow_ref: "shadow://candidate/worker/v2",
         canary_ref: "canary://candidate/worker/v2",
         approval_ref: "approval://operator/worker/v2",
         promotion_ref: "promotion://candidate/worker/v2",
         rollback_ref: "rollback://candidate/worker/v1",
         stale_artifact_rejection_refs: ["stale-rejection://candidate/worker/v1"],
         trace_refs: ["trace://trinity/repair", "trace://adaptive-control/worker"]
       }}
    end
  end

  defp appkit_attrs do
    %{
      control_run_ref: "adaptive-control://phase-13/worker",
      tenant_ref: "tenant://adaptive",
      authority_ref: "authority://adaptive-control",
      actor_ref: "operator://adaptive",
      shadow_comparison_ref: "shadow://candidate/worker/v2",
      canary_state_ref: "canary://candidate/worker/v2",
      threshold_status_refs: [
        "threshold://improvement/pass",
        "threshold://regression/pass",
        "threshold://budget/pass",
        "threshold://approval/operator"
      ],
      budget_impact_ref: "budget-impact://candidate/worker/v2",
      approval_decision_ref: "approval://operator/worker/v2",
      promotion_readiness_ref: "promotion-readiness://candidate/worker/v2",
      rollback_ref: "rollback://candidate/worker/v1",
      artifact_lock_refs: ["artifact-lock://role-worker"],
      stale_artifact_rejection_refs: ["stale-rejection://candidate/worker/v1"],
      audit_refs: ["audit://adaptive-control/worker"],
      trace_refs: ["trace://adaptive-control/worker"]
    }
  end

  defp scanner_input do
    %{
      owner_repo: "mezzanine",
      package_path: "core/adaptive_control_engine",
      adaptive_control_facts: [
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
      ],
      provider_adapter_facts: [
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
      ],
      persistence_facts: [
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
      ],
      debug_sidecar_facts: [
        %{
          debug_tap_ref: "debug-tap://tenant-1/redacted",
          trace_ref: "trace://phase14/debug",
          summary_ref: "summary://phase14/debug",
          state_ref: "state://phase14/debug",
          payload_hash_ref: "hash://phase14/debug",
          capture_level: :debug_redacted,
          raw_material_present?: false
        }
      ]
    }
  end

  defp status(receipts) do
    if Enum.all?(receipts, &(&1.status == :pass)), do: :pass, else: :open_defect
  end
end
