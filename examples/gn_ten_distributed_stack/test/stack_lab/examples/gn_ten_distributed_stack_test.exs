defmodule StackLab.Examples.GnTenDistributedStackTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.GnTenDistributedStack

  test "runs the context 6-node distributed proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_context_6_node()

    assert receipt.status == :pass
    assert receipt.profile == "context_6_node"
    assert receipt.context_packet_hash =~ "sha256:"
    assert receipt.node_lab_run["status"] == "pass"
    assert receipt.node_lab_run["log_artifact"]["line_count"] > 0
    assert File.exists?(receipt.node_lab_run["log_artifact"]["path"])
    assert receipt.distributed_envelope_scan["status"] == "pass"
    assert receipt.evidence_status == "pass"
    assert receipt.persistence_status == "pass"
    assert deterministic_profile?(receipt, "mickey_mouse", "none")
    assert deterministic_profile?(receipt, "memory_debug", "none")
    assert external_profile?(receipt, "integration_postgres", "durable")
    assert external_profile?(receipt, "ops_durable_temporal", "durable_restart")
    assert length(receipt.node_trace_refs) == 5
    assert length(receipt.aitrace_exports) == 5
    assert Enum.all?(receipt.aitrace_exports, &(&1["status"] == "pass"))
    assert receipt.replay_bundle.bundle_ref =~ "replay-bundle://stack_lab/context-abi"
    assert receipt.node_placement.distinct_domain_nodes? == true
    assert receipt.node_placement.domain_node_count == 5
  end

  test "runs the router/model 6-node distributed proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_router_model_6_node()

    assert receipt.status == :pass
    assert receipt.profile == "router_model_6_node"
    assert receipt.context_packet_hash =~ "sha256:"
    assert receipt.route_decision_ref =~ "router_decision:"
    assert receipt.prompt_artifact_ref =~ "prompt-artifact://"
    assert receipt.provider_payload_ref =~ "provider-payload://"
    assert receipt.payload_hash =~ "sha256:"
    assert receipt.model_receipt_ref =~ "jido-model-invocation-receipt/"
    assert is_integer(receipt.model_token_summary["input"])
    assert is_integer(receipt.model_token_summary["total"])
    assert receipt.model_token_summary["input"] > 0
    assert receipt.model_token_summary["total"] >= receipt.model_token_summary["input"]
    assert receipt.model_cost_summary["currency"] == "USD"
    assert receipt.model_stream_refs == []
    assert receipt.stream_fragment_posture == "not_requested"
    assert receipt.node_lab_run["status"] == "pass"
    assert receipt.node_lab_run["log_artifact"]["line_count"] > 0
    assert File.exists?(receipt.node_lab_run["log_artifact"]["path"])
    assert receipt.distributed_envelope_scan["status"] == "pass"
    assert receipt.evidence_status == "pass"
    assert receipt.persistence_status == "pass"
    assert receipt.persistence_profiles["matrix_scan"]["status"] == "pass"
    refute receipt.persistence_profiles["substrate_started_by_stack_lab?"]
    refute receipt.persistence_profiles["temporal_started_by_stack_lab?"]
    refute receipt.persistence_profiles["postgres_started_by_stack_lab?"]
    refute receipt.persistence_profiles["raw_debug_payloads_persisted?"]
    assert length(receipt.node_trace_refs) == 6
    assert length(receipt.aitrace_exports) == 6
    assert Enum.all?(receipt.aitrace_exports, &(&1["status"] == "pass"))
    assert receipt.replay_bundle.bundle_ref =~ "replay-bundle://stack_lab/router-fabric"
    assert receipt.replay_bundle.model_receipt_ref == receipt.model_receipt_ref
    assert "eval-verdict://router-fabric/demo/pass" in receipt.appkit_projection_refs
    assert receipt.node_placement.distinct_domain_nodes? == true
    assert receipt.node_placement.domain_node_count == 6
  end

  test "runs the monolith/distributed semantic parity proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_parity()

    assert receipt.status == :pass
    assert receipt.profile == "parity"
    assert receipt.canonical_encoder == "GroundPlane.Boundary.Codec"
    assert receipt.hash_input_policy["hash_inputs_use"] == "GroundPlane.Boundary.Codec"
    assert "inspect/1" in receipt.hash_input_policy["forbidden_hash_inputs"]
    assert "Jason.encode!/1" in receipt.hash_input_policy["forbidden_hash_inputs"]
    assert receipt.parity_result["status"] == "pass"
    assert receipt.parity_result["findings"] == []
    assert receipt.monolith_semantic_hash == receipt.distributed_semantic_hash
    assert receipt.monolith_semantic_hash =~ "sha256:"
    assert "prompt_artifact_ref" in receipt.semantic_fields
    assert "node_lab_run" in receipt.ignored_fields
  end

  test "semantic parity uses GroundPlane boundary codec and is stable by map order" do
    left = %{
      "status" => "pass",
      "context_packet_hash" => "sha256:abc",
      "model_cost_summary" => %{"currency" => "USD", "estimated_usd" => 0.0}
    }

    right = %{
      "model_cost_summary" => %{"estimated_usd" => 0.0, "currency" => "USD"},
      "context_packet_hash" => "sha256:abc",
      "status" => "pass"
    }

    assert GnTenDistributedStack.semantic_hash(left) ==
             GnTenDistributedStack.semantic_hash(right)

    assert GnTenDistributedStack.semantic_hash(left) ==
             GroundPlane.Boundary.Codec.digest(%{
               "context_packet_hash" => "sha256:abc",
               "model_cost_summary" => %{"currency" => "USD", "estimated_usd" => "0.0"},
               "status" => "pass"
             })
  end

  test "semantic parity ignores placement and timing fields only" do
    monolith = %{"status" => "pass", "context_packet_hash" => "sha256:abc"}

    distributed =
      Map.merge(monolith, %{
        "node_placement" => %{"nodes" => ["mezzanine_workflow_0@localhost"]},
        "wall_clock_duration_ms" => 42,
        "transport_attempt_ref" => "transport-attempt://fixture"
      })

    result =
      GnTenDistributedStack.semantic_parity(monolith, distributed,
        semantic_fields: ["status", "context_packet_hash"]
      )

    assert result["status"] == "pass"
    assert result["findings"] == []
  end

  test "semantic parity records missing fields" do
    result =
      GnTenDistributedStack.semantic_parity(
        %{"status" => "pass", "model_receipt_ref" => "receipt://a"},
        %{"status" => "pass"},
        semantic_fields: ["status", "model_receipt_ref"]
      )

    assert result["status"] == "open_defect"
    assert %{"kind" => "missing_field", "field" => "model_receipt_ref"} in result["findings"]
  end

  test "semantic parity records raw and transport-introduced semantic fields" do
    result =
      GnTenDistributedStack.semantic_parity(
        %{"status" => "pass"},
        %{
          "status" => "pass",
          "raw_provider_payload" => "forbidden",
          "transport_semantic_override" => "forbidden"
        },
        semantic_fields: ["status"]
      )

    assert result["status"] == "open_defect"

    assert %{"kind" => "raw_payload_field", "field" => "raw_provider_payload"} in result[
             "findings"
           ]

    assert %{"kind" => "unexpected_semantic_field", "field" => "transport_semantic_override"} in result[
             "findings"
           ]
  end

  test "semantic parity records terminal status mismatch" do
    result =
      GnTenDistributedStack.semantic_parity(
        %{"status" => "pass"},
        %{"status" => "open_defect"},
        semantic_fields: ["status"]
      )

    assert result["status"] == "open_defect"

    assert Enum.any?(result["findings"], fn finding ->
             finding["kind"] == "value_mismatch" and finding["field"] == "status"
           end)
  end

  test "runs the default 12-node scale proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_scale_12_node()

    assert receipt.status == :pass
    assert receipt.profile == "scale_12_node"
    assert receipt.node_count == 12
    assert receipt.node_cap == 12
    assert receipt.scale_gate["status"] == "pass"
    assert receipt.scale_gate["proof_mode"] == "default_local_gate"
    assert receipt.cleanup_status == "pass"
    assert receipt.resource_summary["node_count"] == 12
    assert receipt.resource_summary["startup_duration_ms"] >= 0
    assert receipt.resource_summary["peer_failure_count"] == 0
    assert receipt.resource_summary["scheduler_flags"] == ["+S 1"]
    assert is_integer(receipt.resource_summary["host_before"]["cpu"]["logical_cores"])
    assert is_integer(receipt.resource_summary["host_before"]["limits"]["open_files_soft"])
    assert receipt.host_feasibility["status"] == "pass"

    assert receipt.parity_baseline_receipt_ref ==
             "receipt://stack_lab/gn_ten_distributed_parity/latest"

    assert receipt.node_lab_run["log_artifact"]["line_count"] >= 24
    assert File.exists?(receipt.node_lab_run["log_artifact"]["path"])
  end

  test "scale proof enforces requested max node cap" do
    assert {:ok, receipt} = GnTenDistributedStack.run_scale_12_node(max_nodes: 11)

    assert receipt.status == :open_defect
    assert receipt.node_count == 12
    assert receipt.scale_gate["status"] == "open_defect"
    assert receipt.scale_gate["reason"] == "node_count_above_requested_cap"
    assert receipt.cleanup_status == "not_started"
    assert is_nil(receipt.node_lab_run)
  end

  test "scale 49 proof is blocked until a host feasibility receipt is supplied" do
    assert {:ok, receipt} = GnTenDistributedStack.run_scale_49_node()

    assert receipt.status == :open_defect
    assert receipt.profile == "scale_49_node"
    assert receipt.node_count == 49
    assert receipt.node_cap == 49
    assert receipt.scale_gate["status"] == "blocked_missing_host_feasibility"
    assert receipt.host_feasibility["status"] == "blocked_missing_host_feasibility"
    assert "empty_peer_memory" in receipt.host_feasibility["required_fields"]
    assert receipt.cleanup_status == "not_started"
    assert is_nil(receipt.node_lab_run)
  end

  test "records AITrace export failure posture without leaking raw evidence" do
    assert {:ok, receipt} =
             GnTenDistributedStack.run_router_model_6_node(
               evidence_opts: [
                 responses: %{
                   "export_trace" => {:error, %{"code" => "exporter_unavailable"}}
                 }
               ]
             )

    assert receipt.status == :open_defect
    assert receipt.evidence_status == "open_defect"
    assert Enum.all?(receipt.aitrace_exports, &(&1["status"] == "open_defect"))

    json = GnTenDistributedStack.to_json!(receipt)
    refute json =~ "cookie_value"
    refute json =~ "raw_prompt"
    refute json =~ "provider_payload\":"
  end

  test "runs the partition recovery fault receipt proof" do
    assert {:ok, receipt} = GnTenDistributedStack.run_partition_recovery()

    assert receipt.status == :pass
    assert receipt.profile == "partition_recovery"
    assert receipt.persistence_status == "pass"
    assert deterministic_profile?(receipt, "mickey_mouse", "none")
    assert external_profile?(receipt, "ops_durable_temporal", "durable_restart")
    assert length(receipt.fault_receipts) == 7
    assert Enum.all?(receipt.fault_receipts, &(&1["status"] == "pass"))
    assert Enum.any?(receipt.fault_receipts, &(&1["fault_kind"] == "node_crash"))
    assert Enum.any?(receipt.fault_receipts, &(&1["fault_kind"] == "stale_dto"))
    assert Enum.any?(receipt.fault_receipts, &(&1["fault_kind"] == "trace_exporter_failure"))
    assert Enum.any?(receipt.owner_recovery_evidence, &(&1["owner"] == "mezzanine"))
    assert Enum.any?(receipt.owner_recovery_evidence, &(&1["owner"] == "citadel"))

    json = GnTenDistributedStack.to_json!(receipt)
    refute json =~ "cookie_value"
    refute json =~ "raw_prompt"
    refute json =~ "provider_payload\":"
    refute json =~ "DATABASE_URL"
  end

  test "runs the release-peer prototype against Execution Plane" do
    assert {:ok, receipt} = GnTenDistributedStack.run_release_peer()

    assert receipt.status == :pass
    assert receipt.profile == "execution_plane_node"
    assert receipt.release_mode == "test_only_release_wrapper"
    assert receipt.owner_repo == "execution_plane"
    assert receipt.otp_app == "execution_plane"
    assert receipt.release_startup["status"] == "pass"
    assert receipt.facade_ping["status"] == "pass"
    assert receipt.receipt_shape_parity["status"] == "pass"
    assert receipt.receipt_ref =~ "gn-ten-release-path://stack_lab-test-only-execution-plane-node"
    assert "production release packaging" in receipt.does_not_prove
  end

  test "release-peer prototype records missing release manifest as open defect" do
    missing_path =
      Path.join(System.tmp_dir!(), "missing-release-#{System.unique_integer([:positive])}.exs")

    assert {:ok, receipt} = GnTenDistributedStack.run_release_peer(manifest_path: missing_path)

    assert receipt.status == :open_defect
    assert receipt.release_startup["status"] == "not_started"
    assert receipt.release_startup["failure"]["code"] == "release_manifest_missing"
  end

  test "release-peer prototype records version mismatch" do
    assert {:ok, receipt} = GnTenDistributedStack.run_release_peer(expected_version: "999.0.0")

    assert receipt.status == :open_defect
    assert receipt.release_startup["status"] == "open_defect"
    assert receipt.release_startup["code"] == "version_mismatch"
  end

  test "release-peer prototype records unavailable facade" do
    missing_facade = Module.concat([Missing, ReleasePeerFacade])

    manifest =
      release_manifest(%{
        facade_module: missing_facade,
        owner_group: {missing_facade, :lane}
      })

    assert {:ok, receipt} = GnTenDistributedStack.run_release_peer(manifest: manifest)

    assert receipt.status == :open_defect
    assert receipt.release_startup["status"] == "pass"
    assert receipt.facade_ping["status"] == "open_defect"
    assert receipt.facade_ping["code"] == "facade_unavailable_or_owner_group_mismatch"
  end

  test "release-peer prototype records receipt shape mismatch against peer mode" do
    manifest = release_manifest(%{peer_mode_receipt_shape: ["node_id", "missing_peer_field"]})

    assert {:ok, receipt} = GnTenDistributedStack.run_release_peer(manifest: manifest)

    assert receipt.status == :open_defect
    assert receipt.facade_ping["status"] == "pass"
    assert receipt.receipt_shape_parity["status"] == "open_defect"
    assert receipt.receipt_shape_parity["missing_fields"] == ["missing_peer_field"]
  end

  defp deterministic_profile?(receipt, profile_id, restart_claim) do
    Enum.any?(receipt.persistence_profiles["deterministic_profiles"], fn profile ->
      profile["profile_id"] == profile_id and profile["restart_claim"] == restart_claim and
        profile["durable_opt_in?"] == false
    end)
  end

  defp external_profile?(receipt, profile_id, restart_claim) do
    Enum.any?(receipt.persistence_profiles["opt_in_external_profiles"], fn profile ->
      profile["profile_id"] == profile_id and profile["restart_claim"] == restart_claim and
        profile["durable_opt_in?"] == true and
        profile["substrate_started_by_stack_lab?"] == false
    end)
  end

  defp release_manifest(overrides) do
    Map.merge(
      %{
        release_ref: "release://stack_lab/test-only/execution-plane-node/v1",
        release_mode: "test_only_release_wrapper",
        profile: :execution_plane_node,
        owner_repo: "execution_plane",
        owner_package: "core/execution_plane",
        otp_app: :execution_plane,
        expected_version: "0.1.0",
        facade_module: ExecutionPlane.RemoteFacade.Lane,
        owner_group: {ExecutionPlane.RemoteFacade.Lane, :lane},
        peer_mode_shape_ref: "receipt-shape://stack_lab/node-lab/peer-mode/v1",
        peer_mode_receipt_shape: [
          "facade_hosts",
          "node",
          "node_id",
          "owner_group_membership",
          "profile",
          "ready?",
          "started_apps"
        ]
      },
      overrides
    )
  end
end
