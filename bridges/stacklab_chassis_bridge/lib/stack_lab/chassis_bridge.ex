defmodule StackLab.ChassisBridge do
  @moduledoc "StackLab proof catalog bridge for Chassis."

  alias Chassis.Evolution.Conformance.Evidence, as: EvolutionEvidence
  alias Chassis.ModelAsset.Conformance.Evidence, as: ModelAssetEvidence
  alias Chassis.StackLab.Bridge.RunConformance

  @spec run(atom() | String.t()) :: {:ok, map()} | {:error, term()}
  def run(tag) when tag in ["chassis", :chassis] do
    RunConformance.run(tag: :chassis)
  end

  def run(tag) when tag in ["chassis_evolution", :chassis_evolution],
    do: Chassis.Evolution.Conformance.stacklab_report()

  def run(tag) when tag in ["chassis_model_asset", :chassis_model_asset],
    do: Chassis.ModelAsset.Conformance.stacklab_report()

  def run(tag) when tag in ["chassis_single_node_monolith", :chassis_single_node_monolith],
    do: StackLab.ChassisSingleNodeMonolithDeployReceipt.run()

  def run(tag), do: {:error, {:unknown_tag, tag}}

  @spec jsonable_report(map()) :: map()
  def jsonable_report(%{tag: :chassis_evolution} = report), do: EvolutionEvidence.jsonable(report)

  def jsonable_report(%{tag: :chassis_model_asset} = report),
    do: ModelAssetEvidence.jsonable(report)

  def jsonable_report(
        %{schema_version: "stack_lab.chassis_single_node_monolith_deploy_receipt.v1"} = receipt
      ),
      do: StackLab.ChassisSingleNodeMonolithDeployReceipt.jsonable(receipt)

  def jsonable_report(report), do: RunConformance.jsonable_report(report)
end
