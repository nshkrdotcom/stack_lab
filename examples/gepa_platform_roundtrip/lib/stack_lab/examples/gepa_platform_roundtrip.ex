defmodule StackLab.Examples.GEPAPlatformRoundtrip.Receipt do
  @moduledoc "Deterministic GEPA platform roundtrip receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_refs,
    :status,
    :provider_dependency?,
    :model_inference_scan,
    :optimization_fabric_scan,
    :ai_run_lineage_scan,
    :framework_projection,
    :candidate_receipt,
    :appkit_projection,
    :promotion_ref,
    :rollback_ref,
    :trace_refs
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.GEPAPlatformRoundtrip do
  @moduledoc """
  Deterministic governed GEPA platform roundtrip proof.
  """

  alias AppKit.OptimizationSurface
  alias GEPAFramework.Runtime
  alias Mezzanine.AIExecution.RuntimeDeps
  alias Mezzanine.OptimizationEngine
  alias StackLab.AIRunLineageScanner
  alias StackLab.Examples.GEPAPlatformRoundtrip.Receipt
  alias StackLab.ModelInferenceScanner
  alias StackLab.OptimizationFabricScanner

  @fixture_refs ["AOC-018", "AOC-019", "AOC-038", "AOC-041", "AOC-042"]

  @spec run() :: {:ok, Receipt.t()} | {:error, term()}
  def run do
    with {:ok, framework_result} <- Runtime.run(framework_config(), examples: example_refs()),
         {:ok, [candidate_receipt]} <-
           OptimizationEngine.propose_candidates(optimization_spec(), runtime_deps(),
             examples: example_refs()
           ),
         {:ok, appkit_projection} <-
           OptimizationSurface.candidate_projection(
             appkit_candidate_projection(candidate_receipt)
           ),
         {:ok, model_scan} <- ModelInferenceScanner.scan(model_scan_input()),
         {:ok, fabric_scan} <- OptimizationFabricScanner.scan(fabric_scan_input()),
         {:ok, lineage_scan} <- AIRunLineageScanner.scan(lineage_scan_input()) do
      {:ok,
       %Receipt{
         receipt_ref: "gepa-platform-roundtrip://phase-8/mock",
         fixture_refs: @fixture_refs,
         status: status([model_scan, fabric_scan, lineage_scan]),
         provider_dependency?: framework_result.provider_dependency?,
         model_inference_scan: model_scan,
         optimization_fabric_scan: fabric_scan,
         ai_run_lineage_scan: lineage_scan,
         framework_projection: framework_projection(framework_result),
         candidate_receipt: candidate_receipt,
         appkit_projection: appkit_projection,
         promotion_ref: "promotion://gepa/candidate",
         rollback_ref: "rollback://gepa/candidate",
         trace_refs: ["trace://gepa/roundtrip", "trace://candidate/eval"]
       }}
    end
  end

  defp runtime_deps do
    %RuntimeDeps{optimizer_adapter: GEPA.MezzanineOptimizerAdapter}
  end

  defp example_refs, do: ["example://gepa/phase-13/1", "example://gepa/phase-13/2"]

  defp framework_config do
    %{
      runtime_ref: "run:gepa:phase13",
      task: %{
        task_ref: "target://gepa/role-worker",
        dataset_ref: "dataset://gepa/phase-13"
      },
      components: [
        %{
          component_ref: "component:gepa:mezzanine:1",
          kind: :component,
          content_ref: "prompt-artifact://gepa/instruction/v1"
        }
      ],
      evaluator: %{
        evaluator_ref: "eval-suite://gepa/phase-13",
        objective_refs: ["eval-suite://gepa/phase-13"]
      },
      proposer: %{
        proposer_ref: "proposer:gepa:mezzanine",
        strategy: :deterministic_reflection
      },
      merge: %{
        merge_ref: "merge:gepa:disabled",
        strategy: :disabled
      },
      tracing: %{trace_refs: ["trace://gepa/roundtrip"]},
      persistence: %{profile: :memory_ephemeral}
    }
  end

  defp optimization_spec do
    %{
      run_ref: "optimization-run://gepa/phase-13",
      tenant_ref: "tenant://phase-13",
      authority_ref: "authority://citadel/optimization/promotion",
      target_ref: "target://gepa/role-worker",
      framework_run_ref: "run:gepa:phase13",
      checkpoint_ref: "checkpoint://gepa/memory",
      budget_ref: "budget://optimization",
      eval_suite_ref: "eval-suite://gepa/phase-13",
      replay_bundle_ref: "replay-bundle://gepa/phase-13",
      trace_ref: "trace://gepa/roundtrip",
      memory_ref_set: ["memory://gepa/promoted/context"],
      prompt_ref_set: ["prompt-artifact://gepa/instruction/v1"],
      context_budget_ref: "context-packet://gepa/phase-13",
      guardrail_ref_set: ["guardrail://gepa/input", "guardrail://gepa/output"],
      cost_budget_ref_set: ["cost://optimization"],
      drift_ref_set: ["drift://gepa/window"],
      persistence_ref_set: ["persistence://gepa/memory-ephemeral"],
      promotion_ref_set: ["promotion://gepa/candidate"],
      rollback_ref_set: ["rollback://gepa/candidate"]
    }
  end

  defp framework_projection(framework_result) do
    %{
      task_ref: "target://gepa/role-worker",
      run_ref: framework_result.run_ref,
      candidate_refs: framework_result.candidate_refs,
      best_candidate_ref: framework_result.best_candidate_ref,
      checkpoint: GEPAFramework.Persistence.to_projection(framework_result.checkpoint),
      trace_refs: framework_result.trace_refs
    }
  end

  defp appkit_candidate_projection(candidate_receipt) do
    %{
      candidate_ref: candidate_receipt.candidate_ref,
      run_ref: candidate_receipt.gepa_run_ref,
      lineage_refs: candidate_receipt.lineage_refs,
      score_refs: [candidate_receipt.objective_score_ref],
      eval_refs: candidate_receipt.eval_refs,
      replay_refs: ["replay-bundle://gepa/phase-13"],
      budget_refs: ["budget://optimization"],
      trace_refs: [candidate_receipt.trace_ref],
      promotion_refs: candidate_receipt.promotion_refs,
      rollback_refs: candidate_receipt.rollback_refs
    }
  end

  defp model_scan_input do
    %{
      owner_repo: "jido_integration",
      package_path: "core/model_provider_registry",
      runtime_facts: [
        %{
          model_profile_ref: "model-profile://mock/proposer",
          endpoint_profile_ref: "endpoint-profile://mock/proposer",
          endpoint_identity_ref: "endpoint-identity://mock/proposer",
          provider_credential_ref: "provider-credential://mock/profile",
          operation_policy_ref: "policy://operation/propose"
        }
      ],
      source_units: []
    }
  end

  defp fabric_scan_input do
    %{
      owner_repo: "mezzanine",
      package_path: "core/optimization_engine",
      optimization_facts: [
        %{
          candidate_lineage_refs: ["lineage://gepa/candidate"],
          context_packet_refs: ["context-packet://gepa/phase-13"],
          route_decision_refs: ["target://gepa/role-worker"],
          eval_dataset_refs: ["eval-suite://gepa/phase-13"],
          proposer_model_ref: "model-profile://mock/proposer",
          promotion_gate_refs: [
            "gate://eval",
            "gate://replay",
            "gate://guardrail",
            "gate://cost",
            "gate://shadow",
            "gate://canary",
            "gate://human-approval"
          ],
          citadel_authority_refs: ["authority://citadel/optimization/promotion"],
          appkit_projection_refs: ["appkit://optimization/candidate"],
          budget_refs: ["budget://optimization"],
          cost_refs: ["cost://optimization"],
          trace_refs: ["trace://candidate/eval"],
          trace_redaction: :redacted,
          promotion_refs: ["promotion://gepa/candidate"],
          rollback_refs: ["rollback://gepa/candidate"],
          provenance_refs: ["provenance://gepa/candidate"]
        }
      ]
    }
  end

  defp lineage_scan_input do
    %{
      owner_repo: "mezzanine",
      package_path: "core/ai_run_model",
      run_facts: [
        %{
          ai_run_ref: "ai-run://gepa/phase-8/child",
          tenant_ref: "tenant://phase-8",
          authority_ref: "authority://optimization",
          parent_run_ref: "ai-run://gepa/phase-8/root",
          idempotency_ref: "idempotency://gepa/phase-8/child",
          persistence_profile_ref: "persistence://memory-minimal",
          optimization_refs: ["optimization-run://gepa/phase-8"],
          trace_refs: ["trace://gepa/roundtrip"]
        }
      ]
    }
  end

  defp status(receipts) do
    if Enum.all?(receipts, &(&1.status == :pass)), do: :pass, else: :open_defect
  end
end
