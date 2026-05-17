defmodule StackLab.CitadelSpineHarness.Phase5SessionLeaseMapEviction do
  @moduledoc false

  alias Citadel.BoundaryLeaseView
  alias Citadel.Kernel.BoundaryLeaseTracker
  alias Citadel.Kernel.KernelSnapshot
  alias Citadel.Kernel.SessionDirectory
  alias Citadel.Kernel.SignalIngress
  alias Citadel.RuntimeObservation
  alias Jido.Integration.V2.SubjectRef
  alias StackLab.CitadelSpineHarness.BoundedNames

  defmodule TestSignalSource do
    @moduledoc false
    @behaviour Citadel.Ports.SignalSource

    @impl true
    def normalize_signal(%RuntimeObservation{} = observation), do: {:ok, observation}
  end

  defmodule BlockingConsumer do
    @moduledoc false
    use GenServer

    def start(opts), do: GenServer.start_link(__MODULE__, opts)

    def release(pid, signal_id) do
      send(pid, {:release_consumer, signal_id})
      :ok
    end

    @impl true
    def init(opts), do: {:ok, %{recorder: Keyword.get(opts, :recorder)}}

    @impl true
    def handle_call({:record_runtime_observation, observation}, _from, state) do
      if is_pid(state.recorder),
        do: send(state.recorder, {:consumer_blocked, observation.signal_id})

      receive do
        {:release_consumer, signal_id} when signal_id == observation.signal_id ->
          {:reply, :ok, state}
      after
        5_000 ->
          {:reply, {:error, :blocked_consumer_timeout}, state}
      end
    end
  end

  @spec run_case(:expiry_first_segmented_lru) :: {:ok, map()}
  def run_case(:expiry_first_segmented_lru) do
    {:ok,
     %{
       case: :expiry_first_segmented_lru,
       scenario: "203A",
       runbook: "session_lease_map_eviction.md",
       signal_ingress: prove_signal_ingress_eviction(),
       boundary_lease: prove_boundary_lease_eviction(),
       session_directory: prove_session_directory_eviction()
     }}
  end

  defp prove_signal_ingress_eviction do
    expired_name = unique_name(:phase5_eviction_signal_expired)

    {:ok, expired_pid} =
      SignalIngress.start_link(signal_ingress_opts(expired_name, expired_policy()))

    capped_name = unique_name(:phase5_eviction_signal_capped)

    {:ok, capped_pid} =
      SignalIngress.start_link(signal_ingress_opts(capped_name, capped_policy()))

    {:ok, blocking_consumer} = BlockingConsumer.start(recorder: self())

    try do
      :ok =
        SignalIngress.register_subscription(expired_name, "sess-expired",
          tenant_scope_key: {"tenant-203a", "authority-203a"}
        )

      before_keys =
        expired_name |> SignalIngress.snapshot() |> Map.fetch!(:subscriptions) |> Map.keys()

      expired_summary = SignalIngress.sweep_expired(expired_name)

      after_keys =
        expired_name |> SignalIngress.snapshot() |> Map.fetch!(:subscriptions) |> Map.keys()

      :ok = SignalIngress.register_subscription(capped_name, "sess-held")
      :ok = SignalIngress.register_consumer(capped_name, "sess-held", blocking_consumer)

      {:ok, held_acceptance} =
        SignalIngress.deliver_observation(
          capped_name,
          observation("sess-held", "sig-held", subject_id: "subject-held")
        )

      assert_blocked!("sig-held")

      {:error, rejected_partition} =
        SignalIngress.deliver_observation(
          capped_name,
          observation("sess-open", "sig-open", subject_id: "subject-open")
        )

      capped_snapshot = SignalIngress.snapshot(capped_name)
      BlockingConsumer.release(blocking_consumer, "sig-held")

      %{
        owner_module: SignalIngress,
        map_name: :subscriptions,
        ttl_parameter_used: :subscription_ttl_ms,
        count_before_sweep: length(before_keys),
        count_after_sweep: length(after_keys),
        evicted_keys: %{subscriptions: before_keys -- after_keys},
        eviction_reason: :idle_ttl_expired,
        protected_active_entry_count: map_size(capped_snapshot.partition_workers),
        protected_partition_ref: held_acceptance.partition_ref,
        rejected_partition:
          Map.take(rejected_partition, [
            :reason,
            :retry_after_ms,
            :queue_depth_before,
            :queue_depth_after,
            :resource_exhaustion?
          ]),
        sweep_summary: expired_summary
      }
    after
      stop_process(expired_pid)
      stop_process(capped_pid)
      stop_process(blocking_consumer)
    end
  end

  defp prove_boundary_lease_eviction do
    kernel_snapshot = unique_name(:phase5_eviction_kernel_snapshot)
    tracker = unique_name(:phase5_boundary_lease_tracker)
    now = DateTime.utc_now()

    {:ok, snapshot_pid} = KernelSnapshot.start_link(name: kernel_snapshot)

    {:ok, tracker_pid} =
      BoundaryLeaseTracker.start_link(
        name: tracker,
        kernel_snapshot: kernel_snapshot,
        eviction_policy: [
          sweep_interval_ms: 0,
          max_evictions_per_sweep: 10,
          lease_ttl_ms: 60_000,
          max_leases_total: 1
        ]
      )

    try do
      expired_ref = "expired-boundary"

      {:ok, _epoch} =
        BoundaryLeaseTracker.record_boundary_view(
          tracker,
          lease_view(expired_ref, DateTime.add(now, -1, :second))
        )

      before_keys =
        tracker |> BoundaryLeaseTracker.snapshot() |> Map.fetch!(:leases) |> Map.keys()

      sweep_summary = BoundaryLeaseTracker.sweep_expired(tracker)
      after_keys = tracker |> BoundaryLeaseTracker.snapshot() |> Map.fetch!(:leases) |> Map.keys()

      reuse_result =
        case BoundaryLeaseTracker.current_view(tracker, expired_ref) do
          nil -> :fail_closed
          %BoundaryLeaseView{} -> :reused
        end

      {:ok, _epoch} =
        BoundaryLeaseTracker.record_boundary_view(
          tracker,
          lease_view("live-boundary", DateTime.add(now, 60, :second))
        )

      {:error, cap_pressure_rejection} =
        BoundaryLeaseTracker.record_boundary_view(
          tracker,
          lease_view("second-live-boundary", DateTime.add(now, 60, :second))
        )

      protected_active_entry_count = map_size(BoundaryLeaseTracker.snapshot(tracker).leases)

      %{
        owner_module: BoundaryLeaseTracker,
        map_name: :leases,
        state_class: :boundary_lease,
        ttl_parameter_used: :lease_ttl_ms,
        count_before_sweep: length(before_keys),
        count_after_sweep: length(after_keys),
        evicted_entry_keys: before_keys -- after_keys,
        eviction_reason: :expires_at_elapsed,
        protected_active_entry_count: protected_active_entry_count,
        cap_pressure_rejection:
          Map.take(cap_pressure_rejection, [
            :reason,
            :retry_after_ms,
            :segment,
            :current_count,
            :ceiling,
            :resource_exhaustion?
          ]),
        post_eviction_lease_reuse_result: reuse_result,
        sweep_summary: sweep_summary
      }
    after
      stop_process(tracker_pid)
      stop_process(snapshot_pid)
    end
  end

  defp prove_session_directory_eviction do
    kernel_snapshot = unique_name(:phase5_eviction_session_kernel_snapshot)
    directory = unique_name(:phase5_session_directory)
    capped_directory = unique_name(:phase5_session_directory_capped)

    {:ok, snapshot_pid} = KernelSnapshot.start_link(name: kernel_snapshot)

    {:ok, directory_pid} =
      SessionDirectory.start_link(
        name: directory,
        kernel_snapshot: kernel_snapshot,
        eviction_policy: [
          sweep_interval_ms: 0,
          active_session_ttl_ms: 0,
          max_active_sessions_total: 10,
          max_active_sessions_per_tenant: 10
        ]
      )

    {:ok, capped_directory_pid} =
      SessionDirectory.start_link(
        name: capped_directory,
        kernel_snapshot: kernel_snapshot,
        eviction_policy: [
          sweep_interval_ms: 0,
          active_session_ttl_ms: 60_000,
          max_active_sessions_total: 10,
          max_active_sessions_per_tenant: 1
        ]
      )

    try do
      :ok =
        SessionDirectory.register_active_session(directory, "sess-expired",
          tenant_id: "tenant-203a",
          authority_scope: "authority-203a"
        )

      before_keys = active_session_ids(directory)
      sweep_summary = SessionDirectory.sweep_expired(directory)
      after_keys = active_session_ids(directory)

      :ok =
        SessionDirectory.register_active_session(capped_directory, "sess-one",
          tenant_id: "tenant-203a",
          authority_scope: "authority-203a"
        )

      {:error, cap_pressure_rejection} =
        SessionDirectory.register_active_session(capped_directory, "sess-two",
          tenant_id: "tenant-203a",
          authority_scope: "authority-203a"
        )

      %{
        owner_module: SessionDirectory,
        map_name: :active_sessions,
        state_class: :active_session_metadata,
        ttl_parameter_used: :active_session_ttl_ms,
        count_before_sweep: length(before_keys),
        count_after_sweep: length(after_keys),
        evicted_entry_keys: before_keys -- after_keys,
        eviction_reason: :idle_ttl_expired,
        protected_active_entry_count: length(active_session_ids(capped_directory)),
        cap_pressure_rejection:
          Map.take(cap_pressure_rejection, [
            :reason,
            :retry_after_ms,
            :segment,
            :current_count,
            :ceiling,
            :resource_exhaustion?
          ]),
        sweep_summary: sweep_summary
      }
    after
      stop_process(capped_directory_pid)
      stop_process(directory_pid)
      stop_process(snapshot_pid)
    end
  end

  defp signal_ingress_opts(name, eviction_policy) do
    [
      name: name,
      signal_source: TestSignalSource,
      admission_policy: [
        bucket_capacity: 16,
        refill_rate_per_second: 0,
        max_queue_depth_per_partition: 16,
        max_in_flight_per_tenant_scope: 10,
        retry_after_ms: 100,
        delivery_order_scope: :partition_fifo
      ],
      eviction_policy: eviction_policy
    ]
  end

  defp expired_policy do
    [
      sweep_interval_ms: 0,
      max_evictions_per_sweep: 20,
      subscription_ttl_ms: 0,
      consumer_ttl_ms: 0,
      partition_state_ttl_ms: 0
    ]
  end

  defp capped_policy do
    [
      sweep_interval_ms: 0,
      max_evictions_per_sweep: 20,
      partition_state_ttl_ms: 60_000,
      max_partitions_total: 1
    ]
  end

  defp observation(session_id, signal_id, opts) do
    tenant_id = Keyword.get(opts, :tenant_id, "tenant-203a")
    authority_scope = Keyword.get(opts, :authority_scope, "authority-203a")
    subject_id = Keyword.fetch!(opts, :subject_id)

    RuntimeObservation.new!(%{
      observation_id: "obs/#{signal_id}",
      request_id: "req/#{signal_id}",
      session_id: session_id,
      signal_id: signal_id,
      signal_cursor: "cursor/#{signal_id}",
      runtime_ref_id: "runtime/#{session_id}",
      event_kind: "host_signal",
      event_at: DateTime.utc_now(),
      status: "ok",
      output: %{},
      artifacts: [],
      payload: %{"status" => "ok"},
      subject_ref: SubjectRef.new!(%{kind: :run, id: subject_id, metadata: %{}}),
      evidence_refs: [],
      governance_refs: [],
      extensions: %{
        "tenant_id" => tenant_id,
        "authority_scope" => authority_scope,
        "trace_id" => "trace/#{signal_id}",
        "canonical_idempotency_key" => "idem:v1:scenario203a:#{signal_id}"
      }
    })
  end

  defp lease_view(boundary_ref, %DateTime{} = expires_at) do
    BoundaryLeaseView.new!(%{
      boundary_ref: boundary_ref,
      last_heartbeat_at: nil,
      expires_at: expires_at,
      staleness_status: :fresh,
      lease_epoch: 1,
      extensions: %{}
    })
  end

  defp active_session_ids(directory) do
    directory
    |> SessionDirectory.list_active_session_cursors()
    |> Enum.map(& &1.session_id)
  end

  defp assert_blocked!(signal_id) do
    receive do
      {:consumer_blocked, ^signal_id} -> :ok
    after
      1_000 -> raise "consumer did not block on #{inspect(signal_id)}"
    end
  end

  defp stop_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1_000)
    end
  catch
    :exit, _reason -> :ok
  end

  defp unique_name(prefix), do: BoundedNames.global_name(prefix)
end
