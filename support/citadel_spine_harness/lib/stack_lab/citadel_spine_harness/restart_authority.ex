defmodule StackLab.CitadelSpineHarness.RestartAuthority do
  @moduledoc false

  alias Citadel.JidoIntegrationBridge
  alias Citadel.Runtime.SessionServer
  alias Jido.Integration.V2.BrainIngress.StaticScopeResolver
  alias StackLab.CitadelSpineHarness.RemoteSpine
  alias StackLab.CitadelSpineHarness.RemoteSupport
  alias StackLab.CitadelSpineHarness.RemoteTransport
  alias StackLab.CitadelSpineHarness.RoundtripRuntime
  alias StackLab.CitadelSpineHarness.TransportRuntime

  @logical_workspace_ref "workspace://stack_lab/root"

  @spec run_case(:delayed_acceptance | :node_restart_recovery) :: {:ok, map()}
  def run_case(:delayed_acceptance) do
    with_remote_case(
      :delayed_acceptance,
      fn listener, remote_node ->
        transport_config(listener, remote_node, delay_ms: 150)
      end,
      fn env ->
        entry =
          RoundtripRuntime.outbox_entry(
            "restart-delay-entry",
            "request-single-node",
            env.snapshot
          )

        RoundtripRuntime.submit_outbox_entry!(env.session_server, entry)

        transport = await_transport_result!()

        resolved =
          RoundtripRuntime.wait_for_entry!(env.session_directory, entry.entry_id, fn candidate ->
            candidate.replay_status == :submission_accepted
          end)

        {:ok, acceptance} =
          RemoteSupport.remote_call!(env.remote_node, RemoteSpine, :fetch_acceptance, [
            transport.acceptance.submission_key
          ])

        {:ok,
         %{
           case: :delayed_acceptance,
           delay_ms: 150,
           transport: %{
             status: transport.acceptance.status,
             submission_key: transport.acceptance.submission_key,
             submission_receipt_ref: transport.acceptance.submission_receipt_ref
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

  def run_case(:node_restart_recovery) do
    with_remote_case(
      :node_restart_recovery,
      fn listener, remote_node ->
        transport_config(listener, remote_node)
      end,
      fn env ->
        initial_remote = env.remote_spine
        RemoteSupport.stop_remote_spine(initial_remote)

        entry =
          RoundtripRuntime.outbox_entry(
            "restart-recovery-entry",
            "request-single-node",
            env.snapshot
          )

        RoundtripRuntime.submit_outbox_entry!(env.session_server, entry)

        pending =
          RoundtripRuntime.wait_for_entry!(env.session_directory, entry.entry_id, fn candidate ->
            candidate.replay_status == :pending and
              candidate.last_error_code == "transport_unreachable"
          end)

        RoundtripRuntime.flush_transport_messages()
        replacement_remote = RemoteSupport.start_remote_spine!(:node_restart_recovery_replacement)

        try do
          :ok =
            TransportRuntime.put!(transport_config(self(), replacement_remote.remote_node))

          Process.sleep(25)
          :ok = SessionServer.replay_pending(env.session_server)

          transport = await_transport_result!()

          resolved =
            RoundtripRuntime.wait_for_entry!(
              env.session_directory,
              entry.entry_id,
              fn candidate ->
                candidate.replay_status == :submission_accepted
              end
            )

          {:ok, acceptance} =
            RemoteSupport.remote_call!(
              replacement_remote.remote_node,
              RemoteSpine,
              :fetch_acceptance,
              [
                transport.acceptance.submission_key
              ]
            )

          {:ok,
           %{
             case: :node_restart_recovery,
             before_restart: %{
               replay_status: pending.entry.replay_status,
               last_error_code: pending.entry.last_error_code
             },
             after_restart: %{
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
             },
             remote: %{
               initial_node: initial_remote.remote_node,
               replacement_node: replacement_remote.remote_node
             }
           }}
        after
          RemoteSupport.stop_remote_spine(replacement_remote)
        end
      end
    )
  end

  defp with_remote_case(case_name, transport_config_fun, fun)
       when is_function(transport_config_fun, 2) and is_function(fun, 1) do
    listener = self()
    RoundtripRuntime.flush_transport_messages()
    previous_transport = Application.get_env(:citadel_jido_integration_bridge, :transport_module)
    remote = RemoteSupport.start_remote_spine!(case_name)
    :ok = JidoIntegrationBridge.put_transport_module(RemoteTransport)
    :ok = TransportRuntime.put!(transport_config_fun.(listener, remote.remote_node))

    env =
      RoundtripRuntime.start_runtime_env(:"restart_authority_#{case_name}")
      |> Map.put(:remote_node, remote.remote_node)
      |> Map.put(:remote_spine, remote)

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
      timeout_ms: 5_000,
      delay_ms: Keyword.get(opts, :delay_ms),
      brain_ingress_opts: [
        submission_ledger: Jido.Integration.V2.StoreLocal.SubmissionLedger,
        submission_ledger_opts: [],
        scope_resolver: StaticScopeResolver,
        scope_resolver_opts: [mapping: %{@logical_workspace_ref => workspace_root}]
      ]
    }
  end

  defp await_transport_result! do
    deadline_ms = System.monotonic_time(:millisecond) + 5_000
    await_transport_result!(deadline_ms)
  end

  defp await_transport_result!(deadline_ms) do
    timeout_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {:stack_lab_brain_ingress_result, %{result: :accepted} = payload} ->
        %{acceptance: payload.acceptance}

      {:stack_lab_brain_ingress_result, %{result: :error, reason: :transport_unreachable}} ->
        await_transport_result!(deadline_ms)

      {:stack_lab_brain_ingress_result, %{result: :error, reason: reason}} ->
        raise "unexpected transport error during restart drill: #{inspect(reason)}"
    after
      timeout_ms ->
        raise "timed out waiting for restart-authority transport result"
    end
  end
end
