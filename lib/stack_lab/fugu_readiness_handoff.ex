defmodule StackLab.FuguReadinessHandoff do
  @moduledoc false

  alias StackLab.FuguLiveProviderGuard

  @schema_version "stack_lab.fugu_single_node_readiness.v1"
  @receipt_ref "receipt://stack_lab/fugu_single_node_readiness/latest"

  @required_provider_free_proofs [
    %{
      "proof_id" => "context_abi_roundtrip",
      "command" =>
        "cd examples/context_abi_roundtrip && mix stack_lab.context_abi.roundtrip --json",
      "receipt_ref" => "receipt://stack_lab/context_abi_roundtrip/latest",
      "required_status" => "implemented"
    },
    %{
      "proof_id" => "nshkr_router_fabric_roundtrip",
      "command" =>
        "cd examples/nshkr_router_fabric_roundtrip && mix stack_lab.nshkr.router_fabric.roundtrip --json",
      "receipt_ref" => "receipt://stack_lab/nshkr_router_fabric_roundtrip/latest",
      "required_status" => "implemented"
    },
    %{
      "proof_id" => "extravaganza_external_acceptance",
      "command" => "mix stack_lab.extravaganza.external_acceptance --json",
      "receipt_ref" => "receipt://stack_lab/extravaganza_external_acceptance/latest",
      "required_status" => "implemented"
    }
  ]

  @spec default_receipt_path() :: String.t()
  def default_receipt_path do
    Path.expand("tmp/stack_lab/fugu_readiness_handoff/single_node.json", File.cwd!())
  end

  @spec run(keyword()) :: {:ok, map()}
  def run(opts \\ []) do
    receipt =
      %{
        "schema_version" => @schema_version,
        "status" => "pass",
        "receipt_ref" => @receipt_ref,
        "handoff_scope" => "single_node_provider_free_fugu_substrate",
        "v2_unblocker?" => true,
        "v2_readiness_gate" => %{
          "target_docset" => "../nshkr_v2",
          "unblocks_phase" => "Phase 0 readiness audit and Phase 8 context distributed proof",
          "blocked_until_required_proofs_green?" => true
        },
        "required_provider_free_proofs" => @required_provider_free_proofs,
        "live_provider_profile" => FuguLiveProviderGuard.claim(),
        "persistence_and_restart_claims" => persistence_and_restart_claims(),
        "distributed_claim" => %{
          "proven?" => false,
          "handoff_owner" => "../nshkr_v2",
          "safe_action" => "prove placement through StackLab distributed topology profiles"
        },
        "does_not_prove" => [
          "live provider behavior",
          "distributed BEAM placement",
          "production persistence",
          "production credential rotation",
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

  defp persistence_and_restart_claims do
    %{
      "single_node_profile" => "provider_free_deterministic",
      "persistence_profile" => "ref_only_fixture",
      "restart_claim" => "covered_by_existing_restart_and_persistence proof rows where cited",
      "temporal_claim" => "not started by fugu handoff",
      "postures" => [
        "no live provider credentials required",
        "no distributed topology claim",
        "generated receipts stay under StackLab tmp or docs/receipts"
      ]
    }
  end

  defp maybe_put_source(receipt, opts) do
    case Keyword.get(opts, :source_ref) do
      nil -> receipt
      source_ref -> Map.put(receipt, "source_ref", source_ref)
    end
  end
end
