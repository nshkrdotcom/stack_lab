defmodule StackLab.CitadelSpineHarness.RoundtripRuntime do
  @moduledoc false

  alias Citadel.ActionOutboxEntry
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1
  alias Citadel.BackoffPolicy
  alias Citadel.BoundaryIntent
  alias Citadel.ExecutionGovernanceCompiler
  alias Citadel.HostIngress.InvocationPayload
  alias Citadel.InvocationBridge
  alias Citadel.InvocationRequest.V2, as: InvocationRequestV2
  alias Citadel.JidoIntegrationBridge.InvocationDownstream
  alias Citadel.Kernel.BoundaryLeaseTracker
  alias Citadel.Kernel.KernelSnapshot
  alias Citadel.Kernel.ServiceCatalog
  alias Citadel.Kernel.SessionDirectory
  alias Citadel.Kernel.SessionServer
  alias Citadel.Kernel.SignalIngress
  alias Citadel.LocalAction
  alias Citadel.SessionOutbox
  alias Citadel.StalenessRequirements
  alias Citadel.TopologyIntent

  defmodule TestSignalSource do
    @moduledoc false
    @behaviour Citadel.Ports.SignalSource

    @impl true
    def normalize_signal(observation), do: {:ok, observation}
  end

  @logical_workspace_ref "workspace://stack_lab/root"

  @spec start_runtime_env(atom(), keyword()) :: map()
  def start_runtime_env(case_name, opts \\ []) do
    kernel_snapshot_name = unique_name(:kernel_snapshot)
    session_directory_name = unique_name(:session_directory)
    service_catalog_name = unique_name(:service_catalog)
    boundary_tracker_name = unique_name(:boundary_tracker)
    invocation_supervisor_name = unique_name(:invocation_supervisor)
    projection_supervisor_name = unique_name(:projection_supervisor)
    local_supervisor_name = unique_name(:local_supervisor)
    signal_ingress_name = unique_name(:signal_ingress)
    session_server_name = unique_name(:session_server)

    {:ok, kernel_snapshot_pid} =
      KernelSnapshot.start_link(
        name: kernel_snapshot_name,
        policy_version: "policy-stack-lab",
        policy_epoch: 1
      )

    Process.unlink(kernel_snapshot_pid)

    {:ok, session_directory_pid} =
      SessionDirectory.start_link(
        name: session_directory_name,
        kernel_snapshot: kernel_snapshot_name
      )

    Process.unlink(session_directory_pid)

    {:ok, service_catalog_pid} =
      ServiceCatalog.start_link(
        name: service_catalog_name,
        kernel_snapshot: kernel_snapshot_name
      )

    Process.unlink(service_catalog_pid)

    {:ok, boundary_tracker_pid} =
      BoundaryLeaseTracker.start_link(
        name: boundary_tracker_name,
        kernel_snapshot: kernel_snapshot_name
      )

    Process.unlink(boundary_tracker_pid)

    {:ok, invocation_supervisor_pid} =
      Task.Supervisor.start_link(name: invocation_supervisor_name, max_children: 4)

    Process.unlink(invocation_supervisor_pid)

    {:ok, projection_supervisor_pid} =
      Task.Supervisor.start_link(name: projection_supervisor_name, max_children: 4)

    Process.unlink(projection_supervisor_pid)

    {:ok, local_supervisor_pid} =
      Task.Supervisor.start_link(name: local_supervisor_name, max_children: 4)

    Process.unlink(local_supervisor_pid)

    {:ok, signal_ingress_pid} =
      SignalIngress.start_link(
        name: signal_ingress_name,
        session_directory: session_directory_name,
        signal_source: TestSignalSource
      )

    Process.unlink(signal_ingress_pid)

    session_id = "stack-lab-session-#{case_name}"

    Code.ensure_loaded!(InvocationDownstream)
    bridge = InvocationBridge.new!(downstream: InvocationDownstream)

    invocation_handler =
      Keyword.get_lazy(opts, :invocation_handler, fn ->
        request =
          invocation_request(
            session_id,
            "request-single-node",
            "invoke-single-node",
            "step-single-node"
          )

        invocation_handler(request, bridge)
      end)

    {:ok, session_server_pid} =
      SessionServer.start_link(
        name: session_server_name,
        session_id: session_id,
        session_directory: session_directory_name,
        kernel_snapshot: kernel_snapshot_name,
        boundary_lease_tracker: boundary_tracker_name,
        service_catalog: service_catalog_name,
        signal_ingress: signal_ingress_name,
        invocation_supervisor: invocation_supervisor_name,
        projection_supervisor: projection_supervisor_name,
        local_supervisor: local_supervisor_name,
        invocation_handler: invocation_handler
      )

    Process.unlink(session_server_pid)

    %{
      kernel_snapshot: kernel_snapshot_name,
      kernel_snapshot_pid: kernel_snapshot_pid,
      session_directory: session_directory_name,
      session_directory_pid: session_directory_pid,
      service_catalog: service_catalog_name,
      service_catalog_pid: service_catalog_pid,
      boundary_tracker: boundary_tracker_name,
      boundary_tracker_pid: boundary_tracker_pid,
      signal_ingress: signal_ingress_name,
      signal_ingress_pid: signal_ingress_pid,
      invocation_supervisor: invocation_supervisor_name,
      invocation_supervisor_pid: invocation_supervisor_pid,
      projection_supervisor: projection_supervisor_name,
      projection_supervisor_pid: projection_supervisor_pid,
      local_supervisor: local_supervisor_name,
      local_supervisor_pid: local_supervisor_pid,
      session_server: session_server_name,
      session_server_pid: session_server_pid,
      session_id: session_id,
      snapshot: KernelSnapshot.current_snapshot(kernel_snapshot_name)
    }
  end

  @spec shutdown_runtime_env(map()) :: :ok
  def shutdown_runtime_env(env) when is_map(env) do
    shutdown_pid(env.session_server_pid)
    shutdown_pid(env.signal_ingress_pid)
    shutdown_pid(env.local_supervisor_pid)
    shutdown_pid(env.projection_supervisor_pid)
    shutdown_pid(env.invocation_supervisor_pid)
    shutdown_pid(env.boundary_tracker_pid)
    shutdown_pid(env.service_catalog_pid)
    shutdown_pid(env.session_directory_pid)
    shutdown_pid(env.kernel_snapshot_pid)
  end

  @spec outbox_entry(String.t(), String.t(), map()) :: ActionOutboxEntry.t()
  def outbox_entry(entry_id, request_id, snapshot) do
    ActionOutboxEntry.new!(%{
      schema_version: 1,
      entry_id: entry_id,
      causal_group_id: "group/#{request_id}",
      action:
        LocalAction.new!(%{
          action_kind: "submit_invocation",
          payload: %{"request_id" => request_id},
          extensions: %{}
        }),
      inserted_at: DateTime.utc_now(),
      replay_status: :pending,
      attempt_count: 0,
      max_attempts: 3,
      backoff_policy:
        BackoffPolicy.new!(%{
          strategy: :fixed,
          base_delay_ms: 10,
          max_delay_ms: 10,
          linear_step_ms: nil,
          multiplier: nil,
          jitter_mode: :none,
          jitter_window_ms: 0,
          extensions: %{}
        }),
      next_attempt_at: nil,
      last_error_code: nil,
      dead_letter_reason: nil,
      ordering_mode: :strict,
      staleness_mode: :requires_check,
      staleness_requirements:
        StalenessRequirements.new!(%{
          snapshot_seq: snapshot.snapshot_seq,
          policy_epoch: snapshot.policy_epoch,
          topology_epoch: nil,
          scope_catalog_epoch: nil,
          service_admission_epoch: nil,
          project_binding_epoch: nil,
          boundary_epoch: nil,
          required_binding_id: nil,
          required_boundary_ref: nil,
          extensions: %{}
        }),
      extensions: %{}
    })
  end

  @spec submit_outbox_entry!(GenServer.server(), ActionOutboxEntry.t()) :: :ok
  def submit_outbox_entry!(session_server, %ActionOutboxEntry{} = entry) do
    current_state = SessionServer.snapshot(session_server)
    updated_outbox = SessionOutbox.put_entry!(current_state.outbox, entry)

    {:ok, _session_state} =
      SessionServer.commit_transition(
        session_server,
        %{outbox: updated_outbox},
        meaningful_activity?: true
      )

    :ok
  end

  @spec wait_for_entry!(
          GenServer.server(),
          String.t(),
          (ActionOutboxEntry.t() -> boolean()),
          non_neg_integer()
        ) ::
          map()
  def wait_for_entry!(session_directory, entry_id, predicate, attempts \\ 40)

  def wait_for_entry!(session_directory, entry_id, predicate, attempts) when attempts > 0 do
    case SessionDirectory.resolve_outbox_entry(session_directory, entry_id) do
      {:ok, %{entry: entry} = resolved} ->
        if predicate.(entry) do
          resolved
        else
          Process.sleep(25)
          wait_for_entry!(session_directory, entry_id, predicate, attempts - 1)
        end

      _other ->
        Process.sleep(25)
        wait_for_entry!(session_directory, entry_id, predicate, attempts - 1)
    end
  end

  def wait_for_entry!(_session_directory, entry_id, _predicate, 0) do
    raise "timed out waiting for persisted entry #{inspect(entry_id)}"
  end

  @spec workspace_root() :: String.t()
  def workspace_root do
    path = Path.join(System.tmp_dir!(), "stack_lab_citadel_spine_workspace")
    File.mkdir_p!(path)
    path
  end

  @spec flush_transport_messages() :: :ok
  def flush_transport_messages do
    receive do
      {:stack_lab_brain_ingress_result, _payload} -> flush_transport_messages()
    after
      0 -> :ok
    end
  end

  defp invocation_handler(request, bridge) do
    fn _payload, attempt_entry ->
      case InvocationBridge.submit_invocation(bridge, request, attempt_entry) do
        {:accepted, acceptance, _bridge} -> {:accepted, acceptance}
        {:rejected, rejection, _bridge} -> {:rejected, rejection}
        {:error, reason, _bridge} -> {:error, reason}
      end
    end
  end

  @spec host_ingress_invocation_handler(Citadel.InvocationBridge.t(), pid() | nil) ::
          (map(), ActionOutboxEntry.t() ->
             {:accepted, term()} | {:rejected, term()} | {:error, term()})
  def host_ingress_invocation_handler(bridge, listener \\ nil) do
    fn payload, attempt_entry ->
      request = InvocationPayload.decode!(payload)

      if is_pid(listener) do
        send(listener, {:invocation_request, request, attempt_entry})
      end

      case InvocationBridge.submit_invocation(bridge, request, attempt_entry) do
        {:accepted, acceptance, _bridge} -> {:accepted, acceptance}
        {:rejected, rejection, _bridge} -> {:rejected, rejection}
        {:error, reason, _bridge} -> {:error, reason}
      end
    end
  end

  defp invocation_request(session_id, request_id, invocation_request_id, selected_step_id) do
    authority_packet = authority_packet(request_id)
    boundary_intent = boundary_intent()
    topology_intent = topology_intent()

    InvocationRequestV2.new!(%{
      schema_version: 2,
      invocation_request_id: invocation_request_id,
      request_id: request_id,
      session_id: session_id,
      tenant_id: "tenant-stack-lab",
      trace_id: "trace/#{request_id}",
      actor_id: "actor-stack-lab",
      target_id: "target-stack-lab",
      target_kind: "cli",
      selected_step_id: selected_step_id,
      allowed_operations: ["shell.exec"],
      authority_packet: authority_packet,
      boundary_intent: boundary_intent,
      topology_intent: topology_intent,
      execution_governance:
        ExecutionGovernanceCompiler.compile!(
          authority_packet,
          boundary_intent,
          topology_intent,
          execution_governance_id: "execgov/#{request_id}",
          sandbox_level: "strict",
          sandbox_egress: "restricted",
          sandbox_approvals: "manual",
          allowed_tools: ["bash", "git"],
          file_scope_ref: @logical_workspace_ref,
          file_scope_hint: workspace_root(),
          logical_workspace_ref: @logical_workspace_ref,
          workspace_mutability: "read_write",
          execution_family: "process",
          placement_intent: "host_local",
          target_kind: "cli",
          allowed_operations: ["shell.exec"],
          effect_classes: ["filesystem", "process"]
        ),
      extensions: %{
        "citadel" => %{
          "execution_intent_family" => "process",
          "execution_intent" => %{
            "contract_version" => "v1",
            "command" => "echo",
            "args" => ["stack-lab"],
            "working_directory" => workspace_root(),
            "environment" => %{},
            "stdin" => nil,
            "extensions" => %{}
          }
        }
      }
    })
  end

  defp authority_packet(request_id) do
    AuthorityDecisionV1.new!(%{
      contract_version: "v1",
      decision_id: "decision/#{request_id}",
      tenant_id: "tenant-stack-lab",
      request_id: request_id,
      policy_version: "policy-stack-lab",
      boundary_class: "hazmat",
      trust_profile: "trusted_operator",
      approval_profile: "manual",
      egress_profile: "restricted",
      workspace_profile: "workspace_attached",
      resource_profile: "balanced",
      decision_hash: String.duplicate("a", 64),
      extensions: %{}
    })
  end

  defp boundary_intent do
    BoundaryIntent.new!(%{
      boundary_class: "hazmat",
      trust_profile: "trusted_operator",
      workspace_profile: "workspace_attached",
      resource_profile: "balanced",
      requested_attach_mode: "reuse_existing",
      requested_ttl_ms: 60_000,
      extensions: %{}
    })
  end

  defp topology_intent do
    TopologyIntent.new!(%{
      topology_intent_id: "topology-stack-lab",
      session_mode: "attached",
      routing_hints: %{
        "execution_intent_family" => "process",
        "execution_intent" => %{
          "contract_version" => "v1",
          "command" => "echo",
          "args" => ["stack-lab"],
          "working_directory" => workspace_root(),
          "environment" => %{},
          "stdin" => nil,
          "extensions" => %{}
        },
        "downstream_scope" => "process:workspace"
      },
      coordination_mode: "single_target",
      topology_epoch: 1,
      extensions: %{}
    })
  end

  defp shutdown_pid(nil), do: :ok

  defp shutdown_pid(pid) when is_pid(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :shutdown)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      500 -> :ok
    end
  end

  defp unique_name(prefix) do
    :"#{prefix}_#{System.unique_integer([:positive])}"
  end
end
