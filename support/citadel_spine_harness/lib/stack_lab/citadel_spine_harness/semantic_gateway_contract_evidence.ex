defmodule StackLab.CitadelSpineHarness.SemanticGatewayContractEvidence do
  @moduledoc false

  alias OuterBrain.Contracts.SemanticGatewayContract
  alias StackLab.CitadelSpineHarness.OuterBrainDurability

  @spec run_case(:semantic_gateway_owner_evidence) :: {:ok, map()}
  def run_case(:semantic_gateway_owner_evidence) do
    contract = SemanticGatewayContract.contract()

    {:ok, positive} = SemanticGatewayContract.owner_evidence(SemanticGatewayContract.fixture())

    {:ok, real_restart} =
      OuterBrainDurability.run_case(:duplicate_publication_suppressed_after_restart)

    {:ok,
     %{
       case: :semantic_gateway_owner_evidence,
       contract: contract,
       stack_lab_role: :evidence_composer_not_owner,
       service_mode_gate: %{
         outer_brain_owner_contract_consumed?: positive.contract_id == contract.id,
         real_outer_brain_restart_durability_consumed?: real_restart.case != nil,
         lower_runtime_only_rejected?:
           :lower_runtime_only_proof_without_outer_brain_owner_evidence in contract.forbidden,
         raw_payload_absent?: not positive.raw_payload_included?
       },
       positive: positive,
       real_restart: real_restart,
       negative_failures: negative_failures()
     }}
  end

  defp negative_failures do
    {:error, missing_semantic_provenance} =
      SemanticGatewayContract.fixture()
      |> Map.delete(:semantic_context_provenance)
      |> SemanticGatewayContract.owner_evidence()

    {:error, raw_payload} =
      SemanticGatewayContract.fixture()
      |> Map.put(:raw_provider_body, %{"text" => "raw provider body"})
      |> SemanticGatewayContract.owner_evidence()

    {:error, lower_runtime_only} =
      SemanticGatewayContract.fixture()
      |> Map.put(:real_outer_brain_surface?, false)
      |> Map.put(:lower_runtime_only_proof?, true)
      |> SemanticGatewayContract.owner_evidence()

    %{
      missing_semantic_provenance: missing_semantic_provenance,
      raw_payload: raw_payload,
      lower_runtime_only: lower_runtime_only
    }
  end
end
