defmodule StackLab.CitadelSpineHarness.Phase5BeamHotPathLoadTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness

  test "describes Phase 5 beam hot-path scenarios 202 and 203" do
    scenario = CitadelSpineHarness.phase5_beam_hot_path_load_scenario()

    assert scenario.name == :phase5_beam_hot_path_load
    assert scenario.runbook == "beam_hot_path_load.md"

    assert scenario.cases == %{
             snapshot_publish_read_sustained: %{
               kind: :snapshot_publish_read_sustained,
               scenario: 202,
               minimum_duration_ms: 15_000
             },
             partitioned_signal_ingress_sustained: %{
               kind: :partitioned_signal_ingress_sustained,
               scenario: 203,
               minimum_duration_ms: 30_000
             }
           }
  end

  @tag timeout: 25_000
  test "scenario 202 records bounded sustained snapshot publish and read evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_beam_hot_path_load(
               :snapshot_publish_read_sustained
             )

    assert result.case == :snapshot_publish_read_sustained
    assert result.scenario == 202
    assert result.duration_ms >= 15_000
    assert result.operation_count >= result.minimum_operation_count
    assert result.timeout_result == :completed
    assert result.owner_mailbox_high_water >= 0
    assert result.runtime_samples.memory_before_bytes > 0
    assert result.runtime_samples.memory_after_bytes > 0
    assert result.runtime_samples.schedulers_online >= 1
    assert result.stale_read_count >= 0
    assert result.rebuild_required_count >= 1
    assert result.hot_publication_store == :ets
    assert result.persistent_term_payload? == false
  end

  @tag timeout: 45_000
  test "scenario 203 records bounded sustained partitioned signal ingress evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_beam_hot_path_load(
               :partitioned_signal_ingress_sustained
             )

    assert result.case == :partitioned_signal_ingress_sustained
    assert result.scenario == 203
    assert result.duration_ms >= 30_000
    assert result.operation_count >= result.minimum_operation_count
    assert result.accepted_count > 0
    assert result.rejected_count > 0
    assert result.delivery_order_scope == :partition_fifo
    assert result.owner_mailbox_high_water >= 0
    assert result.queue_high_water >= 1
    assert result.admission_latency_summary.count == result.operation_count
    assert result.admission_latency_summary.max_ms >= result.admission_latency_summary.min_ms
    assert result.blocked_partition_isolation? == true
    assert result.token_bucket_exhaustion.reason == :partition_token_exhausted
    assert result.tenant_scope_cap.reason == :tenant_scope_in_flight_exhausted
    assert result.rejection_queue_depth_stable? == true
    assert result.timeout_result == :completed
    assert result.runtime_samples.memory_before_bytes > 0
    assert result.runtime_samples.memory_after_bytes > 0
    assert result.runtime_samples.schedulers_online >= 1
  end
end
