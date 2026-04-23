defmodule StackLab.CitadelSpineHarness.AITraceClaimCheckTraceContinuityTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness

  test "Scenario 25 proves AITrace visibility, claim-check indirection, and lower trace continuity under one trace id" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_aitrace_claim_check_trace_continuity(
               :claim_check_trace_continuity
             )

    assert result.case == :claim_check_trace_continuity
    assert result.scenario == 25
    assert is_binary(result.trace_id)
    assert String.length(result.trace_id) == 32

    assert result.app_kit_to_lower.join_keys["execution_id"] ==
             result.app_kit_to_lower.execution_id

    assert "audit_fact" in result.app_kit_to_lower.step_sources
    assert "execution_record" in result.app_kit_to_lower.step_sources
    assert "lower_run_status" in result.app_kit_to_lower.step_sources

    refute result.inline_threshold.run_input_claim_checked?
    refute result.inline_threshold.run_result_claim_checked?
    refute result.inline_threshold.attempt_output_claim_checked?
    refute result.inline_threshold.terminal_event_claim_checked?
    assert is_nil(result.inline_threshold.input_payload_ref)
    assert is_nil(result.inline_threshold.result_payload_ref)
    assert is_nil(result.inline_threshold.output_payload_ref)
    assert is_nil(result.inline_threshold.event_payload_ref)
    assert result.inline_threshold.inline_prompt == "short prompt"

    assert Enum.all?(
             result.claim_check.stage_upload_in_transaction?,
             &(&1 == false)
           )

    assert result.claim_check.run_input_claim_checked?
    assert result.claim_check.run_result_claim_checked?
    assert result.claim_check.attempt_output_claim_checked?
    assert result.claim_check.terminal_event_claim_checked?
    assert String.starts_with?(result.claim_check.input_payload_ref.key, "sha256/")
    assert String.starts_with?(result.claim_check.event_payload_ref.key, "sha256/")
    assert result.claim_check.live_reference_counts == %{input: 1, result: 1, output: 1, event: 1}
    assert result.claim_check.metadata_statuses.input.status == :referenced
    assert result.claim_check.metadata_statuses.result.status == :referenced
    assert result.claim_check.metadata_statuses.output.status == :referenced
    assert result.claim_check.metadata_statuses.event.status == :referenced
    assert result.claim_check.metadata_statuses.input.trace_id == result.trace_id
    assert result.claim_check.metadata_statuses.event.trace_id == result.trace_id
    refute "request" in result.claim_check.hot_row_shapes.input_keys
    refute "inference_result" in result.claim_check.hot_row_shapes.result_keys
    refute "inference_result" in result.claim_check.hot_row_shapes.output_keys
    assert "__claim_check__" in result.claim_check.hot_row_shapes.input_keys
    assert "__claim_check__" in result.claim_check.hot_row_shapes.result_keys
    assert "__claim_check__" in result.claim_check.hot_row_shapes.output_keys
    assert "__claim_check__" in result.claim_check.hot_row_shapes.event_keys
    assert result.claim_check.resolved_prompt_length > 64 * 1024
    assert result.claim_check.resolved_error_length > 64 * 1024
    assert result.claim_check.gc.deleted_count == 0
    assert result.claim_check.gc.skipped_live_reference_count >= 4

    assert result.staged_orphan.duplicate_payload_ref?
    assert result.staged_orphan.staged_status == :staged
    assert result.staged_orphan.payload_kind == "scenario_25_payload"
    assert result.staged_orphan.live_reference_count == 0
    assert result.staged_orphan.sweep_deleted_count == 1
    assert result.staged_orphan.swept_status == :swept
    assert result.staged_orphan.blob_deleted?

    assert result.execution_plane.lineage_trace_id == result.trace_id
    assert result.execution_plane.envelope_trace_id == result.trace_id
    assert result.execution_plane.route_trace_id == result.trace_id
    assert result.execution_plane.request_id == result.app_kit_to_lower.execution_id

    assert result.aitrace.trace_id == result.trace_id
    assert result.aitrace.trace_id_source.kind == :external_alias
    assert result.aitrace.span_count == 1
    assert result.aitrace.span_id_source.kind == :external_alias
    assert result.aitrace.start_time == nil
    assert %DateTime{} = result.aitrace.start_wall_time
    assert result.aitrace.clock_domain.source == "citadel_trace_envelope"
    assert result.aitrace.lineage.trace_id == result.trace_id
    assert result.aitrace.lineage.tenant_id == result.app_kit_to_lower.tenant_id
    assert result.aitrace.lineage.causation_id == result.app_kit_to_lower.execution_id

    assert result.aitrace.lineage.canonical_idempotency_key ==
             result.execution_plane.idempotency_key

    assert result.aitrace.aitrace_context.trace_id == result.trace_id
    assert result.aitrace.aitrace_context.span_id == result.aitrace.span_id
    assert result.aitrace.platform_envelope_field_map.trace_id == "AITrace.Trace.trace_id"

    assert result.aitrace.platform_envelope_field_map.request_id ==
             "AITrace.Context.metadata.causation_id"
  end

  test "claim-check degradation keeps telemetry and cleanup honest without mutating the ledger on stage failure" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_aitrace_claim_check_trace_continuity(
               :claim_check_degradation
             )

    assert result.case == :claim_check_degradation
    assert is_binary(result.trace_id)
    assert Enum.all?(result.delayed_stage.stage_upload_in_transaction?, &(&1 == false))
    assert result.delayed_stage.stage_event_count == 4
    assert result.delayed_stage.max_stage_latency_ms >= 200

    assert result.failure.result == {:error, :claim_check_unavailable}
    assert result.failure.run_count_unchanged?
    assert result.failure.stage_failure_count == 1
    assert result.failure.stage_failure_reason == "claim_check_unavailable"

    assert result.cleanup.orphaned_staged_payload_count == 1
    assert result.cleanup.blob_gc_skipped_live_reference_count >= 4
    assert result.cleanup.orphaned_sweep_deleted_count == 1
    assert result.cleanup.orphaned_blob_deleted?
  end
end
