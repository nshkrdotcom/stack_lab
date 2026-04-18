defmodule StackLab.CitadelSpineHarness.PacketReconciliationTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "freezes the active packet ownership model and current proof anchors" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_packet_reconciliation(:packet_ownership_freeze)

    assert result.case == :packet_ownership_freeze

    assert String.ends_with?(
             result.docs.orchestration,
             "0020_oban_hybrid_orchestration_architecture.md"
           )

    assert String.ends_with?(
             result.docs.read_plane,
             "0022_leased_read_stream_plane_and_bff_schema_registry.md"
           )

    assert String.ends_with?(
             result.docs.aitrace,
             "0023_aitrace_identity_and_claim_check_contract.md"
           )

    assert String.ends_with?(result.docs.trace, "0026_trace_identity_contract.md")
    assert result.anchors.dispatch_seam == "Mezzanine.JobOutbox"
    assert result.anchors.read_lease == "leased direct lower path"
    assert result.anchors.trace_key == "trace_id"
  end

  test "proves product-facing repos do not bypass the governed write path into lower runtimes" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_packet_reconciliation(:control_path_boundaries)

    assert result.case == :control_path_boundaries
    assert result.checked_files.extravaganza > 0
    assert result.checked_files.app_kit > 0
  end

  test "mechanically gates stack IR, schema-envelope, and lease-contract drift" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_packet_reconciliation(:stack_ir_binding_map_freeze)

    assert result.case == :stack_ir_binding_map_freeze
    assert String.ends_with?(result.docs.stack_ir, "0017_stack_ir_and_binding_map.md")

    assert String.ends_with?(
             result.docs.read_plane,
             "0022_leased_read_stream_plane_and_bff_schema_registry.md"
           )

    assert String.ends_with?(result.docs.trace, "0026_trace_identity_contract.md")

    assert :boundary_generator in result.code_anchors
    assert :read_lease in result.code_anchors
    assert :stream_attach_lease in result.code_anchors
    assert :execution_record in result.code_anchors
    assert :operator_services_test in result.code_anchors
  end

  test "proves the harness no longer carries stale Stage-0 runtime owner references" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_packet_reconciliation(:stale_reference_absence)

    assert result.case == :stale_reference_absence
    assert result.checked_files > 0
  end

  test "proves the active substrate-origin AppKit proof does not use host sessions" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_packet_reconciliation(
               :substrate_origin_no_host_session_path
             )

    assert result.case == :substrate_origin_no_host_session_path
    assert result.checked_files == 1

    assert String.ends_with?(
             result.active_surface,
             "app_kit_operational_surface.ex"
           )
  end
end
