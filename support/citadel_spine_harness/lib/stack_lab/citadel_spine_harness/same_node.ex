defmodule StackLab.CitadelSpineHarness.SameNode do
  @moduledoc false

  alias Citadel.Kernel.SessionDirectory
  alias Jido.Integration.V2.BrainIngress.StaticScopeResolver
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.Server, as: StoreLocalServer
  alias Jido.Integration.V2.StoreLocal.Storage, as: StoreLocalStorage
  alias Jido.Integration.V2.StoreLocal.SubmissionLedger
  alias StackLab.CitadelSpineHarness.RoundtripRuntime
  alias StackLab.CitadelSpineHarness.TransportRuntime

  @logical_workspace_ref "workspace://stack_lab/root"

  @spec run_case(:acceptance | :duplicate | :scope_rejection) :: {:ok, map()}
  def run_case(:acceptance) do
    with_case_runtime(:acceptance, fn env ->
      entry =
        RoundtripRuntime.outbox_entry(
          "single-node-accept-entry",
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
        SubmissionLedger.fetch_acceptance(transport.acceptance.submission_key, [])

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
         }
       }}
    end)
  end

  def run_case(:duplicate) do
    with_case_runtime(:duplicate, fn env ->
      first_entry =
        RoundtripRuntime.outbox_entry(
          "single-node-duplicate-entry-1",
          "request-single-node",
          env.snapshot
        )

      RoundtripRuntime.submit_outbox_entry!(env.session_server, first_entry)

      first_transport = await_transport_result!()

      first_resolved =
        RoundtripRuntime.wait_for_entry!(
          env.session_directory,
          first_entry.entry_id,
          fn candidate ->
            candidate.replay_status == :submission_accepted
          end
        )

      second_entry =
        RoundtripRuntime.outbox_entry(
          "single-node-duplicate-entry-2",
          "request-single-node",
          env.snapshot
        )

      RoundtripRuntime.submit_outbox_entry!(env.session_server, second_entry)

      second_transport = await_transport_result!()

      second_resolved =
        RoundtripRuntime.wait_for_entry!(
          env.session_directory,
          second_entry.entry_id,
          fn candidate ->
            candidate.replay_status == :submission_accepted
          end
        )

      {:ok, ledger_acceptance} =
        SubmissionLedger.fetch_acceptance(first_transport.acceptance.submission_key, [])

      {:ok,
       %{
         case: :duplicate,
         first: %{
           transport: %{
             status: first_transport.acceptance.status,
             submission_key: first_transport.acceptance.submission_key
           },
           citadel: %{
             entry_id: first_resolved.entry.entry_id,
             replay_status: first_resolved.entry.replay_status,
             submission_key: first_resolved.entry.submission_key,
             submission_receipt_ref: first_resolved.entry.submission_receipt_ref
           }
         },
         second: %{
           transport: %{
             status: second_transport.acceptance.status,
             submission_key: second_transport.acceptance.submission_key
           },
           citadel: %{
             entry_id: second_resolved.entry.entry_id,
             replay_status: second_resolved.entry.replay_status,
             submission_key: second_resolved.entry.submission_key,
             submission_receipt_ref: second_resolved.entry.submission_receipt_ref
           }
         },
         ledger: %{
           submission_key: ledger_acceptance.submission_key,
           submission_receipt_ref: ledger_acceptance.submission_receipt_ref
         }
       }}
    end)
  end

  def run_case(:scope_rejection) do
    with_case_runtime(:scope_rejection, fn env ->
      entry =
        RoundtripRuntime.outbox_entry(
          "single-node-reject-entry",
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
        StoreLocalStorage.read(fn state ->
          Map.get(state.submission_rejections, transport.rejection.submission_key)
        end)

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
           rejection_family: stored_rejection && stored_rejection.rejection_family,
           reason_code: stored_rejection && stored_rejection.reason_code
         }
       }}
    end)
  end

  defp with_case_runtime(case_name, fun) when is_function(fun, 1) do
    listener = self()
    RoundtripRuntime.flush_transport_messages()
    storage_dir = store_local_dir(case_name)
    ensure_store_local_ready!(storage_dir)

    config = transport_config(case_name, listener)
    :ok = TransportRuntime.put!(config)

    env = RoundtripRuntime.start_runtime_env(case_name)

    try do
      fun.(env)
    after
      :ok = RoundtripRuntime.shutdown_runtime_env(env)
      :ok = TransportRuntime.reset!()
      stop_store_local()
      File.rm_rf!(storage_dir)
    end
  end

  defp ensure_store_local_ready!(storage_dir) do
    stop_store_local()
    File.rm_rf!(storage_dir)
    File.mkdir_p!(storage_dir)
    :ok = StoreLocal.configure_defaults!(storage_dir: storage_dir)

    _ = Application.ensure_all_started(:jido_integration_v2_store_local)

    case Process.whereis(StoreLocalServer) do
      nil ->
        raise "store_local server did not start"

      _pid ->
        :ok = StoreLocal.reset!()
    end
  end

  defp stop_store_local do
    case Application.stop(:jido_integration_v2_store_local) do
      :ok -> :ok
      {:error, {:not_started, :jido_integration_v2_store_local}} -> :ok
      {:error, {:not_started, _other_app}} -> :ok
      {:error, reason} -> raise "unable to stop store_local application: #{inspect(reason)}"
    end
  end

  defp transport_config(:scope_rejection, listener) do
    %{
      listener: listener,
      submission_ledger: SubmissionLedger,
      submission_ledger_opts: [],
      scope_resolver: StaticScopeResolver,
      scope_resolver_opts: [mapping: %{}]
    }
  end

  defp transport_config(_case_name, listener) do
    workspace_root = RoundtripRuntime.workspace_root()

    %{
      listener: listener,
      submission_ledger: SubmissionLedger,
      submission_ledger_opts: [],
      scope_resolver: StaticScopeResolver,
      scope_resolver_opts: [mapping: %{@logical_workspace_ref => workspace_root}]
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
      2_000 ->
        raise "timed out waiting for brain ingress result"
    end
  end

  defp store_local_dir(case_name) do
    Path.join(
      System.tmp_dir!(),
      "stack_lab_citadel_spine_store_local_#{case_name}_#{System.unique_integer([:positive])}"
    )
  end
end
