defmodule StackLab.CitadelSpineHarness.Phase5BeamHotPathLoad do
  @moduledoc false

  alias Citadel.DecisionSnapshot
  alias Citadel.Kernel.KernelSnapshot
  alias Citadel.Kernel.SignalIngress
  alias Citadel.KernelEpochUpdate
  alias Citadel.RuntimeObservation
  alias Jido.Integration.V2.SubjectRef

  @scenario_202_duration_ms 15_000
  @scenario_202_minimum_operations 500
  @scenario_203_duration_ms 30_000
  @scenario_203_minimum_operations 500

  defmodule TestSignalSource do
    @moduledoc false
    @behaviour Citadel.Ports.SignalSource

    @impl true
    def normalize_signal(%RuntimeObservation{} = observation), do: {:ok, observation}
  end

  defmodule BlockingConsumer do
    @moduledoc false
    use GenServer

    def start(opts), do: GenServer.start(__MODULE__, opts)

    def release(pid, count \\ 1) when is_pid(pid) and count >= 1 do
      Enum.each(1..count, fn _index -> send(pid, :release_consumer) end)
      :ok
    end

    @impl true
    def init(opts) do
      {:ok,
       %{
         blocked_count: 0,
         recorder: Keyword.get(opts, :recorder)
       }}
    end

    @impl true
    def handle_call({:record_runtime_observation, observation}, _from, state) do
      send_recorder(state.recorder, {:consumer_blocked, observation.signal_id})

      receive do
        :release_consumer ->
          {:reply, :ok, %{state | blocked_count: state.blocked_count + 1}}

        {:release_consumer, signal_id} when signal_id == observation.signal_id ->
          {:reply, :ok, %{state | blocked_count: state.blocked_count + 1}}
      after
        45_000 ->
          {:reply, {:error, :blocked_consumer_timeout}, state}
      end
    end

    defp send_recorder(nil, _message), do: :ok
    defp send_recorder(pid, message) when is_pid(pid), do: send(pid, message)
  end

  defmodule CountingConsumer do
    @moduledoc false
    use GenServer

    def start(opts), do: GenServer.start(__MODULE__, opts)
    def count(pid), do: GenServer.call(pid, :count)
    def observed_signal_ids(pid), do: GenServer.call(pid, :observed_signal_ids)

    @impl true
    def init(_opts), do: {:ok, %{count: 0, signal_ids: []}}

    @impl true
    def handle_call(:count, _from, state), do: {:reply, state.count, state}

    def handle_call(:observed_signal_ids, _from, state), do: {:reply, state.signal_ids, state}

    def handle_call({:record_runtime_observation, observation}, _from, state) do
      {:reply, :ok,
       %{
         state
         | count: state.count + 1,
           signal_ids: state.signal_ids ++ [observation.signal_id]
       }}
    end
  end

  @spec run_case(
          :snapshot_publish_read_sustained
          | :snapshot_staleness_classes
          | :partitioned_signal_ingress_sustained
          | :partition_fifo_ordering_scope
        ) :: {:ok, map()}
  def run_case(:snapshot_publish_read_sustained), do: run_snapshot_publish_read_sustained()
  def run_case(:snapshot_staleness_classes), do: run_snapshot_staleness_classes()

  def run_case(:partitioned_signal_ingress_sustained),
    do: run_partitioned_signal_ingress_sustained()

  def run_case(:partition_fifo_ordering_scope), do: run_partition_fifo_ordering_scope()

  defp run_snapshot_publish_read_sustained do
    name = unique_name(:phase5_kernel_snapshot)
    {:ok, pid} = KernelSnapshot.start_link(name: name, policy_epoch: 0, policy_version: "v0")

    started_at_ms = monotonic_ms()
    deadline_ms = started_at_ms + @scenario_202_duration_ms
    before_sample = runtime_sample()

    try do
      state =
        snapshot_publish_read_loop(name, pid, deadline_ms, %{
          operation_count: 0,
          stale_read_count: 0,
          rebuild_required_count: 0,
          owner_mailbox_high_water: 0,
          last_epoch: 0
        })

      after_sample = runtime_sample()
      duration_ms = monotonic_ms() - started_at_ms
      read_surface = KernelSnapshot.read_surface_info(name)

      {:ok,
       %{
         case: :snapshot_publish_read_sustained,
         scenario: 202,
         minimum_duration_ms: @scenario_202_duration_ms,
         duration_ms: duration_ms,
         operation_count: state.operation_count,
         minimum_operation_count: @scenario_202_minimum_operations,
         timeout_result: :completed,
         owner_mailbox_high_water: state.owner_mailbox_high_water,
         runtime_samples: runtime_samples(before_sample, after_sample),
         stale_read_count: state.stale_read_count,
         rebuild_required_count: state.rebuild_required_count,
         hot_publication_store: read_surface.storage,
         persistent_term_payload?: persistent_term_payload?(read_surface.discovery_key),
         final_epoch: state.last_epoch
       }}
    after
      stop_process(pid)
    end
  end

  defp snapshot_publish_read_loop(name, pid, deadline_ms, state) do
    if monotonic_ms() >= deadline_ms do
      state
    else
      epoch = state.last_epoch + 1

      KernelSnapshot.publish_epoch_update(
        name,
        KernelEpochUpdate.new!(%{
          source_owner: "stack_lab_phase5_scenario_202",
          constituent: :policy_epoch,
          epoch: epoch,
          updated_at: DateTime.utc_now(),
          extensions: %{"policy_version" => "v#{epoch}"}
        })
      )

      read_result =
        KernelSnapshot.read_snapshot(name,
          staleness_class: :fresh_required,
          required_min_sequence: epoch
        )

      Process.sleep(1)

      snapshot_publish_read_loop(name, pid, deadline_ms, %{
        state
        | operation_count: state.operation_count + 1,
          stale_read_count: count_stale_read(read_result, state.stale_read_count),
          rebuild_required_count:
            maybe_count_rebuild_required(name, epoch, state.rebuild_required_count),
          owner_mailbox_high_water: max(state.owner_mailbox_high_water, mailbox_depth(pid)),
          last_epoch: epoch
      })
    end
  end

  defp maybe_count_rebuild_required(_name, epoch, count) when rem(epoch, 50) != 0, do: count

  defp maybe_count_rebuild_required(name, _epoch, count) do
    case KernelSnapshot.read_snapshot(name, staleness_class: :rebuild_required) do
      {:error, %{safe_action: :rebuild_required}} -> count + 1
      _other -> count
    end
  end

  defp count_stale_read({:ok, _evidence}, count), do: count
  defp count_stale_read({:error, _reason}, count), do: count + 1

  defp run_snapshot_staleness_classes do
    name = unique_name(:phase5_kernel_snapshot_staleness)
    {:ok, pid} = KernelSnapshot.start_link(name: name, policy_epoch: 0, policy_version: "v0")

    try do
      KernelSnapshot.publish_epoch_update(
        name,
        KernelEpochUpdate.new!(%{
          source_owner: "stack_lab_phase5_scenario_202_staleness",
          constituent: :policy_epoch,
          epoch: 1,
          updated_at: DateTime.utc_now(),
          extensions: %{"policy_version" => "v1"}
        })
      )

      :ok = wait_until(fn -> KernelSnapshot.snapshot(name).snapshot_seq >= 1 end)

      {:ok, fresh_required} =
        KernelSnapshot.read_snapshot(name,
          staleness_class: :fresh_required,
          required_min_sequence: 1
        )

      {:ok, bounded_stale_allowed} =
        KernelSnapshot.read_snapshot(name,
          staleness_class: :bounded_stale_allowed,
          max_age_ms: 60_000,
          max_sequence_lag: 0,
          owner_sequence: fresh_required.snapshot_sequence
        )

      {:ok, reject_stale_positive} =
        KernelSnapshot.read_snapshot(name,
          staleness_class: :reject_stale,
          required_min_sequence: 1
        )

      {:error, fresh_required_negative} =
        KernelSnapshot.read_snapshot(name,
          staleness_class: :fresh_required,
          required_min_sequence: fresh_required.snapshot_sequence + 1
        )

      {:error, bounded_stale_negative} =
        KernelSnapshot.read_snapshot(name,
          staleness_class: :bounded_stale_allowed,
          max_age_ms: 60_000,
          max_sequence_lag: 0,
          owner_sequence: fresh_required.snapshot_sequence + 1
        )

      {:error, rebuild_required} =
        KernelSnapshot.read_snapshot(name, staleness_class: :rebuild_required)

      {:error, reject_stale_negative} =
        KernelSnapshot.read_snapshot(name,
          staleness_class: :reject_stale,
          required_min_sequence: fresh_required.snapshot_sequence + 1
        )

      {:error, invalid_class} =
        KernelSnapshot.read_snapshot(name, staleness_class: :eventually_consistent)

      read_surface = KernelSnapshot.read_surface_info(name)

      {:ok,
       %{
         case: :snapshot_staleness_classes,
         scenario: 202,
         positive_path: %{
           staleness_classes: [
             fresh_required.staleness_class,
             bounded_stale_allowed.staleness_class,
             reject_stale_positive.staleness_class
           ],
           snapshot_sequence: fresh_required.snapshot_sequence,
           max_age_ms: bounded_stale_allowed.max_age_ms,
           max_sequence_lag: bounded_stale_allowed.max_sequence_lag,
           hot_publication_store: read_surface.storage,
           read_concurrency?: read_surface.read_concurrency?
         },
         negative_failure_modes: %{
           fresh_required: Map.take(fresh_required_negative, [:reason, :safe_action]),
           bounded_stale_allowed:
             Map.take(bounded_stale_negative, [:reason, :safe_action, :max_sequence_lag]),
           rebuild_required: Map.take(rebuild_required, [:reason, :safe_action]),
           reject_stale: Map.take(reject_stale_negative, [:reason, :safe_action]),
           invalid_class: Map.take(invalid_class, [:reason, :safe_action, :staleness_class])
         }
       }}
    after
      stop_process(pid)
    end
  end

  defp run_partitioned_signal_ingress_sustained do
    name = unique_name(:phase5_signal_ingress)
    {:ok, ingress_pid} = SignalIngress.start_link(signal_ingress_opts(name, sustained_policy()))
    {:ok, blocking_consumer} = BlockingConsumer.start([])
    {:ok, counting_consumer} = CountingConsumer.start([])

    :ok = SignalIngress.register_subscription(name, "sess-blocked")
    :ok = SignalIngress.register_subscription(name, "sess-open")
    :ok = SignalIngress.register_consumer(name, "sess-blocked", blocking_consumer)
    :ok = SignalIngress.register_consumer(name, "sess-open", counting_consumer)

    started_at_ms = monotonic_ms()
    deadline_ms = started_at_ms + @scenario_203_duration_ms
    before_sample = runtime_sample()

    try do
      state =
        partitioned_ingress_loop(name, ingress_pid, deadline_ms, %{
          operation_count: 0,
          accepted_count: 0,
          rejected_count: 0,
          rejection_queue_depth_stable?: true,
          owner_mailbox_high_water: 0,
          queue_high_water: 0,
          delivery_order_scope: nil,
          latency: latency_accumulator(),
          rejection_reasons: %{}
        })

      release_blocking_consumer(blocking_consumer, name)
      open_delivery_count = CountingConsumer.count(counting_consumer)
      after_sample = runtime_sample()
      duration_ms = monotonic_ms() - started_at_ms

      {:ok, token_bucket_exhaustion} = prove_token_bucket_exhaustion()
      {:ok, tenant_scope_cap} = prove_tenant_scope_cap()

      {:ok,
       %{
         case: :partitioned_signal_ingress_sustained,
         scenario: 203,
         minimum_duration_ms: @scenario_203_duration_ms,
         duration_ms: duration_ms,
         operation_count: state.operation_count,
         minimum_operation_count: @scenario_203_minimum_operations,
         accepted_count: state.accepted_count,
         rejected_count: state.rejected_count,
         delivery_order_scope: state.delivery_order_scope || :partition_fifo,
         owner_mailbox_high_water: state.owner_mailbox_high_water,
         queue_high_water: state.queue_high_water,
         admission_latency_summary: summarize_latency(state.latency),
         blocked_partition_isolation?:
           open_delivery_count > 0 and state.rejected_count > 0 and state.queue_high_water >= 1,
         token_bucket_exhaustion: token_bucket_exhaustion,
         tenant_scope_cap: tenant_scope_cap,
         rejection_queue_depth_stable?: state.rejection_queue_depth_stable?,
         timeout_result: :completed,
         runtime_samples: runtime_samples(before_sample, after_sample),
         rejection_reasons: state.rejection_reasons,
         open_delivery_count: open_delivery_count
       }}
    after
      stop_process(ingress_pid)
      stop_process(blocking_consumer)
      stop_process(counting_consumer)
    end
  end

  defp run_partition_fifo_ordering_scope do
    name = unique_name(:phase5_signal_ordering)
    {:ok, ingress_pid} = SignalIngress.start_link(signal_ingress_opts(name, sustained_policy()))
    {:ok, alpha_consumer} = CountingConsumer.start([])
    {:ok, beta_consumer} = CountingConsumer.start([])

    try do
      :ok = SignalIngress.register_subscription(name, "sess-alpha")
      :ok = SignalIngress.register_subscription(name, "sess-beta")
      :ok = SignalIngress.register_consumer(name, "sess-alpha", alpha_consumer)
      :ok = SignalIngress.register_consumer(name, "sess-beta", beta_consumer)

      acceptances =
        [
          observation("sess-alpha", "sig-alpha-1", subject_id: "subject-alpha"),
          observation("sess-beta", "sig-beta-1", subject_id: "subject-beta"),
          observation("sess-alpha", "sig-alpha-2", subject_id: "subject-alpha"),
          observation("sess-beta", "sig-beta-2", subject_id: "subject-beta"),
          observation("sess-alpha", "sig-alpha-3", subject_id: "subject-alpha"),
          observation("sess-beta", "sig-beta-3", subject_id: "subject-beta")
        ]
        |> Enum.map(fn observation ->
          {:ok, acceptance} = SignalIngress.deliver_observation(name, observation)
          acceptance
        end)

      :ok =
        wait_until(fn ->
          CountingConsumer.count(alpha_consumer) == 3 and
            CountingConsumer.count(beta_consumer) == 3
        end)

      {:ok,
       %{
         case: :partition_fifo_ordering_scope,
         scenario: 203,
         delivery_order_scope:
           acceptances
           |> Enum.map(& &1.delivery_order_scope)
           |> Enum.uniq()
           |> only_scope!(),
         partition_fifo: %{
           alpha: CountingConsumer.observed_signal_ids(alpha_consumer),
           beta: CountingConsumer.observed_signal_ids(beta_consumer)
         },
         partition_refs:
           acceptances
           |> Enum.map(& &1.partition_ref)
           |> Enum.uniq(),
         rejected_ordering_claims: [:global_fifo, :tenant_total_fifo, :cross_partition_fifo],
         cross_partition_ordering_assumption?: false
       }}
    after
      stop_process(ingress_pid)
      stop_process(alpha_consumer)
      stop_process(beta_consumer)
    end
  end

  defp partitioned_ingress_loop(name, ingress_pid, deadline_ms, state) do
    if monotonic_ms() >= deadline_ms do
      state
    else
      signal_index = state.operation_count + 1
      blocked? = rem(signal_index, 3) == 0
      observation = sustained_observation(signal_index, blocked?)

      {latency_ms, result} =
        timed(fn -> SignalIngress.deliver_observation(name, observation) end)

      snapshot = SignalIngress.snapshot(name)
      queue_high_water = max(state.queue_high_water, max_queue_depth(snapshot))

      state =
        state
        |> Map.update!(:latency, &record_latency(&1, latency_ms))
        |> Map.put(:queue_high_water, queue_high_water)
        |> Map.put(
          :owner_mailbox_high_water,
          max(state.owner_mailbox_high_water, mailbox_depth(ingress_pid))
        )
        |> record_admission_result(result)

      Process.sleep(1)
      partitioned_ingress_loop(name, ingress_pid, deadline_ms, state)
    end
  end

  defp record_admission_result(state, {:ok, acceptance}) do
    %{
      state
      | operation_count: state.operation_count + 1,
        accepted_count: state.accepted_count + 1,
        delivery_order_scope: state.delivery_order_scope || acceptance.delivery_order_scope
    }
  end

  defp record_admission_result(state, {:error, rejection}) when is_map(rejection) do
    %{
      state
      | operation_count: state.operation_count + 1,
        rejected_count: state.rejected_count + 1,
        rejection_queue_depth_stable?:
          state.rejection_queue_depth_stable? and
            Map.get(rejection, :queue_depth_before) == Map.get(rejection, :queue_depth_after),
        rejection_reasons: Map.update(state.rejection_reasons, rejection.reason, 1, &(&1 + 1))
    }
  end

  defp signal_ingress_opts(name, admission_policy) do
    [
      name: name,
      signal_source: TestSignalSource,
      admission_policy: admission_policy
    ]
  end

  defp sustained_policy do
    [
      bucket_capacity: 20_000,
      refill_rate_per_second: 20_000,
      max_queue_depth_per_partition: 64,
      max_in_flight_per_tenant_scope: 256,
      retry_after_ms: 25,
      delivery_order_scope: :partition_fifo
    ]
  end

  defp prove_token_bucket_exhaustion do
    name = unique_name(:phase5_signal_token)

    {:ok, ingress_pid} =
      SignalIngress.start_link(signal_ingress_opts(name, token_bucket_policy()))

    try do
      observation = observation("sess-token", "sig-token-1", subject_id: "subject-token")
      {:ok, accepted} = SignalIngress.deliver_observation(name, observation)

      :ok =
        wait_until(fn ->
          snapshot = SignalIngress.snapshot(name)
          Map.get(snapshot.partition_queue_depths, accepted.partition_ref, 0) == 0
        end)

      {:error, rejection} =
        SignalIngress.deliver_observation(
          name,
          observation("sess-token", "sig-token-2", subject_id: "subject-token")
        )

      {:ok,
       Map.take(rejection, [:reason, :retry_after_ms, :queue_depth_before, :queue_depth_after])}
    after
      stop_process(ingress_pid)
    end
  end

  defp prove_tenant_scope_cap do
    name = unique_name(:phase5_signal_tenant_scope)

    {:ok, ingress_pid} =
      SignalIngress.start_link(signal_ingress_opts(name, tenant_scope_policy()))

    {:ok, blocking_consumer} = BlockingConsumer.start([])

    try do
      :ok = SignalIngress.register_subscription(name, "sess-held")
      :ok = SignalIngress.register_consumer(name, "sess-held", blocking_consumer)

      {:ok, _acceptance} =
        SignalIngress.deliver_observation(
          name,
          observation("sess-held", "sig-held", subject_id: "subject-held")
        )

      {:error, rejection} =
        SignalIngress.deliver_observation(
          name,
          observation("sess-other", "sig-other", subject_id: "subject-other")
        )

      {:ok,
       Map.take(rejection, [:reason, :retry_after_ms, :queue_depth_before, :queue_depth_after])}
    after
      BlockingConsumer.release(blocking_consumer, 4)
      stop_process(ingress_pid)
      stop_process(blocking_consumer)
    end
  end

  defp token_bucket_policy do
    [
      bucket_capacity: 1,
      refill_rate_per_second: 0,
      max_queue_depth_per_partition: 16,
      max_in_flight_per_tenant_scope: 16,
      retry_after_ms: 250,
      delivery_order_scope: :partition_fifo
    ]
  end

  defp tenant_scope_policy do
    [
      bucket_capacity: 16,
      refill_rate_per_second: 0,
      max_queue_depth_per_partition: 16,
      max_in_flight_per_tenant_scope: 1,
      retry_after_ms: 300,
      delivery_order_scope: :partition_fifo
    ]
  end

  defp sustained_observation(index, true) do
    observation("sess-blocked", "sig-blocked-#{index}", subject_id: "subject-blocked")
  end

  defp sustained_observation(index, false) do
    observation("sess-open", "sig-open-#{index}", subject_id: "subject-open")
  end

  defp observation(session_id, signal_id, opts) do
    tenant_id = Keyword.get(opts, :tenant_id, "tenant-203")
    authority_scope = Keyword.get(opts, :authority_scope, "authority-203")
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
      extensions:
        %{}
        |> maybe_put("tenant_id", tenant_id)
        |> maybe_put("authority_scope", authority_scope)
    })
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp release_blocking_consumer(pid, ingress_name) do
    release_count =
      case SignalIngress.snapshot(ingress_name) do
        %{partition_queue_depths: queue_depths} ->
          queue_depths
          |> Map.values()
          |> Enum.sum()
          |> Kernel.+(4)

        _other ->
          4
      end

    BlockingConsumer.release(pid, max(release_count, 4))
  rescue
    _error -> :ok
  end

  defp runtime_sample do
    {gc_count, gc_words_reclaimed, _zero} = :erlang.statistics(:garbage_collection)

    %{
      memory_bytes: :erlang.memory(:total),
      gc_count: gc_count,
      gc_words_reclaimed: gc_words_reclaimed,
      run_queue: :erlang.statistics(:run_queue),
      schedulers_online: System.schedulers_online()
    }
  end

  defp runtime_samples(before_sample, after_sample) do
    %{
      memory_before_bytes: before_sample.memory_bytes,
      memory_after_bytes: after_sample.memory_bytes,
      gc_count_before: before_sample.gc_count,
      gc_count_after: after_sample.gc_count,
      gc_words_reclaimed_before: before_sample.gc_words_reclaimed,
      gc_words_reclaimed_after: after_sample.gc_words_reclaimed,
      run_queue_before: before_sample.run_queue,
      run_queue_after: after_sample.run_queue,
      schedulers_online: before_sample.schedulers_online
    }
  end

  defp latency_accumulator, do: %{count: 0, min_ms: nil, max_ms: 0, sum_ms: 0}

  defp record_latency(acc, latency_ms) do
    %{
      count: acc.count + 1,
      min_ms: min(acc.min_ms || latency_ms, latency_ms),
      max_ms: max(acc.max_ms, latency_ms),
      sum_ms: acc.sum_ms + latency_ms
    }
  end

  defp summarize_latency(%{count: 0}), do: %{count: 0, min_ms: 0, max_ms: 0, avg_ms: 0.0}

  defp summarize_latency(acc) do
    %{
      count: acc.count,
      min_ms: acc.min_ms || 0,
      max_ms: acc.max_ms,
      avg_ms: acc.sum_ms / acc.count
    }
  end

  defp timed(fun) do
    started_at = System.monotonic_time(:microsecond)
    result = fun.()
    finished_at = System.monotonic_time(:microsecond)
    {max(div(finished_at - started_at, 1_000), 0), result}
  end

  defp max_queue_depth(%{partition_queue_depths: queue_depths}) when map_size(queue_depths) == 0,
    do: 0

  defp max_queue_depth(%{partition_queue_depths: queue_depths}) do
    queue_depths
    |> Map.values()
    |> Enum.max()
  end

  defp persistent_term_payload?(discovery_key) do
    match?(%DecisionSnapshot{}, :persistent_term.get(discovery_key, :missing))
  end

  defp mailbox_depth(pid) when is_pid(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, depth} -> depth
      nil -> 0
    end
  end

  defp wait_until(fun, attempts \\ 40)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: {:error, :timeout}

  defp only_scope!([scope]), do: scope

  defp stop_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1_000)
    end
  catch
    :exit, _reason -> :ok
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
  defp unique_name(prefix), do: :"#{prefix}_#{System.unique_integer([:positive, :monotonic])}"
end
