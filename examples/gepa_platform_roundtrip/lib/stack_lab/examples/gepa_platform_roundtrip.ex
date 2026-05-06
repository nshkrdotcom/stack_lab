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

  alias StackLab.AIRunLineageScanner
  alias StackLab.Examples.GEPAPlatformRoundtrip.Receipt
  alias StackLab.ModelInferenceScanner
  alias StackLab.OptimizationFabricScanner

  @fixture_refs ["AOC-018", "AOC-019", "AOC-038", "AOC-041", "AOC-042"]

  @spec run() :: {:ok, Receipt.t()} | {:error, term()}
  def run do
    with {:ok, buildout_result} <- GEPABuildout.run_domain_task(buildout_input()),
         {:ok, model_scan} <- ModelInferenceScanner.scan(model_scan_input()),
         {:ok, fabric_scan} <- OptimizationFabricScanner.scan(fabric_scan_input()),
         {:ok, lineage_scan} <- AIRunLineageScanner.scan(lineage_scan_input()) do
      {:ok,
       %Receipt{
         receipt_ref: "gepa-platform-roundtrip://phase-8/mock",
         fixture_refs: @fixture_refs,
         status: status([model_scan, fabric_scan, lineage_scan]),
         provider_dependency?: buildout_result.framework_result.provider_dependency?,
         model_inference_scan: model_scan,
         optimization_fabric_scan: fabric_scan,
         ai_run_lineage_scan: lineage_scan,
         framework_projection: buildout_result.projection,
         promotion_ref: "promotion://gepa/candidate",
         rollback_ref: "rollback://gepa/candidate",
         trace_refs: ["trace://gepa/roundtrip", "trace://candidate/eval"]
       }}
    end
  end

  defp buildout_input do
    %{
      task_ref: "task:gepa:phase-8",
      dataset_ref: "dataset://gepa/phase-8",
      example_refs: ["example://gepa/phase-8/1", "example://gepa/phase-8/2"],
      trace_ref: "trace://gepa/roundtrip"
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
          eval_dataset_refs: ["dataset://gepa/phase-8"],
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
          budget_refs: ["budget://optimization"],
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
