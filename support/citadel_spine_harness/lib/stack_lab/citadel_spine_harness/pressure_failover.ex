defmodule StackLab.CitadelSpineHarness.PressureFailover do
  @moduledoc false

  alias Citadel.JidoIntegrationBridge
  alias Citadel.Kernel.SessionServer
  alias Jido.Integration.V2.BrainIngress.StaticScopeResolver
  alias StackLab.CitadelSpineHarness.BoundedNames
  alias StackLab.CitadelSpineHarness.RemoteSpine
  alias StackLab.CitadelSpineHarness.RemoteSupport
  alias StackLab.CitadelSpineHarness.RemoteTransport
  alias StackLab.CitadelSpineHarness.RoundtripRuntime
  alias StackLab.CitadelSpineHarness.TransportRuntime

  @logical_workspace_ref "workspace://stack_lab/root"
  @pressure_recovery_timeout_ms 60_000
  @entry_wait_attempts div(@pressure_recovery_timeout_ms, 25)

  @spec run_case(:transport_interruption | :duplicate_delivery) :: {:ok, map()}
  def run_case(:transport_interruption) do
    with_remote_case(
      :transport_interruption,
      fn listener, remote_node ->
        %{
          initial: transport_config(listener, unavailable_node()),
          recovered: transport_config(listener, remote_node)
        }
      end,
      fn env ->
        entry =
          RoundtripRuntime.outbox_entry(
            "pressure-interrupt-entry",
            "request-single-node",
            env.snapshot
          )

        RoundtripRuntime.submit_outbox_entry!(env.session_server, entry)

        pending =
          RoundtripRuntime.wait_for_entry!(
            env.session_directory,
            entry.entry_id,
            fn candidate ->
              candidate.replay_status == :pending and
                candidate.last_error_code == "transport_unreachable"
            end,
            @entry_wait_attempts
          )

        :ok = TransportRuntime.put!(env.transport_configs.recovered)
        Process.sleep(25)
        :ok = SessionServer.replay_pending(env.session_server)

        transport = await_transport_result!(@pressure_recovery_timeout_ms)

        resolved =
          RoundtripRuntime.wait_for_entry!(
            env.session_directory,
            entry.entry_id,
            fn candidate ->
              candidate.replay_status == :submission_accepted
            end,
            @entry_wait_attempts
          )

        {:ok, acceptance} =
          RemoteSupport.remote_call!(env.remote_node, RemoteSpine, :fetch_acceptance, [
            transport.acceptance.submission_key
          ])

        {:ok,
         %{
           case: :transport_interruption,
           before_recovery: %{
             replay_status: pending.entry.replay_status,
             last_error_code: pending.entry.last_error_code
           },
           after_recovery: %{
             replay_status: resolved.entry.replay_status,
             submission_key: resolved.entry.submission_key
           },
           transport: %{
             status: transport.acceptance.status,
             submission_key: transport.acceptance.submission_key
           },
           spine: %{
             submission_key: acceptance.submission_key,
             submission_receipt_ref: acceptance.submission_receipt_ref
           }
         }}
      end
    )
  end

  def run_case(:duplicate_delivery) do
    with_remote_case(
      :duplicate_delivery,
      fn listener, remote_node ->
        %{initial: transport_config(listener, remote_node, deliver_twice?: true)}
      end,
      fn env ->
        entry =
          RoundtripRuntime.outbox_entry(
            "pressure-duplicate-entry",
            "request-single-node",
            env.snapshot
          )

        RoundtripRuntime.submit_outbox_entry!(env.session_server, entry)

        transport = await_transport_result!(@pressure_recovery_timeout_ms)

        resolved =
          RoundtripRuntime.wait_for_entry!(
            env.session_directory,
            entry.entry_id,
            fn candidate ->
              candidate.replay_status == :submission_accepted
            end,
            @entry_wait_attempts
          )

        {:ok, acceptance} =
          RemoteSupport.remote_call!(env.remote_node, RemoteSpine, :fetch_acceptance, [
            transport.acceptance.submission_key
          ])

        {:ok,
         %{
           case: :duplicate_delivery,
           transport: %{
             status: transport.acceptance.status,
             submission_key: transport.acceptance.submission_key,
             duplicate_status:
               transport.duplicate_acceptance && transport.duplicate_acceptance.status
           },
           citadel: %{
             replay_status: resolved.entry.replay_status,
             submission_key: resolved.entry.submission_key
           },
           spine: %{
             submission_key: acceptance.submission_key,
             submission_receipt_ref: acceptance.submission_receipt_ref
           }
         }}
      end
    )
  end

  defp with_remote_case(case_name, transport_config_fun, fun)
       when is_function(transport_config_fun, 2) and is_function(fun, 1) do
    listener = self()
    RoundtripRuntime.flush_transport_messages()
    previous_transport = Application.get_env(:citadel_jido_integration_bridge, :transport_module)
    remote = RemoteSupport.start_remote_spine!(case_name)
    transport_configs = transport_config_fun.(listener, remote.remote_node)
    :ok = JidoIntegrationBridge.put_transport_module(RemoteTransport)
    :ok = TransportRuntime.put!(transport_configs.initial)

    env =
      RoundtripRuntime.start_runtime_env({:pressure_failover, case_name})
      |> Map.put(:remote_node, remote.remote_node)
      |> Map.put(:remote_spine, remote)
      |> Map.put(:transport_configs, transport_configs)

    try do
      fun.(env)
    after
      :ok = RoundtripRuntime.shutdown_runtime_env(env)
      :ok = TransportRuntime.reset!()
      RemoteSupport.stop_remote_spine(remote)

      if is_nil(previous_transport) do
        Application.delete_env(:citadel_jido_integration_bridge, :transport_module)
      else
        Application.put_env(
          :citadel_jido_integration_bridge,
          :transport_module,
          previous_transport
        )
      end
    end
  end

  defp transport_config(listener, remote_node, opts \\ []) do
    workspace_root = RoundtripRuntime.workspace_root()

    %{
      listener: listener,
      remote_node: remote_node,
      timeout_ms: Keyword.get(opts, :timeout_ms, 5_000),
      deliver_twice?: Keyword.get(opts, :deliver_twice?, false),
      brain_ingress_opts: [
        submission_ledger: Jido.Integration.V2.StoreLocal.SubmissionLedger,
        submission_ledger_opts: [],
        scope_resolver: StaticScopeResolver,
        scope_resolver_opts: [mapping: %{@logical_workspace_ref => workspace_root}]
      ]
    }
  end

  defp await_transport_result!(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_await_transport_result!(deadline_ms)
  end

  defp do_await_transport_result!(deadline_ms) do
    timeout_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {:stack_lab_brain_ingress_result, %{result: :accepted} = payload} ->
        %{
          acceptance: payload.acceptance,
          duplicate_acceptance: payload.duplicate_acceptance
        }

      {:stack_lab_brain_ingress_result, %{result: :error}} ->
        do_await_transport_result!(deadline_ms)
    after
      timeout_ms ->
        raise "timed out waiting for pressure-failover transport result"
    end
  end

  defp unavailable_node do
    BoundedNames.unavailable_node()
  end
end
