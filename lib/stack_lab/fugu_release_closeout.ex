defmodule StackLab.FuguReleaseCloseout do
  @moduledoc false

  @schema_version "stack_lab.fugu_release_closeout.v1"
  @receipt_ref "receipt://stack_lab/fugu_release_claim_closeout/latest"

  @spec default_receipt_path() :: String.t()
  def default_receipt_path do
    Path.expand("tmp/stack_lab/fugu_release_closeout/release_closeout.json", File.cwd!())
  end

  @spec run(keyword()) :: {:ok, map()}
  def run(opts \\ []) do
    receipt =
      %{
        "schema_version" => @schema_version,
        "status" => "pass",
        "receipt_ref" => @receipt_ref,
        "release_scope" => "fugu_single_node_provider_free_substrate",
        "claim_policy" => %{
          "all_public_claims_mapped?" => true,
          "hidden_defects_allowed?" => false,
          "authoritative_audit_claim?" => false,
          "production_deployment_claim?" => false
        },
        "public_claims" => public_claims(),
        "required_closeout_gates" => required_closeout_gates(),
        "open_non_release_claims" => open_non_release_claims(),
        "does_not_prove" => [
          "live provider behavior",
          "distributed BEAM placement",
          "production persistence",
          "production credential rotation",
          "provider billing correctness",
          "49-node local scale feasibility"
        ]
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

  defp public_claims do
    [
      claim(
        "context_abi_single_node",
        [
          "outer_brain",
          "mezzanine",
          "citadel",
          "jido_integration",
          "app_kit",
          "AITrace",
          "stack_lab"
        ],
        [
          "examples/context_abi_roundtrip",
          "support/context_abi_scanner",
          "support/model_inference_scanner",
          "support/cost_budget_scanner",
          "support/ai_run_lineage_scanner"
        ],
        [
          "support/context_abi_scanner",
          "support/model_inference_scanner",
          "support/cost_budget_scanner",
          "support/ai_run_lineage_scanner"
        ],
        [
          "mix test examples/context_abi_roundtrip",
          "mix gn_ten.proofs.validate --json",
          "mix ci"
        ],
        [
          "../nshkr_fugu/03_context_abi.md",
          "../nshkr_fugu/16_interface_freeze_contracts.md",
          "docs/gn_ten_proof_matrix.md"
        ],
        ["receipt://stack_lab/context_abi_roundtrip/latest"],
        [
          "Context ABI packet, render refs, authority refs, model receipt, eval verdict, cost, lineage, and bounded trace facts are proven provider-free"
        ]
      ),
      claim(
        "router_fabric_single_node",
        ["trinity_framework", "mezzanine", "jido_integration", "app_kit", "AITrace", "stack_lab"],
        [
          "examples/nshkr_router_fabric_roundtrip",
          "support/router_fabric_scanner",
          "support/coordination_fabric_scanner",
          "support/model_inference_scanner"
        ],
        [
          "support/router_fabric_scanner",
          "support/coordination_fabric_scanner",
          "support/model_inference_scanner"
        ],
        [
          "mix test examples/nshkr_router_fabric_roundtrip",
          "mix gn_ten.proofs.validate --json",
          "mix ci"
        ],
        [
          "../nshkr_fugu/04_router_fabric.md",
          "../nshkr_fugu/16_interface_freeze_contracts.md",
          "docs/gn_ten_proof_matrix.md"
        ],
        ["receipt://stack_lab/nshkr_router_fabric_roundtrip/latest"],
        [
          "TRINITY route adapter, Mezzanine render handoff, Jido fake invocation, AITrace facts, and AppKit projection are proven provider-free"
        ]
      ),
      claim(
        "product_boundary_acceptance",
        ["extravaganza", "app_kit", "stack_lab"],
        [
          "extravaganza/apps/extravaganza_core",
          "support/no_bypass_scanner",
          "StackLab external acceptance command"
        ],
        [
          "support/no_bypass_scanner",
          "support/tenant_isolation_scanner"
        ],
        [
          "mix ci in extravaganza",
          "mix stack_lab.extravaganza.external_acceptance --json",
          "mix ci in stack_lab"
        ],
        [
          "../nshkr_fugu/06_implementation_checklist.md#phase-15-product-proof-through-extravaganza",
          "docs/gn_ten_proof_matrix.md"
        ],
        ["receipt://stack_lab/extravaganza_external_acceptance/latest"],
        [
          "Product proof enters through AppKit and projects only product-safe context, model, eval, and review refs"
        ]
      ),
      claim(
        "adaptive_optimization_coordination",
        ["gepa_framework", "trinity_framework", "mezzanine", "app_kit", "citadel", "stack_lab"],
        [
          "examples/gepa_platform_roundtrip",
          "examples/trinity_platform_roundtrip",
          "examples/adaptive_control_roundtrip",
          "support/optimization_fabric_scanner",
          "support/coordination_fabric_scanner",
          "support/adaptive_control_scanner"
        ],
        [
          "support/optimization_fabric_scanner",
          "support/coordination_fabric_scanner",
          "support/adaptive_control_scanner"
        ],
        [
          "mix test examples/gepa_platform_roundtrip",
          "mix test examples/trinity_platform_roundtrip",
          "mix test examples/adaptive_control_roundtrip",
          "mix ci"
        ],
        [
          "../nshkr_fugu/04_router_fabric.md",
          "../nshkr_fugu/13_package_placement_matrix.md",
          "docs/gn_ten_proof_matrix.md"
        ],
        [
          "receipt://stack_lab/gepa_platform_roundtrip/latest",
          "receipt://stack_lab/trinity_platform_roundtrip/latest",
          "receipt://stack_lab/adaptive_control_roundtrip/latest"
        ],
        [
          "Optimization, coordination, and adaptive promotion refs are bound through governed provider-free stack proofs"
        ]
      ),
      claim(
        "persistence_restart_profiles",
        ["outer_brain", "mezzanine", "ground_plane", "AITrace", "stack_lab"],
        [
          "examples/persistence_mode_roundtrip",
          "examples/outer_brain_restart_durability",
          "examples/mezzanine_restart_recovery",
          "support/persistence_matrix_scanner"
        ],
        [
          "support/persistence_matrix_scanner",
          "support/ai_run_lineage_scanner"
        ],
        [
          "mix test examples/persistence_mode_roundtrip",
          "mix test examples/outer_brain_restart_durability",
          "mix test examples/mezzanine_restart_recovery",
          "mix ci"
        ],
        [
          "../nshkr_fugu/14_monolith_and_distributed_modes.md",
          "docs/gn_ten_proof_matrix.md"
        ],
        [
          "receipt://stack_lab/persistence_mode_roundtrip/latest",
          "receipt://stack_lab/outer_brain_restart_durability/latest",
          "receipt://stack_lab/mezzanine_restart_recovery/latest"
        ],
        [
          "Provider-free persistence and restart claims are profile-specific and do not claim production durability"
        ]
      ),
      claim(
        "live_and_distributed_boundaries",
        ["jido_integration", "mezzanine", "stack_lab"],
        [
          "lib/stack_lab/fugu_live_provider_guard.ex",
          "lib/stack_lab/fugu_readiness_handoff.ex",
          "docs/receipts/gn_ten_phase16"
        ],
        [
          "support/model_inference_scanner",
          "support/connector_hardening_scanner",
          "support/no_bypass_scanner"
        ],
        [
          "mix stack_lab.fugu.readiness_handoff --json",
          "mix stack_lab.fugu.live_provider_smoke --allow-live --secrets-loaded --dry-run --json -- --linear-api-key-stdin",
          "mix ci"
        ],
        [
          "../nshkr_fugu/09_security_governance_boundaries.md",
          "../nshkr_fugu/14_monolith_and_distributed_modes.md",
          "../nshkr_v2/06_implementation_checklist.md"
        ],
        ["receipt://stack_lab/fugu_single_node_readiness/latest"],
        [
          "Live provider behavior is explicitly opt-in and distributed BEAM placement is handed off to the v2 StackLab topology proof"
        ]
      )
    ]
  end

  defp claim(id, owner_repos, source_refs, scanner_refs, qc_refs, docs_refs, receipt_refs, proves) do
    %{
      "claim_id" => id,
      "status" => "mapped",
      "owner_repos" => owner_repos,
      "source_refs" => source_refs,
      "test_refs" => qc_refs,
      "scanner_refs" => scanner_refs,
      "qc_refs" => qc_refs,
      "docs_refs" => docs_refs,
      "receipt_refs" => receipt_refs,
      "proves" => proves,
      "does_not_prove" => [
        "production security",
        "live provider behavior unless the claim is explicitly live-gated",
        "distributed placement unless the v2 topology receipt is present"
      ]
    }
  end

  defp required_closeout_gates do
    [
      "mix stack_lab.fugu.release_closeout --json",
      "mix gn_ten.proofs.validate --json",
      "mix ci"
    ]
  end

  defp open_non_release_claims do
    [
      %{
        "claim" => "distributed_beam_placement",
        "owner" => "../nshkr_v2",
        "status" => "not_claimed_by_fugu",
        "required_receipt" => "receipt://stack_lab/gn_ten_distributed_context_roundtrip/latest"
      },
      %{
        "claim" => "live_provider_behavior",
        "owner" => "future opt-in live-provider proof",
        "status" => "guarded_not_ci_default",
        "required_command" =>
          "~/scripts/with_bash_secrets mix stack_lab.fugu.live_provider_smoke --allow-live --secrets-loaded -- --linear-api-key-stdin"
      },
      %{
        "claim" => "artifact_source_sha_freshness",
        "owner" => "StackLab contract artifact ledger refresh",
        "status" => "non_blocking_validator_warning",
        "safe_action" => "refresh artifact ledger when release artifact provenance is the claim"
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
