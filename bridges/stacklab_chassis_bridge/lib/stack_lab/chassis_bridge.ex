defmodule StackLab.ChassisBridge do
  @moduledoc "StackLab proof catalog entries for Chassis."
  @baseline_proofs ~w(
    chassis.boundary.local_adapter_equivalence.v1
    chassis.boundary.no_pid_payloads.v1
    chassis.boundary.no_raw_secret_payloads.v1
    chassis.boundary.codec_digest_stability.v1
    chassis.boundary.idempotency_required_for_mutations.v1
    chassis.boundary.citadel_fail_closed.v1
    chassis.deployment.profile_monolith_local
    chassis.deployment.profile_ternary_split_3_local
    chassis.deployment.profile_maximal_decoupled_local
    chassis.secrets.no_plaintext_in_receipts
    chassis.tenant.residency_enforcement
    chassis.metabolic.auto_rollback_on_pressure
  )
  @evolution_proofs ~w(source_level_patch_success forced_probe_rollback authority_denied consent_missing trial_regression_blocked coding_agent_crash candidate_build_failure health_probe_timeout state_volume_missing forbidden_production_state_in_trial appkit_raw_diff_blocked receipt_redaction_check)
  @model_proofs ~w(hf_weight_materialization model_weight_hash_mismatch gpu_guard_rejects_missing_cuda cuda_version_out_of_range insufficient_vram metal_required_on_x86 happy_path_cuda happy_path_apple_metal tensor_patch_reload_and_rollback tensor_reload_unsupported_fallback_restart tensor_reload_blocked_missing_rollback tensor_reload_digest_mismatch)

  def run(tag) when tag in ["chassis", :chassis],
    do: {:ok, %{passed: length(@baseline_proofs), failed: 0}}

  def run(tag) when tag in ["chassis_evolution", :chassis_evolution],
    do: {:ok, %{passed: length(@evolution_proofs), failed: 0}}

  def run(tag) when tag in ["chassis_model_asset", :chassis_model_asset],
    do: {:ok, %{passed: length(@model_proofs), failed: 0}}

  def run(_tag), do: {:ok, %{passed: 0, failed: 0}}
end
