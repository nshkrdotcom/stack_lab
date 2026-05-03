defmodule StackLab.CitadelSpineHarness.SemanticHost do
  @moduledoc false

  alias AppKit.ChatSurface
  alias AppKit.ScopeObjects
  alias Citadel.DomainSurface.Adapters.CitadelAdapter
  alias Citadel.InvocationBridge
  alias Citadel.Kernel.SessionDirectory
  alias Jido.Integration.V2.BrainIngress.StaticScopeResolver
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.Server, as: StoreLocalServer
  alias Jido.Integration.V2.StoreLocal.Storage, as: StoreLocalStorage
  alias Jido.Integration.V2.StoreLocal.SubmissionLedger
  alias StackLab.CitadelSpineHarness.InProcessInvocationDownstream
  alias StackLab.CitadelSpineHarness.RoundtripRuntime
  alias StackLab.CitadelSpineHarness.TransportRuntime

  @logical_workspace_ref "workspace://workspace/workspace/main"

  @spec run_case(:turn_acceptance | :turn_replay | :turn_scope_rejection) :: {:ok, map()}
  def run_case(:turn_acceptance) do
    with_case_runtime(:turn_acceptance, fn env ->
      {scope, runtime_opts} = runtime_context(env)

      {:ok, result} = submit_turn(scope, runtime_opts, "semantic-host-turn-1")

      if result.state != :accepted do
        raise "expected AppKit semantic host submission to be accepted, got: #{inspect(result)}"
      end

      {request, attempt_entry} = await_invocation_request!()

      resolved =
        RoundtripRuntime.wait_for_entry!(
          env.session_directory,
          attempt_entry.entry_id,
          fn candidate -> candidate.replay_status == :submission_accepted end
        )

      {:ok, acceptance} =
        SubmissionLedger.fetch_acceptance(resolved.entry.submission_key, [])

      {:ok,
       %{
         case: :turn_acceptance,
         app_kit: %{
           state: result.state,
           request_id: result.payload.accepted.request_id,
           manifest_id: result.payload.manifest_id
         },
         semantic: %{
           route: result.payload.action_request.route,
           args: result.payload.action_request.args
         },
         citadel: %{
           entry_id: resolved.entry.entry_id,
           replay_status: resolved.entry.replay_status,
           submission_key: resolved.entry.submission_key,
           submission_receipt_ref: resolved.entry.submission_receipt_ref
         },
         invocation: %{
           request_id: request.request_id,
           selected_step_id: request.selected_step_id,
           execution_intent: request.extensions["citadel"]["execution_intent"]
         },
         spine: %{
           submission_key: acceptance.submission_key,
           submission_receipt_ref: acceptance.submission_receipt_ref
         }
       }}
    end)
  end

  def run_case(:turn_replay) do
    with_case_runtime(:turn_replay, fn env ->
      {scope, runtime_opts} = runtime_context(env)

      {:ok, first_result} =
        submit_turn(scope, runtime_opts, "semantic-host-turn-replay",
          trace_id: RoundtripRuntime.trace_id("semantic-host-turn-replay-1")
        )

      {request, attempt_entry} = await_invocation_request!()

      {:ok, second_result} =
        submit_turn(scope, runtime_opts, "semantic-host-turn-replay",
          trace_id: RoundtripRuntime.trace_id("semantic-host-turn-replay-2")
        )

      refute_invocation_request!()

      resolved =
        RoundtripRuntime.wait_for_entry!(
          env.session_directory,
          attempt_entry.entry_id,
          fn candidate -> candidate.replay_status == :submission_accepted end
        )

      {:ok, acceptance} =
        SubmissionLedger.fetch_acceptance(resolved.entry.submission_key, [])

      {:ok,
       %{
         case: :turn_replay,
         first: %{
           app_kit: duplicate_app_kit_result(first_result),
           semantic: %{
             route: first_result.payload.action_request.route,
             args: first_result.payload.action_request.args
           }
         },
         second: %{
           app_kit: duplicate_app_kit_result(second_result)
         },
         invocation: %{
           request_id: request.request_id,
           selected_step_id: request.selected_step_id,
           execution_intent: request.extensions["citadel"]["execution_intent"]
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
         }
       }}
    end)
  end

  def run_case(:turn_scope_rejection) do
    with_case_runtime(:turn_scope_rejection, fn env ->
      {scope, runtime_opts} = runtime_context(env)

      {:ok, result} =
        submit_turn(scope, runtime_opts, "semantic-host-turn-rejection",
          trace_id: RoundtripRuntime.trace_id("semantic-host-turn-rejection")
        )

      {_request, attempt_entry} = await_invocation_request!()
      transport = await_transport_rejection!()

      resolved =
        RoundtripRuntime.wait_for_entry!(
          env.session_directory,
          attempt_entry.entry_id,
          fn candidate ->
            candidate.replay_status == :superseded and
              candidate.last_error_code == "workspace_ref_unresolved"
          end
        )

      {:ok, persisted_blob} =
        SessionDirectory.fetch_persisted_blob(env.session_directory, env.session_id)

      stored_rejection =
        StoreLocalStorage.read(fn state ->
          Map.get(state.submission_rejections, transport.rejection.submission_key)
        end)

      {:ok,
       %{
         case: :turn_scope_rejection,
         app_kit: %{
           state: result.state,
           request_id: result.payload.accepted.request_id,
           manifest_id: result.payload.manifest_id
         },
         semantic: %{
           route: result.payload.action_request.route,
           args: result.payload.action_request.args
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

    :ok =
      TransportRuntime.put!(transport_config(case_name, listener))

    Code.ensure_loaded!(InProcessInvocationDownstream)
    bridge = InvocationBridge.new!(downstream: InProcessInvocationDownstream)

    env =
      RoundtripRuntime.start_runtime_env({:semantic_host, case_name},
        invocation_handler: RoundtripRuntime.host_ingress_invocation_handler(bridge, listener)
      )

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

  defp transport_config(:turn_scope_rejection, listener) do
    %{
      listener: listener,
      submission_ledger: SubmissionLedger,
      submission_ledger_opts: [],
      scope_resolver: StaticScopeResolver,
      scope_resolver_opts: [mapping: %{}]
    }
  end

  defp transport_config(_case_name, listener) do
    %{
      listener: listener,
      submission_ledger: SubmissionLedger,
      submission_ledger_opts: [],
      scope_resolver: StaticScopeResolver,
      scope_resolver_opts: [
        mapping: %{@logical_workspace_ref => RoundtripRuntime.workspace_root()}
      ]
    }
  end

  defp policy_pack do
    %{
      pack_id: "default",
      policy_version: "policy-stack-lab",
      policy_epoch: 1,
      priority: 0,
      selector: %{
        tenant_ids: [],
        scope_kinds: [],
        environments: [],
        default?: true,
        extensions: %{}
      },
      profiles: %{
        trust_profile: "baseline",
        approval_profile: "standard",
        egress_profile: "restricted",
        workspace_profile: "workspace",
        resource_profile: "standard",
        boundary_class: "workspace_session",
        extensions: %{}
      },
      rejection_policy: %{
        runtime_change_reason_codes: ["scope_changed"],
        governance_change_reason_codes: ["governance_changed"],
        denial_audit_reason_codes: ["policy_denied"],
        derived_state_reason_codes: [],
        extensions: %{}
      },
      extensions: %{}
    }
  end

  defp store_local_dir(case_name) do
    Path.join(
      System.tmp_dir!(),
      "stack_lab_semantic_host_store_local_#{case_name}_#{System.unique_integer([:positive])}"
    )
  end

  defp runtime_context(env) do
    {:ok, scope} =
      ScopeObjects.host_scope(%{
        scope_id: "workspace/main",
        session_id: env.session_id,
        tenant_id: "tenant-stack-lab",
        actor_id: "actor-stack-lab",
        environment: "dev",
        metadata: %{workspace_root: "/workspace/main"}
      })

    runtime_opts =
      CitadelAdapter.runtime_opts(
        request_submission_opts: [
          session_directory: env.session_directory,
          policy_packs: [policy_pack()],
          lookup_session: fn session_id ->
            if session_id == env.session_id do
              {:ok, env.session_server}
            else
              {:error, :not_found}
            end
          end
        ]
      )

    {scope, runtime_opts}
  end

  defp submit_turn(scope, runtime_opts, idempotency_key, opts \\ []) do
    ChatSurface.submit_turn(
      scope,
      "compile the workspace",
      idempotency_key: idempotency_key,
      domain_module: Citadel.DomainSurface.Examples.ProvingGround,
      route_sources: [Citadel.DomainSurface.Examples.ProvingGround.Routes.CompileWorkspace],
      kernel_runtime: {CitadelAdapter, runtime_opts},
      workspace_root: "/workspace/main",
      trace_id: Keyword.get(opts, :trace_id, RoundtripRuntime.trace_id(idempotency_key))
    )
  end

  defp await_invocation_request! do
    receive do
      {:invocation_request, request, attempt_entry} -> {request, attempt_entry}
    after
      2_000 ->
        raise "timed out waiting for semantic host invocation request"
    end
  end

  defp refute_invocation_request! do
    receive do
      {:invocation_request, request, attempt_entry} ->
        raise "unexpected second semantic host invocation request: #{inspect({request, attempt_entry})}"
    after
      100 ->
        :ok
    end
  end

  defp await_transport_rejection! do
    receive do
      {:stack_lab_brain_ingress_result, %{result: :rejected} = payload} ->
        %{rejection: payload.rejection}
    after
      2_000 ->
        raise "timed out waiting for semantic host rejection result"
    end
  end

  defp duplicate_app_kit_result(result) do
    %{
      state: result.state,
      request_id: result.payload.accepted.request_id,
      manifest_id: result.payload.manifest_id,
      submission_status: result.payload.accepted.metadata[:submission_status]
    }
  end
end
