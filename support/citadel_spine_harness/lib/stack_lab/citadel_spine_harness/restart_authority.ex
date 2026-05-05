defmodule StackLab.CitadelSpineHarness.RestartAuthority do
  @moduledoc false

  alias Citadel.Kernel.SessionServer
  alias GroundPlane.Contracts.Fence
  alias GroundPlane.Contracts.Lease
  alias Jido.Integration.V2.BrainIngress.StaticScopeResolver
  alias StackLab.CitadelSpineHarness.RemoteInvocationDownstream
  alias StackLab.CitadelSpineHarness.RemoteSpine
  alias StackLab.CitadelSpineHarness.RemoteSupport
  alias StackLab.CitadelSpineHarness.RoundtripRuntime
  alias StackLab.CitadelSpineHarness.TransportRuntime

  @logical_workspace_ref "workspace://stack_lab/root"
  @restart_recovery_timeout_ms 60_000
  @restart_events [
    :target_detach,
    :sandbox_restart,
    :process_crash,
    :stream_reconnect,
    :workflow_resume
  ]

  @spec run_case(
          :delayed_acceptance
          | :node_restart_recovery
          | :revoked_credentials_after_restart
          | :expired_lease_after_restart
          | :rotated_handle_epoch_after_restart
          | :stale_installation_revision_after_restart
          | :stale_target_grant_after_restart
          | :duplicate_old_lease_materialization
          | :delayed_retry_revalidates_authority
          | :restart_event_revalidation
        ) :: {:ok, map()}
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
            TransportRuntime.put!(
              transport_config(
                self(),
                replacement_remote.remote_node,
                timeout_ms: @restart_recovery_timeout_ms
              )
            )

          Process.sleep(100)
          :ok = SessionServer.replay_pending(env.session_server)

          transport = await_transport_result!(@restart_recovery_timeout_ms)

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

  def run_case(:revoked_credentials_after_restart) do
    rejected_retry(:revoked_credentials_after_restart, :lease_revoked_after_restart, fn attrs,
                                                                                        now ->
      attrs
      |> Map.put(:revoked_at, now)
      |> Map.put(:revocation_ref, "revocation://tenant-1/codex/restart")
    end)
  end

  def run_case(:expired_lease_after_restart) do
    rejected_retry(:expired_lease_after_restart, :lease_expired_after_restart, fn attrs, now ->
      Map.put(attrs, :expires_at, DateTime.add(now, -1, :second))
    end)
  end

  def run_case(:rotated_handle_epoch_after_restart) do
    rejected_retry(
      :rotated_handle_epoch_after_restart,
      :rotation_epoch_mismatch,
      fn attrs, _now -> attrs end,
      %{rotation_epoch: 0}
    )
  end

  def run_case(:stale_installation_revision_after_restart) do
    rejected_retry(
      :stale_installation_revision_after_restart,
      :stale_installation_revision,
      fn attrs, _now -> attrs end,
      %{installation_revision_ref: "installation-revision://tenant-1/app/0"}
    )
  end

  def run_case(:stale_target_grant_after_restart) do
    rejected_retry(
      :stale_target_grant_after_restart,
      :stale_target_grant,
      fn attrs, _now -> attrs end,
      %{target_grant_revision: "target-grant-revision://tenant-1/sandbox/0"}
    )
  end

  def run_case(:duplicate_old_lease_materialization) do
    rejected_retry(
      :duplicate_old_lease_materialization,
      :duplicate_dispatch_old_lease_reuse,
      fn attrs, _now -> attrs end,
      %{materialized_credential_lease_ref: "credential-lease://tenant-1/codex/old"}
    )
  end

  def run_case(:delayed_retry_revalidates_authority) do
    now = DateTime.from_unix!(1_700_000_000)
    {:ok, lease} = Lease.new(lease_attrs(now))
    fence = Fence.from_lease(lease)

    {:ok, result} =
      Fence.authorize_retry_dispatch(
        lease,
        fence,
        retry_context(%{restart_event: :workflow_resume}),
        now
      )

    {:ok,
     %{
       case: :delayed_retry_revalidates_authority,
       status: :authorized,
       retry_dispatch_status: result.retry_dispatch_status,
       active_execution_ref: result.active_execution_ref,
       idempotency_key: result.idempotency_key,
       credential_lease_ref: result.credential_lease_ref,
       target_ref: result.target_ref,
       restart_event: result.restart_event,
       redacted?: result.redacted
     }}
  end

  def run_case(:restart_event_revalidation) do
    now = DateTime.from_unix!(1_700_000_000)
    {:ok, lease} = Lease.new(lease_attrs(now))
    fence = Fence.from_lease(lease)

    events =
      Map.new(@restart_events, fn event ->
        {:ok, result} =
          Fence.authorize_retry_dispatch(
            lease,
            fence,
            retry_context(%{restart_event: event}),
            now
          )

        {event, result.retry_dispatch_status}
      end)

    {:ok,
     %{
       case: :restart_event_revalidation,
       status: :authorized,
       events: events,
       redacted?: true
     }}
  end

  defp with_remote_case(case_name, transport_config_fun, fun)
       when is_function(transport_config_fun, 2) and is_function(fun, 1) do
    listener = self()
    RoundtripRuntime.flush_transport_messages()
    remote = RemoteSupport.start_remote_spine!(case_name)
    :ok = TransportRuntime.put!(transport_config_fun.(listener, remote.remote_node))

    env =
      RoundtripRuntime.start_runtime_env({:restart_authority, case_name},
        downstream: RemoteInvocationDownstream
      )
      |> Map.put(:remote_node, remote.remote_node)
      |> Map.put(:remote_spine, remote)

    try do
      fun.(env)
    after
      :ok = RoundtripRuntime.shutdown_runtime_env(env)
      :ok = TransportRuntime.reset!()
      RemoteSupport.stop_remote_spine(remote)
    end
  end

  defp transport_config(listener, remote_node, opts \\ []) do
    workspace_root = RoundtripRuntime.workspace_root()

    %{
      listener: listener,
      remote_node: remote_node,
      timeout_ms: Keyword.get(opts, :timeout_ms, 5_000),
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
    await_transport_result!(5_000)
  end

  defp await_transport_result!(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0 do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_await_transport_result!(deadline_ms)
  end

  defp do_await_transport_result!(deadline_ms) do
    timeout_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {:stack_lab_brain_ingress_result, %{result: :accepted} = payload} ->
        %{acceptance: payload.acceptance}

      {:stack_lab_brain_ingress_result, %{result: :error, reason: :transport_unreachable}} ->
        do_await_transport_result!(deadline_ms)

      {:stack_lab_brain_ingress_result, %{result: :error, reason: reason}} ->
        raise "unexpected transport error during restart drill: #{inspect(reason)}"
    after
      timeout_ms ->
        raise "timed out waiting for restart-authority transport result"
    end
  end

  defp rejected_retry(case_name, expected_reason, lease_fun, context_overrides \\ %{}) do
    now = DateTime.from_unix!(1_700_000_000)
    attrs = lease_fun.(lease_attrs(now), now)
    {:ok, lease} = Lease.new(attrs)
    fence = Fence.from_lease(lease)

    {:error, {reason, details}} =
      Fence.authorize_retry_dispatch(
        lease,
        fence,
        retry_context(context_overrides),
        now
      )

    if reason != expected_reason do
      raise "expected #{inspect(expected_reason)} for #{case_name}, got: #{inspect(reason)}"
    end

    {:ok,
     %{
       case: case_name,
       status: :rejected,
       reason: reason,
       credential_lease_ref: Map.get(details, :credential_lease_ref),
       target_ref: Map.get(details, :target_ref),
       mismatch_field: Map.get(details, :mismatch_field),
       redacted?: Map.get(details, :redacted, true)
     }}
  end

  defp lease_attrs(now) do
    %{
      resource: "credential:codex:tenant-1:account-a",
      holder: "materializer-a",
      lease_id: "lease_active",
      epoch: 4,
      expires_at: DateTime.add(now, 30, :second),
      tenant_id: "tenant-1",
      subject_ref: "subject://tenant-1/codex/user-a",
      provider_family: "codex",
      provider_account_ref: "provider-account://tenant-1/codex/account-a",
      connector_instance_ref: "connector-instance://tenant-1/codex/a",
      credential_handle_ref: "credential-handle://tenant-1/codex/account-a",
      credential_lease_ref: "credential-lease://tenant-1/codex/a/1",
      operation_class: "cli",
      target_ref: "target://tenant-1/sandbox/a",
      attach_grant_ref: "attach-grant://tenant-1/sandbox/a",
      operation_policy_ref: "operation-policy://tenant-1/codex/run",
      installation_revision_ref: "installation-revision://tenant-1/app/1",
      policy_revision_ref: "policy-revision://tenant-1/codex/1",
      target_grant_revision: "target-grant-revision://tenant-1/sandbox/1",
      rotation_epoch: 1,
      fence_token: "fence://tenant-1/codex/a/1"
    }
  end

  defp retry_context(overrides) do
    Map.merge(
      %{
        tenant_id: "tenant-1",
        provider_family: "codex",
        provider_account_ref: "provider-account://tenant-1/codex/account-a",
        connector_instance_ref: "connector-instance://tenant-1/codex/a",
        credential_handle_ref: "credential-handle://tenant-1/codex/account-a",
        operation_class: "cli",
        target_ref: "target://tenant-1/sandbox/a",
        attach_grant_ref: "attach-grant://tenant-1/sandbox/a",
        operation_policy_ref: "operation-policy://tenant-1/codex/run",
        installation_revision_ref: "installation-revision://tenant-1/app/1",
        policy_revision_ref: "policy-revision://tenant-1/codex/1",
        target_grant_revision: "target-grant-revision://tenant-1/sandbox/1",
        rotation_epoch: 1,
        fence_token: "fence://tenant-1/codex/a/1",
        idempotency_key: "idem://tenant-1/codex/retry-1",
        dispatch_ref: "dispatch://tenant-1/codex/retry-1",
        active_execution_ref: "execution://tenant-1/codex/active-1",
        current_execution_ref: "execution://tenant-1/codex/active-1",
        retry_authority_ref: "retry-authority://tenant-1/codex/retry-1",
        materialization_epoch: 1,
        materialized_credential_lease_ref: "credential-lease://tenant-1/codex/a/1",
        restart_event: :workflow_resume
      },
      overrides
    )
  end
end
