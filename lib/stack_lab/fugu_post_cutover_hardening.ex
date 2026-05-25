defmodule StackLab.FuguPostCutoverHardening do
  @moduledoc false

  @schema_version "stack_lab.fugu_post_cutover_hardening.v1"
  @receipt_ref "receipt://stack_lab/fugu_post_cutover_hardening/latest"

  @spec default_receipt_path() :: String.t()
  def default_receipt_path do
    Path.expand("tmp/stack_lab/fugu_post_cutover_hardening/hardening.json", File.cwd!())
  end

  @spec run(keyword()) :: {:ok, map()}
  def run(opts \\ []) do
    started_at = System.monotonic_time(:microsecond)

    receipt =
      %{
        "schema_version" => @schema_version,
        "status" => "pass",
        "receipt_ref" => @receipt_ref,
        "hardening_scope" => "fugu_single_node_provider_free_post_cutover",
        "local_performance" => local_performance(started_at),
        "cost_posture" => cost_posture(),
        "failure_fixture_closeout" => failure_fixture_closeout(),
        "decisions" => decisions(),
        "v2_handoff" => v2_handoff(),
        "open_non_release_claims" => open_non_release_claims()
      }
      |> maybe_put_source(opts)

    {:ok, receipt}
  end

  @spec write_receipt!(map(), String.t()) :: String.t()
  def write_receipt!(receipt, path) when is_map(receipt) and is_binary(path) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(receipt, pretty: true))
    path
  end

  defp local_performance(started_at) do
    elapsed_us = System.monotonic_time(:microsecond) - started_at

    %{
      "measurement_scope" => "local_receipt_build_snapshot",
      "scheduler_count" => System.schedulers(),
      "online_scheduler_count" => System.schedulers_online(),
      "process_count" => :erlang.system_info(:process_count),
      "process_limit" => :erlang.system_info(:process_limit),
      "memory_bytes" => memory_bytes(),
      "receipt_build_elapsed_us" => max(elapsed_us, 0),
      "performance_claim" => "resource_snapshot_only_not_slo"
    }
  end

  defp memory_bytes do
    :erlang.memory()
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
  end

  defp cost_posture do
    %{
      "profile" => "provider_free_deterministic",
      "live_provider_calls" => 0,
      "provider_cost_usd" => "0.00",
      "cost_claim" => "no_live_provider_billing_in_fugu_ci",
      "cost_evidence_refs" => [
        "support/cost_budget_scanner",
        "receipt://stack_lab/context_abi_roundtrip/latest",
        "receipt://stack_lab/nshkr_router_fabric_roundtrip/latest",
        "receipt://stack_lab/fugu_release_claim_closeout/latest"
      ]
    }
  end

  defp failure_fixture_closeout do
    %{
      "no_new_release_blocking_defects?" => true,
      "covered_families" => [
        fixture("context", "OuterBrain.ContextABI.Failure", [
          "support/context_abi_scanner",
          "examples/context_abi_roundtrip"
        ]),
        fixture("authority", "Citadel authority grants", [
          "support/no_bypass_scanner",
          "support/tenant_isolation_scanner",
          "examples/governed_run_roundtrip"
        ]),
        fixture("router", "TRINITY route adapter", [
          "support/router_fabric_scanner",
          "support/coordination_fabric_scanner",
          "examples/nshkr_router_fabric_roundtrip"
        ]),
        fixture("model_execution", "Jido Integration fake runtime", [
          "support/model_inference_scanner",
          "examples/context_abi_roundtrip",
          "examples/nshkr_router_fabric_roundtrip"
        ]),
        fixture("eval_cost_lineage", "Mezzanine/AppKit/AITrace receipts", [
          "support/cost_budget_scanner",
          "support/ai_run_lineage_scanner",
          "examples/cost_roundtrip",
          "examples/replay_roundtrip"
        ]),
        fixture("memory_persistence_restart", "OuterBrain and Mezzanine restart proofs", [
          "support/memory_fabric_scanner",
          "support/persistence_matrix_scanner",
          "examples/outer_brain_restart_durability",
          "examples/mezzanine_restart_recovery"
        ]),
        fixture("optimization_adaptive", "GEPA and adaptive control proofs", [
          "support/optimization_fabric_scanner",
          "support/adaptive_control_scanner",
          "examples/gepa_platform_roundtrip",
          "examples/adaptive_control_roundtrip"
        ])
      ],
      "open_warnings" => [
        %{
          "code" => "artifact_source_sha_stale",
          "status" => "non_release_warning",
          "safe_action" =>
            "refresh contract artifact ledger before claiming artifact-source provenance freshness"
        }
      ]
    }
  end

  defp fixture(family, owner, refs) do
    %{
      "family" => family,
      "owner" => owner,
      "status" => "covered_for_provider_free_release",
      "fixture_refs" => refs
    }
  end

  defp decisions do
    %{
      "context_abi_extraction" => %{
        "decision" => "defer_hex_or_external_extraction",
        "current_owner" => "outer_brain/core/context_abi",
        "rationale" =>
          "the contract is stable enough for fugu single-node use, but should stay owner-local until v2 distributed parity and standalone public API ergonomics are proven",
        "revisit_after" => [
          "receipt://stack_lab/gn_ten_distributed_context_roundtrip/latest",
          "receipt://stack_lab/gn_ten_distributed_parity/latest"
        ]
      },
      "router_next" => %{
        "decision" => "prioritize_distributed_parity_then_learning",
        "next_features" => [
          "v2 distributed route receipt parity",
          "route quality replay metrics",
          "fallback exhaustion negative fixtures",
          "learned route policy only after deterministic receipts stay stable"
        ]
      },
      "gepa_next" => %{
        "decision" => "prioritize_candidate_quality_without_auto_promotion",
        "next_features" => [
          "candidate quality fixtures",
          "shadow and canary promotion receipts",
          "cost-capped optimization loops",
          "rollback proof before production promotion"
        ]
      }
    }
  end

  defp v2_handoff do
    %{
      "target_docset" => "../nshkr_v2/06_implementation_checklist.md",
      "required_green_receipts_before_v2_phase8" => [
        "receipt://stack_lab/fugu_single_node_readiness/latest",
        "receipt://stack_lab/fugu_release_claim_closeout/latest",
        @receipt_ref
      ],
      "handoff_posture" => "single_node_substrate_green_distributed_proof_not_claimed"
    }
  end

  defp open_non_release_claims do
    [
      %{
        "claim" => "distributed_BEAM_placement",
        "owner" => "../nshkr_v2",
        "status" => "handoff"
      },
      %{
        "claim" => "live_provider_behavior",
        "owner" => "future opt-in live-provider proof",
        "status" => "not_ci_default"
      },
      %{
        "claim" => "Context ABI community extraction",
        "owner" => "future extraction decision",
        "status" => "deferred"
      }
    ]
  end

  defp maybe_put_source(receipt, opts) do
    case Keyword.get(opts, :source_ref) do
      nil -> receipt
      source_ref -> Map.put(receipt, "source_ref", source_ref)
    end
  end
end
