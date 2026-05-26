defmodule StackLab.GnTenDistributedHardening do
  @moduledoc false

  alias StackLab.GnTen.ProofMatrix

  @schema_version "stack_lab.gn_ten_distributed_hardening.v1"
  @receipt_ref "receipt://stack_lab/gn_ten_distributed_hardening/latest"

  @distributed_receipt_refs [
    "receipt://stack_lab/gn_ten_distributed_topology_freeze/latest",
    "receipt://stack_lab/gn_ten_node_lab_preflight/latest",
    "receipt://stack_lab/gn_ten_distributed_context_roundtrip/latest",
    "receipt://stack_lab/gn_ten_distributed_router_model_roundtrip/latest",
    "receipt://stack_lab/gn_ten_distributed_partition_recovery/latest",
    "receipt://stack_lab/gn_ten_distributed_parity/latest",
    "receipt://stack_lab/gn_ten_distributed_scale_12/latest",
    "receipt://stack_lab/gn_ten_distributed_release_peer/latest",
    @receipt_ref
  ]

  @spec default_receipt_path() :: String.t()
  def default_receipt_path do
    Path.expand("tmp/stack_lab/gn_ten_distributed_hardening/hardening.json", File.cwd!())
  end

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    started_at = System.monotonic_time(:microsecond)

    with {:ok, proof_report} <- ProofMatrix.validate() do
      receipt =
        %{
          "schema_version" => @schema_version,
          "status" => "pass",
          "receipt_ref" => @receipt_ref,
          "hardening_scope" => "gn_ten_local_distributed_peer_mode",
          "proof_matrix_closeout" => proof_matrix_closeout(proof_report),
          "regression_coverage" => regression_coverage(),
          "extraction_decision" => extraction_decision(),
          "scale_decision" => scale_decision(),
          "remaining_non_release_claims" => remaining_non_release_claims(),
          "local_resource_snapshot" => local_resource_snapshot(started_at)
        }
        |> maybe_put_source(opts)

      {:ok, receipt}
    end
  end

  @spec write_receipt!(map(), String.t()) :: String.t()
  def write_receipt!(receipt, path) when is_map(receipt) and is_binary(path) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(receipt, pretty: true))
    path
  end

  defp proof_matrix_closeout(report) do
    %{
      "proof_count" => report.proof_count,
      "implemented_count" => report.implemented_count,
      "partial_count" => report.partial_count,
      "missing_proof_count" => report.missing_proof_count,
      "open_distributed_defects" => open_distributed_defects(report),
      "required_receipt_refs" => @distributed_receipt_refs,
      "highest_risk_missing_proof" => report.highest_risk_missing_proof
    }
  end

  defp open_distributed_defects(report) do
    report.proofs
    |> Enum.filter(fn proof ->
      String.starts_with?(proof.id, "gn_ten_distributed_") and proof.status != "implemented"
    end)
    |> Enum.map(fn proof ->
      %{
        "id" => proof.id,
        "status" => Atom.to_string(proof.status),
        "next_action" => proof.next_action
      }
    end)
  end

  defp regression_coverage do
    [
      regression("topology_preflight", [
        "receipt://stack_lab/gn_ten_distributed_topology_freeze/latest",
        "receipt://stack_lab/gn_ten_node_lab_preflight/latest"
      ]),
      regression("context_roundtrip", [
        "receipt://stack_lab/gn_ten_distributed_context_roundtrip/latest"
      ]),
      regression("router_model_roundtrip", [
        "receipt://stack_lab/gn_ten_distributed_router_model_roundtrip/latest"
      ]),
      regression("partition_recovery", [
        "receipt://stack_lab/gn_ten_distributed_partition_recovery/latest"
      ]),
      regression("semantic_parity", [
        "receipt://stack_lab/gn_ten_distributed_parity/latest"
      ]),
      regression("scale_12", [
        "receipt://stack_lab/gn_ten_distributed_scale_12/latest"
      ]),
      regression("release_peer", [
        "receipt://stack_lab/gn_ten_distributed_release_peer/latest"
      ])
    ]
  end

  defp regression(family, receipt_refs) do
    %{
      "family" => family,
      "status" => "covered_for_local_peer_mode",
      "receipt_refs" => receipt_refs
    }
  end

  defp extraction_decision do
    %{
      "candidate_repo" => "North-Shore-AI/crucible_cluster",
      "decision" => "defer_extraction",
      "current_owner" => "stack_lab/support/gn_ten_node_lab",
      "rationale" =>
        "the node-lab package is useful but still carries gn-ten topology and proof-matrix vocabulary; extract only after the API is domain-free and reusable outside StackLab",
      "required_before_extraction" => [
        "remove NSHKR, gn-ten, AppKit, Mezzanine, Citadel, Jido, AITrace, GEPA, and TRINITY vocabulary from the public API",
        "standalone tests for :peer, :erpc, :pg, log capture, and local netsplit helpers",
        "documentation that Erlang distribution cookies are local-dev authority only",
        "StackLab continues to own topology specs, proof rows, and distributed platform scenarios"
      ]
    }
  end

  defp scale_decision do
    %{
      "scale_12_status" => "implemented_default",
      "scale_32_status" => "opt_in_heavy",
      "scale_49_status" => "host_feasibility_required",
      "safe_action" =>
        "keep 49-node stress out of root CI until host memory, scheduler, open-file, and cleanup receipts are measured"
    }
  end

  defp remaining_non_release_claims do
    [
      non_claim("full_9_node_lower_lane_runtime", "future Execution Plane lower-lane proof"),
      non_claim("32_node_or_49_node_stress", "future opt-in scale receipt"),
      non_claim("49_node_scale_stress", "future host feasibility receipt"),
      non_claim(
        "production_distribution_security",
        "future non-cookie or TLS distribution topology"
      ),
      non_claim("production_release_packaging", "future owner release strategy"),
      non_claim("live_provider_behavior", "future opt-in live-provider proof"),
      non_claim("public_crucible_cluster_extraction", "future extraction decision")
    ]
  end

  defp non_claim(claim, owner) do
    %{
      "claim" => claim,
      "owner" => owner,
      "status" => "open_non_release_claim"
    }
  end

  defp local_resource_snapshot(started_at) do
    %{
      "measurement_scope" => "receipt_build_snapshot_only",
      "scheduler_count" => System.schedulers(),
      "online_scheduler_count" => System.schedulers_online(),
      "process_count" => :erlang.system_info(:process_count),
      "process_limit" => :erlang.system_info(:process_limit),
      "memory_bytes" => memory_bytes(),
      "receipt_build_elapsed_us" => max(System.monotonic_time(:microsecond) - started_at, 0),
      "performance_claim" => "not_a_scale_or_slo_claim"
    }
  end

  defp memory_bytes do
    :erlang.memory()
    |> Enum.map(fn {key, value} -> {Atom.to_string(key), value} end)
    |> Map.new()
  end

  defp maybe_put_source(receipt, opts) do
    case Keyword.get(opts, :source_ref) do
      nil -> receipt
      source_ref -> Map.put(receipt, "source_ref", source_ref)
    end
  end
end
