defmodule StackLab.CitadelSpineHarness.MultiNode do
  @moduledoc false

  alias Citadel.JidoIntegrationBridge
  alias Citadel.Kernel.SessionDirectory
  alias Jido.Integration.V2.BrainIngress.StaticScopeResolver
  alias StackLab.CitadelSpineHarness.RemoteSpine
  alias StackLab.CitadelSpineHarness.RemoteSupport
  alias StackLab.CitadelSpineHarness.RemoteTransport
  alias StackLab.CitadelSpineHarness.RoundtripRuntime
  alias StackLab.CitadelSpineHarness.TransportRuntime

  @logical_workspace_ref "workspace://stack_lab/root"

  @spec run_case(:acceptance | :scope_rejection) :: {:ok, map()}
  def run_case(:acceptance) do
    with_case_runtime(:acceptance, fn env ->
      entry =
        RoundtripRuntime.outbox_entry(
          "multi-node-accept-entry",
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
         case: :acceptance,
         transport: %{
           status: transport.acceptance.status,
           submission_key: transport.acceptance.submission_key,
           submission_receipt_ref: transport.acceptance.submission_receipt_ref
         },
         citadel: %{
           entry_id: resolved.entry.entry_id,
           replay_status: resolved.entry.replay_status,
           submission_key: resolved.entry.submission_key,
           submission_receipt_ref: resolved.entry.submission_receipt_ref
         },
         spine: %{
           submission_key: acceptance.submission_key,
           submission_receipt_ref: acceptance.submission_receipt_ref
         },
         runtime_inputs: transport.runtime_inputs,
         scope: %{
           workspace_root: transport.runtime_inputs.workspace_root,
           file_scope: transport.gateway.sandbox.file_scope
         },
         remote: %{remote_node: env.remote_node}
       }}
    end)
  end

  def run_case(:scope_rejection) do
    with_case_runtime(:scope_rejection, fn env ->
      entry =
        RoundtripRuntime.outbox_entry(
          "multi-node-reject-entry",
          "request-single-node",
          env.snapshot
        )

      RoundtripRuntime.submit_outbox_entry!(env.session_server, entry)

      transport = await_transport_result!()

      resolved =
        RoundtripRuntime.wait_for_entry!(env.session_directory, entry.entry_id, fn candidate ->
          candidate.replay_status == :superseded and
            candidate.last_error_code == "workspace_ref_unresolved"
        end)

      {:ok, persisted_blob} =
        SessionDirectory.fetch_persisted_blob(env.session_directory, env.session_id)

      stored_rejection =
        RemoteSupport.remote_call!(env.remote_node, RemoteSpine, :fetch_rejection, [
          transport.rejection.submission_key
        ])

      rejection_keys =
        RemoteSupport.remote_call!(env.remote_node, RemoteSpine, :rejection_keys, [])

      {:ok,
       %{
         case: :scope_rejection,
         transport: %{
           rejection_family: transport.rejection.rejection_family,
           reason_code: transport.rejection.reason_code
         },
         citadel: %{
           entry_id: resolved.entry.entry_id,
           replay_status: resolved.entry.replay_status,
           last_error_code: resolved.entry.last_error_code,
           has_redecision_entry:
             Enum.any?(persisted_blob.outbox_entries, fn {_entry_id, candidate} ->
               candidate.action.action_kind == "enqueue_redecision"
             end)
         },
         spine: %{
           submission_key: transport.rejection.submission_key,
           rejection_family: stored_rejection && stored_rejection.rejection_family,
           reason_code: stored_rejection && stored_rejection.reason_code,
           rejection_keys: rejection_keys
         },
         remote: %{remote_node: env.remote_node}
       }}
    end)
  end

  defp with_case_runtime(case_name, fun) when is_function(fun, 1) do
    listener = self()
    RoundtripRuntime.flush_transport_messages()

    previous_transport = Application.get_env(:citadel_jido_integration_bridge, :transport_module)
    remote = RemoteSupport.start_remote_spine!(case_name)
    :ok = JidoIntegrationBridge.put_transport_module(RemoteTransport)
    :ok = TransportRuntime.put!(transport_config(case_name, listener, remote.remote_node))

    env =
      RoundtripRuntime.start_runtime_env({:multi_node, case_name})
      |> Map.put(:remote_node, remote.remote_node)
      |> Map.put(:remote_spine, remote)

    try do
      fun.(env)
    after
      :ok = RoundtripRuntime.shutdown_runtime_env(env)
      :ok = TransportRuntime.reset!()
      :ok = RemoteSupport.stop_remote_spine(remote)

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

  defp transport_config(:scope_rejection, listener, remote_node) do
    %{
      listener: listener,
      remote_node: remote_node,
      timeout_ms: 5_000,
      brain_ingress_opts: [
        submission_ledger: Jido.Integration.V2.StoreLocal.SubmissionLedger,
        submission_ledger_opts: [],
        scope_resolver: StaticScopeResolver,
        scope_resolver_opts: [mapping: %{}]
      ]
    }
  end

  defp transport_config(_case_name, listener, remote_node) do
    workspace_root = RoundtripRuntime.workspace_root()

    %{
      listener: listener,
      remote_node: remote_node,
      timeout_ms: 5_000,
      brain_ingress_opts: [
        submission_ledger: Jido.Integration.V2.StoreLocal.SubmissionLedger,
        submission_ledger_opts: [],
        scope_resolver: StaticScopeResolver,
        scope_resolver_opts: [mapping: %{@logical_workspace_ref => workspace_root}]
      ]
    }
  end

  defp await_transport_result! do
    receive do
      {:stack_lab_brain_ingress_result, %{result: :accepted} = payload} ->
        %{
          acceptance: payload.acceptance,
          gateway: payload.gateway,
          runtime_inputs: payload.runtime_inputs
        }

      {:stack_lab_brain_ingress_result, %{result: :rejected} = payload} ->
        %{rejection: payload.rejection}
    after
      5_000 ->
        raise "timed out waiting for remote brain ingress result"
    end
  end
end
