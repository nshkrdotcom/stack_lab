defmodule StackLab.ChassisBridge do
  @moduledoc "StackLab proof catalog bridge for Chassis."

  alias Chassis.Evolution.Conformance.Evidence, as: EvolutionEvidence
  alias Chassis.StackLab.Bridge.RunConformance

  @spec run(atom() | String.t()) :: {:ok, map()} | {:error, term()}
  def run(tag) when tag in ["chassis", :chassis] do
    RunConformance.run(tag: :chassis)
  end

  def run(tag) when tag in ["chassis_evolution", :chassis_evolution],
    do: Chassis.Evolution.Conformance.stacklab_report()

  def run(tag) when tag in ["chassis_model_asset", :chassis_model_asset],
    do: {:error, {:not_implemented, :chassis_model_asset_conformance}}

  def run(tag), do: {:error, {:unknown_tag, tag}}

  @spec jsonable_report(map()) :: map()
  def jsonable_report(%{tag: :chassis_evolution} = report), do: EvolutionEvidence.jsonable(report)

  def jsonable_report(report), do: RunConformance.jsonable_report(report)
end
