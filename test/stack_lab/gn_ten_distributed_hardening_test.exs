defmodule StackLab.GnTenDistributedHardeningTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTenDistributedHardening

  test "records distributed proof closeout and non-claims" do
    assert {:ok, receipt} = GnTenDistributedHardening.run()

    assert receipt["schema_version"] == "stack_lab.gn_ten_distributed_hardening.v1"
    assert receipt["status"] == "pass"
    assert receipt["receipt_ref"] == "receipt://stack_lab/gn_ten_distributed_hardening/latest"
    assert receipt["hardening_scope"] == "gn_ten_local_distributed_peer_mode"

    proof_closeout = receipt["proof_matrix_closeout"]
    assert proof_closeout["proof_count"] == 31
    assert proof_closeout["implemented_count"] == 31
    assert proof_closeout["missing_proof_count"] == 0
    assert proof_closeout["open_distributed_defects"] == []

    assert "receipt://stack_lab/gn_ten_distributed_context_roundtrip/latest" in proof_closeout[
             "required_receipt_refs"
           ]

    assert "receipt://stack_lab/gn_ten_distributed_release_peer/latest" in proof_closeout[
             "required_receipt_refs"
           ]

    assert receipt["extraction_decision"]["candidate_repo"] ==
             "North-Shore-AI/crucible_cluster"

    assert receipt["extraction_decision"]["decision"] == "defer_extraction"
    assert receipt["scale_decision"]["scale_49_status"] == "host_feasibility_required"
  end

  test "maps regression coverage and remaining non-release claims" do
    assert {:ok, receipt} = GnTenDistributedHardening.run()

    regression_families =
      receipt["regression_coverage"]
      |> Enum.map(& &1["family"])

    assert "topology_preflight" in regression_families
    assert "context_roundtrip" in regression_families
    assert "router_model_roundtrip" in regression_families
    assert "partition_recovery" in regression_families
    assert "semantic_parity" in regression_families
    assert "scale_12" in regression_families
    assert "release_peer" in regression_families

    assert Enum.all?(receipt["regression_coverage"], fn family ->
             family["status"] == "covered_for_local_peer_mode" and
               nonempty_list?(family["receipt_refs"])
           end)

    non_claims =
      receipt["remaining_non_release_claims"]
      |> Enum.map(& &1["claim"])

    assert "full_9_node_lower_lane_runtime" in non_claims
    assert "production_distribution_security" in non_claims
    assert "live_provider_behavior" in non_claims
    assert "49_node_scale_stress" in non_claims
  end

  test "writes a hardening receipt to the requested path" do
    path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_gn_ten_distributed_hardening_#{System.unique_integer([:positive, :monotonic])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, receipt} = GnTenDistributedHardening.run(source_ref: "test://v2-phase18")
    assert GnTenDistributedHardening.write_receipt!(receipt, path) == path
    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["source_ref"] == "test://v2-phase18"
  end

  defp nonempty_list?(value), do: is_list(value) and value != []
end
