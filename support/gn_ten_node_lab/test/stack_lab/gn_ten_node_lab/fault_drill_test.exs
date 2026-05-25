defmodule StackLab.GnTenNodeLab.FaultDrillTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTenNodeLab.{FaultDrill, Peer}

  test "records node crash posture from cleanup evidence" do
    receipt = FaultDrill.crash_node!(run_receipt(), "jido_model_runtime_0")

    assert receipt["status"] == "pass"
    assert receipt["fault_kind"] == "node_crash"
    assert receipt["cleanup_status"] == "stopped"
    assert receipt["actual_safe_action"] == "node_down_recorded_no_ambient_fallback"
  end

  test "stops a live peer when a harness run carries peer handles" do
    assert {:ok, peer} = Peer.start(name: Peer.generated_node_name(:peer))

    try do
      receipt = FaultDrill.crash_node!(live_peer_run(peer), "jido_model_runtime_0")

      assert receipt["status"] == "pass"
      assert receipt["fault_execution_mode"] == "live_peer_stop"
      assert receipt["cleanup_status"] == "stopped"
      assert receipt["crashed_node"] == Atom.to_string(peer.peer_node)
      refute Process.alive?(peer.peer_pid)
    after
      if Process.alive?(peer.peer_pid), do: Peer.stop(peer)
    end
  end

  test "records stale DTO rejection through the envelope scanner" do
    receipt =
      FaultDrill.inject_stale_dto!(
        run_receipt(),
        "seam://mezzanine/jido/model-invocation",
        "fixture://fault-drill/stale-dto"
      )

    assert receipt["status"] == "pass"
    assert receipt["fault_kind"] == "stale_dto"
    assert receipt["scanner_receipt"]["status"] == "open_defect"

    assert Enum.any?(
             receipt["scanner_receipt"]["findings"],
             &(&1["rule"] == "version_mismatch")
           )
  end

  test "records duplicate and exporter failure receipts" do
    duplicate = FaultDrill.duplicate_submit!(run_receipt(), "accepted://one")
    exporter = FaultDrill.kill_exporter!(run_receipt(), :aitrace_evidence)

    assert duplicate["status"] == "pass"
    assert duplicate["dedupe_status"] == "same_terminal_facts"
    assert exporter["status"] == "pass"
    assert exporter["actual_safe_action"] == "export_unavailable_posture_recorded"
  end

  defp run_receipt do
    %{
      "run_id" => "fault-run",
      "topology_ref" => "topology://stack_lab/gn-ten/router-model-6-node/v1",
      "boot_receipts" => [
        %{"node_id" => "jido_model_runtime_0"},
        %{"node_id" => "aitrace_evidence_0"}
      ],
      "cleanup" => [
        %{
          "node_id" => "jido_model_runtime_0",
          "node" => "jido_model_runtime_0@localhost",
          "stopped?" => true,
          "reachable_after_stop?" => false
        }
      ]
    }
  end

  defp live_peer_run(peer) do
    run_receipt()
    |> Map.delete("cleanup")
    |> Map.put("live_peers", [
      %{
        "node_id" => "jido_model_runtime_0",
        "peer" => peer
      }
    ])
  end
end
