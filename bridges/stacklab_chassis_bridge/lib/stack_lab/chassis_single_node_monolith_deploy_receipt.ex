defmodule StackLab.ChassisSingleNodeMonolithDeployReceipt do
  @moduledoc """
  Links the Chassis local monolith deployment proof to product proof refs.

  This module intentionally consumes the existing Chassis conformance proof
  through `StackLab.ChassisBridge`. StackLab records the cross-proof linkage;
  Chassis remains the owner of deployment transaction behavior.
  """

  @schema_version "stack_lab.chassis_single_node_monolith_deploy_receipt.v1"
  @chassis_proof "chassis.deployment.profile_monolith_local"

  @spec run(keyword()) :: {:ok, map()} | {:error, map()}
  def run(opts \\ []) do
    bridge_run = Keyword.get(opts, :chassis_bridge_run, &StackLab.ChassisBridge.run/1)

    with {:ok, chassis_report} <- bridge_run.(:chassis),
         {:ok, proof} <- select_monolith_proof(chassis_report),
         :ok <- validate_monolith_proof(proof) do
      {:ok, receipt(chassis_report, proof)}
    else
      {:error, %{} = reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, error("chassis_single_node_link_failed", reason: inspect(reason))}
    end
  end

  @spec jsonable(map()) :: map()
  def jsonable(receipt) when is_map(receipt), do: stringify(receipt)

  defp select_monolith_proof(%{proofs: proofs}) when is_list(proofs) do
    case Enum.find(proofs, &(Map.get(&1, :name) == @chassis_proof)) do
      nil -> {:error, error("monolith_chassis_proof_missing")}
      proof -> {:ok, proof}
    end
  end

  defp select_monolith_proof(_report), do: {:error, error("chassis_report_invalid")}

  defp validate_monolith_proof(%{status: :pass, evidence: evidence}) do
    cond do
      Map.get(evidence, :profile_ref) != "profile:monolith" ->
        {:error, error("bad_profile_ref", profile_ref: Map.get(evidence, :profile_ref))}

      Map.get(evidence, :node_count) != 1 ->
        {:error, error("bad_node_count", node_count: Map.get(evidence, :node_count))}

      not present?(Map.get(evidence, :receipt_ref)) ->
        {:error, error("missing_deployment_receipt_ref")}

      not present?(Map.get(evidence, :app_ref)) ->
        {:error, error("missing_app_ref")}

      true ->
        :ok
    end
  end

  defp validate_monolith_proof(%{status: status}),
    do: {:error, error("monolith_chassis_proof_not_passed", status: status)}

  defp validate_monolith_proof(_proof), do: {:error, error("monolith_chassis_proof_invalid")}

  defp receipt(chassis_report, proof) do
    evidence = Map.fetch!(proof, :evidence)

    %{
      schema_version: @schema_version,
      status: "pass",
      classification: "local_single_node",
      owner_repo: "stack_lab",
      deployment_profile: "profile:monolith",
      chassis: %{
        tag: Map.get(chassis_report, :tag),
        run_ref: Map.get(chassis_report, :run_ref),
        proof_name: @chassis_proof,
        proof_status: Map.get(proof, :status),
        app_ref: Map.fetch!(evidence, :app_ref),
        deployment_receipt_ref: Map.fetch!(evidence, :receipt_ref),
        node_count: Map.fetch!(evidence, :node_count),
        profile_ref: Map.fetch!(evidence, :profile_ref)
      },
      product_proofs: %{
        extravaganza: %{
          product_repo: "extravaganza",
          proof_ref: "receipt://stack_lab/extravaganza_external_acceptance/latest",
          command: "MIX_ENV=test mix stack_lab.extravaganza.external_acceptance --json"
        },
        synapse_acceptance: %{
          product_repo: "synapse",
          proof_ref: "receipt://stack_lab/synapse_acceptance/latest",
          command: "MIX_ENV=test mix stack_lab.synapse.acceptance --json"
        },
        synapse_staged_live: %{
          product_repo: "synapse",
          proof_ref: "receipt://stack_lab/synapse_staged_live/latest",
          command: "MIX_ENV=test mix stack_lab.synapse.staged_live.v1 --json"
        }
      },
      completed_at: DateTime.utc_now()
    }
  end

  defp error(code, fields \\ []) do
    fields
    |> Map.new()
    |> Map.put(:code, code)
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp stringify(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify(value), do: value
end
