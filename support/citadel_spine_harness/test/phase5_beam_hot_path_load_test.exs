defmodule StackLab.CitadelSpineHarness.Phase5BeamHotPathLoadTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "describes Phase 5 beam hot-path scenarios 202 and 203" do
    scenario = CitadelSpineHarness.phase5_beam_hot_path_load_scenario()

    assert scenario.name == :phase5_beam_hot_path_load
    assert scenario.runbook == "beam_hot_path_load.md"

    assert scenario.cases == %{
             snapshot_publish_read_sustained: %{
               kind: :snapshot_publish_read_sustained,
               scenario: 202,
               target_operation_count: 500
             },
             snapshot_staleness_classes: %{
               kind: :snapshot_staleness_classes,
               scenario: 202
             },
             partitioned_signal_ingress_sustained: %{
               kind: :partitioned_signal_ingress_sustained,
               scenario: 203,
               target_operation_count: 500
             },
             partition_fifo_ordering_scope: %{
               kind: :partition_fifo_ordering_scope,
               scenario: 203
             }
           }
  end

  test "scenario 202 records bounded sustained snapshot publish and read evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_beam_hot_path_load(
               :snapshot_publish_read_sustained
             )

    assert result.case == :snapshot_publish_read_sustained
    assert result.scenario == 202
    assert result.operation_count == result.target_operation_count
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

  test "scenario 203 records bounded sustained partitioned signal ingress evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_beam_hot_path_load(
               :partitioned_signal_ingress_sustained
             )

    assert result.case == :partitioned_signal_ingress_sustained
    assert result.scenario == 203
    assert result.operation_count == result.target_operation_count
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

  test "scenario 202 proves snapshot staleness classes and fail-closed negatives" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_beam_hot_path_load(:snapshot_staleness_classes)

    assert result.case == :snapshot_staleness_classes
    assert result.scenario == 202

    assert result.positive_path.staleness_classes == [
             :fresh_required,
             :bounded_stale_allowed,
             :reject_stale
           ]

    assert result.positive_path.hot_publication_store == :ets
    assert result.positive_path.read_concurrency? == true
    assert result.negative_failure_modes.fresh_required.safe_action == :reject_stale
    assert result.negative_failure_modes.bounded_stale_allowed.safe_action == :reject_stale
    assert result.negative_failure_modes.rebuild_required.safe_action == :rebuild_required
    assert result.negative_failure_modes.reject_stale.safe_action == :reject_stale
    assert result.negative_failure_modes.invalid_class.reason == :invalid_staleness_class
  end

  test "scenario 203 proves partition FIFO scope without cross-partition ordering claims" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_beam_hot_path_load(
               :partition_fifo_ordering_scope
             )

    assert result.case == :partition_fifo_ordering_scope
    assert result.scenario == 203
    assert result.delivery_order_scope == :partition_fifo
    assert result.partition_fifo.alpha == ["sig-alpha-1", "sig-alpha-2", "sig-alpha-3"]
    assert result.partition_fifo.beta == ["sig-beta-1", "sig-beta-2", "sig-beta-3"]

    assert result.rejected_ordering_claims == [
             :global_fifo,
             :tenant_total_fifo,
             :cross_partition_fifo
           ]

    assert result.cross_partition_ordering_assumption? == false
  end

  test "scenario 203A proves expiry-first segmented LRU eviction and fail-closed reuse" do
    scenario = CitadelSpineHarness.phase5_session_lease_map_eviction_scenario()

    assert scenario.name == :phase5_session_lease_map_eviction
    assert scenario.runbook == "session_lease_map_eviction.md"
    assert scenario.cases.expiry_first_segmented_lru.scenario == "203A"

    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_session_lease_map_eviction(
               :expiry_first_segmented_lru
             )

    assert result.case == :expiry_first_segmented_lru
    assert result.scenario == "203A"
    assert result.signal_ingress.evicted_keys.subscriptions == ["sess-expired"]
    assert result.signal_ingress.rejected_partition.reason == :partition_capacity_exhausted
    assert result.boundary_lease.evicted_entry_keys == ["expired-boundary"]
    assert result.boundary_lease.protected_active_entry_count == 1
    assert result.boundary_lease.cap_pressure_rejection.reason == :lease_capacity_exhausted
    assert result.boundary_lease.post_eviction_lease_reuse_result == :fail_closed
    assert result.session_directory.evicted_entry_keys == ["sess-expired"]

    assert result.session_directory.cap_pressure_rejection.reason ==
             :active_session_tenant_capacity_exhausted
  end
end
