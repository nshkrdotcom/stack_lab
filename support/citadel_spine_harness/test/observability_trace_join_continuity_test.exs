defmodule StackLab.CitadelSpineHarness.ObservabilityTraceJoinContinuityTest do
  use ExUnit.Case, async: false

  alias AppKit.Core.Telemetry, as: AppKitTelemetry
  alias Citadel.ObservabilityContract.Telemetry, as: CitadelTelemetry
  alias StackLab.CitadelSpineHarness

  test "Scenario 19 proves live and archived trace join continuity under one Stage 11 trace contract" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_observability_trace_join_continuity(
               :trace_join_continuity
             )

    assert result.case == :observability_trace_join_continuity
    assert result.scenario == 19
    assert result.tenant_id == "tenant-observability-trace-join"
    assert is_binary(result.trace_id)
    assert String.length(result.trace_id) == 32

    assert result.live_path.request_edge_trace_id == result.trace_id
    assert result.live_path.mezzanine_trace_id == result.trace_id
    assert result.live_path.lower_gateway_trace_id == result.trace_id
    assert result.execution_plane_backfill.lineage_trace_id == result.trace_id
    assert result.execution_plane_backfill.envelope_trace_id == result.trace_id
    assert result.execution_plane_backfill.route_trace_id == result.trace_id
    assert result.execution_plane.lineage_trace_id == result.trace_id
    assert result.execution_plane.envelope_trace_id == result.trace_id
    assert result.execution_plane.route_trace_id == result.trace_id
    assert result.claim_check.metadata_statuses.input.trace_id == result.trace_id
    assert result.claim_check.metadata_statuses.event.trace_id == result.trace_id
    assert result.aitrace.trace_id == result.trace_id

    assert "audit_fact" in result.live_path.step_sources
    assert "execution_record" in result.live_path.step_sources
    assert "decision_record" in result.live_path.step_sources
    assert "evidence_record" in result.live_path.step_sources
    assert "lower_run_status" in result.live_path.step_sources

    assert Enum.sort(Enum.map(result.archival.live_lower_fetches, &elem(&1, 0))) == [
             :attempts,
             :events,
             :fetch_run,
             :run_artifacts
           ]

    assert result.archival.archived_lower_fetches == []

    assert result.archival.hot_read_errors.work_query ==
             {:error, :archived, result.archival.manifest_ref}

    assert result.archival.hot_read_errors.operator_status ==
             {:error, :archived, result.archival.manifest_ref}

    assert result.archival.trace_id == result.trace_id
    assert result.archival.archived_manifest_ref == result.archival.manifest_ref
    assert "audit_fact" in result.archival.step_sources
    assert "execution_record" in result.archival.step_sources
    assert "decision_record" in result.archival.step_sources
    assert "evidence_record" in result.archival.step_sources
    refute "lower_run_status" in result.archival.step_sources

    assert length(result.telemetry.app_kit_unified_trace) == 2

    Enum.each(result.telemetry.app_kit_unified_trace, fn event ->
      assert event.metadata.trace_id == result.trace_id

      assert Map.keys(event.metadata) |> Enum.sort() ==
               AppKitTelemetry.metadata_keys(:unified_trace_assembled) |> Enum.sort()

      assert Map.keys(event.measurements) |> Enum.sort() ==
               AppKitTelemetry.measurement_keys(:unified_trace_assembled) |> Enum.sort()
    end)

    assert length(result.telemetry.claim_check_stage) >= 4

    Enum.each(result.telemetry.claim_check_stage, fn event ->
      assert event.metadata.trace_id == result.trace_id

      assert Map.keys(event.metadata) |> Enum.sort() == [
               :content_type,
               :payload_kind,
               :payload_ref,
               :redaction_class,
               :source_component,
               :store_backend,
               :trace_id
             ]

      assert Map.keys(event.measurements) |> Enum.sort() == [:count, :latency_ms, :payload_bytes]
    end)

    assert result.telemetry.execution_plane_backfill.metadata.trace_id == result.trace_id
    assert result.telemetry.execution_plane_backfill.measurements == %{count: 1}

    assert Map.keys(result.telemetry.execution_plane_backfill.metadata) |> Enum.sort() == [
             :boundary_session_id,
             :consumer,
             :decision_id,
             :request_id,
             :route_id,
             :source,
             :tenant_id,
             :trace_id
           ]

    assert result.telemetry.citadel_trace_publication_failure.metadata.trace_id == result.trace_id

    assert result.telemetry.citadel_trace_publication_failure.metadata.request_id ==
             result.execution_id

    assert Map.keys(result.telemetry.citadel_trace_publication_failure.metadata) |> Enum.sort() ==
             CitadelTelemetry.metadata_keys(:trace_publication_failure) |> Enum.sort()

    assert result.telemetry.citadel_trace_publication_failure.measurements == %{
             batch_size: 1,
             count: 1
           }

    assert result.telemetry.archival_run.metadata.event_name == "archival.run"
    assert result.telemetry.archival_run.metadata.trace_id == result.trace_id
    assert result.telemetry.archival_run.metadata.subject_id == result.subject_id
    assert result.telemetry.archival_run.metadata.installation_id == result.installation_id
    assert result.telemetry.archival_verified.metadata.event_name == "archival.verified"
    assert result.telemetry.archival_verified.metadata.trace_id == result.trace_id
    assert result.telemetry.archival_rows_removed.metadata.event_name == "archival.rows_removed"
    assert result.telemetry.archival_rows_removed.metadata.trace_id == result.trace_id
    assert result.telemetry.archival_rows_removed.measurements.count >= 4
  end
end
