defmodule StackLab.CitadelSpineHarness.LowerFacts do
  @moduledoc false

  alias Jido.Integration.V2
  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.AuthorityAuditEnvelope
  alias Jido.Integration.V2.BrainInvocation
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.ExecutionGovernanceProjection.Compiler
  alias Jido.Integration.V2.LowerFacts
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.Application, as: StoreLocalApplication
  alias Jido.Integration.V2.StoreLocal.ArtifactStore
  alias Jido.Integration.V2.StoreLocal.AttemptStore
  alias Jido.Integration.V2.StoreLocal.EventStore
  alias Jido.Integration.V2.StoreLocal.RunStore
  alias Jido.Integration.V2.StoreLocal.Server, as: StoreLocalServer
  alias Jido.Integration.V2.StoreLocal.TestSupport, as: StoreLocalTestSupport
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.SubmissionIdentity
  alias Jido.Integration.V2.TenantScope
  alias Mezzanine.Audit.ExecutionLineage
  alias Mezzanine.IntegrationBridge
  alias Mezzanine.Intent.ReadIntent
  alias StackLab.AppEnvSandbox
  alias StackLab.CitadelSpineHarness.RoundtripRuntime
  alias StackLab.CitadelSpineHarness.RuntimeResourceOwner
  alias StackLab.CitadelSpineHarness.Timing

  @control_plane_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :target_store,
    :ingress_store
  ]
  @auth_keys [
    :credential_store,
    :lease_store,
    :connection_store,
    :install_store,
    :keyring,
    :refresh_handler,
    :external_secret_resolver
  ]
  @brain_ingress_keys [:submission_ledger]
  @store_local_keys [:storage_dir]
  @logical_workspace_ref "workspace://tenant-lower-facts/root"

  @spec run_case(
          :generic_readback
          | :authorized_mezzanine_readback
          | :unauthorized_mezzanine_readback
        ) :: {:ok, map()}
  def run_case(case_name)
      when case_name in [
             :generic_readback,
             :authorized_mezzanine_readback,
             :unauthorized_mezzanine_readback
           ] do
    with_store_local_case(fn ->
      token = Integer.to_string(System.unique_integer([:positive]))
      invocation = brain_invocation_fixture(token)

      {:ok, %SubmissionAcceptance{}, _gateway, _runtime_inputs} =
        V2.accept_brain_invocation(
          invocation,
          scope_resolver: __MODULE__.Resolver,
          scope_resolver_opts: [
            mapping: %{
              @logical_workspace_ref => RoundtripRuntime.workspace_root()
            }
          ]
        )

      run = run_fixture(token)
      attempt = attempt_fixture(run.run_id)
      events = event_fixtures(run.run_id, attempt.attempt_id, token)
      artifact = artifact_fixture(run.run_id, attempt.attempt_id, token)

      :ok = RunStore.put_run(run)
      :ok = AttemptStore.put_attempt(attempt)
      :ok = EventStore.append_events(events)
      :ok = ArtifactStore.put_artifact_ref(artifact)

      tenant_scope = tenant_scope(token)

      {:ok, fetched_receipt} =
        LowerFacts.fetch_submission_receipt(tenant_scope, invocation.submission_key)

      {:ok, fetched_run} = LowerFacts.fetch_run(tenant_scope, run.run_id)

      {:ok, [listed_attempt]} = LowerFacts.attempts(tenant_scope, run.run_id)
      {:ok, fetched_attempt} = LowerFacts.fetch_attempt(tenant_scope, attempt.attempt_id)

      {:ok, fetched_events} = LowerFacts.events(tenant_scope, run.run_id)

      {:ok, fetched_artifact} = LowerFacts.fetch_artifact(tenant_scope, artifact.artifact_id)
      {:ok, run_artifacts} = LowerFacts.run_artifacts(tenant_scope, run.run_id)

      case case_name do
        :generic_readback ->
          {:ok,
           %{
             case: :generic_readback,
             receipt: %{
               submission_key: fetched_receipt.submission_key,
               submission_receipt_ref: fetched_receipt.submission_receipt_ref,
               status: fetched_receipt.status
             },
             run: %{
               run_id: fetched_run.run_id,
               capability_id: fetched_run.capability_id,
               status: fetched_run.status
             },
             attempt: %{
               listed_attempt_id: listed_attempt.attempt_id,
               fetched_attempt_id: fetched_attempt.attempt_id,
               status: fetched_attempt.status
             },
             events: Enum.map(fetched_events, & &1.type),
             artifact: %{
               artifact_id: fetched_artifact.artifact_id,
               run_artifact_ids: Enum.map(run_artifacts, & &1.artifact_id)
             }
           }}

        :authorized_mezzanine_readback ->
          authorized_mezzanine_readback_result(token, fetched_run, attempt, artifact)

        :unauthorized_mezzanine_readback ->
          unauthorized_mezzanine_readback_result(token, fetched_run, attempt, artifact)
      end
    end)
  end

  defp authorized_mezzanine_readback_result(
         token,
         %Run{} = run,
         %Attempt{} = attempt,
         %ArtifactRef{} = artifact
       ) do
    lineage = execution_lineage_fixture(token, run, attempt, artifact)

    intent =
      ReadIntent.new!(%{
        intent_id: "lower-facts-mezzanine-read-#{token}",
        read_type: :lower_fact,
        subject: %{
          actor_id: "actor-lower-facts",
          tenant_id: "tenant-lower-facts",
          installation_id: lineage.installation_id,
          execution_id: lineage.execution_id
        },
        query: %{operation: :fetch_run}
      })

    assert_lineage_lookup =
      fn execution_id ->
        if execution_id == lineage.execution_id do
          {:ok, lineage}
        else
          {:error, :not_found}
        end
      end

    with {:ok, result} <-
           IntegrationBridge.dispatch_read(intent,
             lower_facts: LowerFacts,
             fetch_lineage: assert_lineage_lookup
           ) do
      {:ok,
       %{
         case: :authorized_mezzanine_readback,
         operation: result.operation,
         source: result.source,
         staleness_class: result.staleness_class,
         operator_actionable?: result.operator_actionable?,
         lineage: result.lineage,
         run: %{
           run_id: result.result.run_id,
           capability_id: result.result.capability_id,
           status: result.result.status
         }
       }}
    end
  end

  defp unauthorized_mezzanine_readback_result(
         token,
         %Run{} = run,
         %Attempt{} = attempt,
         %ArtifactRef{} = artifact
       ) do
    lineage = execution_lineage_fixture(token, run, attempt, artifact)

    intent =
      ReadIntent.new!(%{
        intent_id: "lower-facts-mezzanine-read-denied-#{token}",
        read_type: :lower_fact,
        subject: %{
          actor_id: "actor-lower-facts",
          tenant_id: "tenant-lower-facts",
          installation_id: "inst-other",
          execution_id: lineage.execution_id
        },
        query: %{operation: :fetch_run}
      })

    fetch_lineage = fn
      execution_id when execution_id == lineage.execution_id -> {:ok, lineage}
      _execution_id -> {:error, :not_found}
    end

    case IntegrationBridge.dispatch_read(intent,
           lower_facts: LowerFacts,
           fetch_lineage: fetch_lineage
         ) do
      {:error, :unauthorized_lower_read} ->
        {:ok,
         %{
           case: :unauthorized_mezzanine_readback,
           error: :unauthorized_lower_read
         }}

      other ->
        {:error, {:unexpected_mezzanine_read_result, other}}
    end
  end

  defmodule Resolver do
    @moduledoc false

    @behaviour Jido.Integration.V2.BrainIngress.ScopeResolver

    @impl true
    def resolve(logical_workspace_ref, file_scope_ref, opts) do
      mapping = Keyword.get(opts, :mapping, %{})

      with {:ok, workspace_root} <- fetch(mapping, logical_workspace_ref),
           {:ok, file_scope} <- fetch(mapping, file_scope_ref) do
        {:ok, %{workspace_root: workspace_root, file_scope: file_scope}}
      end
    end

    defp fetch(_mapping, nil), do: {:ok, nil}

    defp fetch(mapping, value) do
      case Map.fetch(mapping, value) do
        {:ok, resolved} -> {:ok, resolved}
        :error -> {:error, {:scope_unresolvable, value}}
      end
    end
  end

  defp with_store_local_case(fun) when is_function(fun, 0) do
    RuntimeResourceOwner.transaction(fn ->
      previous_env = snapshot_env()
      storage_dir = StoreLocalTestSupport.tmp_dir!()

      try do
        :ok = configure_store_local!(storage_dir)
        :ok = reset_control_plane_if_started()
        fun.()
      after
        stop_store_local()
        restore_env(previous_env)
        StoreLocalTestSupport.cleanup!(storage_dir)
      end
    end)
  end

  defp configure_store_local!(storage_dir) do
    stop_store_local()
    File.rm_rf!(storage_dir)
    File.mkdir_p!(storage_dir)
    :ok = StoreLocal.configure_defaults!(storage_dir: storage_dir)
    :ok = ensure_store_local_started!()
    :ok = StoreLocal.reset!()
  end

  defp reset_control_plane_if_started do
    if Process.whereis(Jido.Integration.V2.ControlPlane.Registry) do
      ControlPlane.reset!()
    else
      :ok
    end
  end

  defp stop_store_local do
    _ = Application.stop(:jido_integration_v2_store_local)
    stop_named_process(StoreLocalServer)
    stop_named_process(StoreLocalApplication)
    :ok
  end

  defp ensure_store_local_started! do
    case Application.ensure_all_started(:jido_integration_v2_store_local) do
      {:ok, _apps} ->
        wait_for_store_local_server!()

      {:error, {:jido_integration_v2_store_local, {:already_started, pid}}} ->
        stop_process(pid)
        ensure_store_local_started!()

      {:error, {:already_started, pid}} ->
        stop_process(pid)
        ensure_store_local_started!()

      {:error, reason} ->
        raise "unable to start store_local application: #{inspect(reason)}"
    end
  end

  defp wait_for_store_local_server!(attempts \\ 40)
  defp wait_for_store_local_server!(0), do: raise("store_local server did not start")

  defp wait_for_store_local_server!(attempts) do
    case Process.whereis(StoreLocalServer) do
      nil ->
        Timing.retry_delay(:store_local_server_ready, 50)
        wait_for_store_local_server!(attempts - 1)

      _pid ->
        :ok
    end
  end

  defp stop_named_process(name) do
    case Process.whereis(name) do
      nil -> :ok
      pid -> stop_process(pid)
    end
  end

  defp stop_process(pid) when is_pid(pid) do
    monitor_ref = Process.monitor(pid)

    if Process.alive?(pid) do
      try do
        GenServer.stop(pid, :normal, 5_000)
      catch
        :exit, _reason ->
          Process.exit(pid, :shutdown)
      end
    end

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
        :ok
    after
      5_000 ->
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> :ok
        end
    end
  end

  defp snapshot_env do
    %{
      control_plane: snapshot_keys(:jido_integration_v2_control_plane, @control_plane_keys),
      auth: snapshot_keys(:jido_integration_v2_auth, @auth_keys),
      brain_ingress: snapshot_keys(:jido_integration_v2_brain_ingress, @brain_ingress_keys),
      store_local: snapshot_keys(:jido_integration_v2_store_local, @store_local_keys)
    }
  end

  defp restore_env(previous_env) do
    restore_keys(:jido_integration_v2_control_plane, previous_env.control_plane)
    restore_keys(:jido_integration_v2_auth, previous_env.auth)
    restore_keys(:jido_integration_v2_brain_ingress, previous_env.brain_ingress)
    restore_keys(:jido_integration_v2_store_local, previous_env.store_local)
    :ok
  end

  defp snapshot_keys(app, keys) do
    keys
    |> Enum.map(&{app, &1})
    |> AppEnvSandbox.snapshot()
  end

  defp restore_keys(_app, snapshot), do: AppEnvSandbox.restore(snapshot)

  defp brain_invocation_fixture(token) do
    identity =
      SubmissionIdentity.new!(%{
        submission_family: :invocation,
        tenant_id: "tenant-lower-facts",
        session_id: "session-#{token}",
        request_id: "request-#{token}",
        invocation_request_id: "invoke-#{token}",
        causal_group_id: "cg-#{token}",
        target_id: "target-#{token}",
        target_kind: "cli",
        selected_step_id: "step-#{token}",
        authority_decision_id: "decision-#{token}",
        execution_governance_id: "governance-#{token}",
        execution_intent_family: "process"
      })

    authority_payload =
      AuthorityAuditEnvelope.new!(%{
        contract_version: "v1",
        decision_id: "decision-#{token}",
        tenant_id: "tenant-lower-facts",
        request_id: "request-#{token}",
        policy_version: "policy-lower-facts",
        boundary_class: "hazmat",
        trust_profile: "trusted_operator",
        approval_profile: "manual",
        egress_profile: "restricted",
        workspace_profile: "workspace_attached",
        resource_profile: "balanced",
        decision_hash: String.duplicate("f", 64),
        extensions: %{}
      })

    governance_payload =
      ExecutionGovernanceProjection.new!(%{
        contract_version: "v1",
        execution_governance_id: "governance-#{token}",
        authority_ref: %{
          "decision_id" => "decision-#{token}",
          "policy_version" => "policy-lower-facts",
          "decision_hash" => String.duplicate("f", 64)
        },
        sandbox: %{
          "level" => "strict",
          "egress" => "restricted",
          "approvals" => "manual",
          "acceptable_attestation" => ["local-erlexec-weak"],
          "allowed_tools" => ["bash", "git"],
          "file_scope_ref" => @logical_workspace_ref,
          "file_scope_hint" => RoundtripRuntime.workspace_root()
        },
        boundary: %{
          "boundary_class" => "hazmat",
          "trust_profile" => "trusted_operator",
          "requested_attach_mode" => "attach_if_exists",
          "requested_ttl_ms" => 60_000
        },
        topology: %{
          "topology_intent_id" => "topology-#{token}",
          "session_mode" => "attached",
          "coordination_mode" => "single_target",
          "topology_epoch" => 1,
          "routing_hints" => %{
            "runtime_driver" => "asm",
            "runtime_provider" => "codex"
          }
        },
        workspace: %{
          "workspace_profile" => "workspace_attached",
          "logical_workspace_ref" => @logical_workspace_ref,
          "mutability" => "read_write"
        },
        resources: %{
          "resource_profile" => "balanced",
          "cpu_class" => "medium",
          "memory_class" => "medium",
          "wall_clock_budget_ms" => 300_000
        },
        placement: %{
          "execution_family" => "process",
          "placement_intent" => "host_local",
          "target_kind" => "cli",
          "node_affinity" => "same_node"
        },
        operations: %{
          "allowed_operations" => ["shell.exec"],
          "effect_classes" => ["filesystem", "process"]
        }
      })

    compiled_projection = Compiler.compile!(governance_payload)

    BrainInvocation.new!(%{
      submission_identity: identity,
      request_id: "request-#{token}",
      session_id: "session-#{token}",
      tenant_id: "tenant-lower-facts",
      trace_id: RoundtripRuntime.trace_id("lower-facts:#{token}"),
      actor_id: "actor-lower-facts",
      target_id: "target-#{token}",
      target_kind: "cli",
      runtime_class: :direct,
      allowed_operations: ["shell.exec"],
      authority_payload: authority_payload,
      execution_governance_payload: governance_payload,
      gateway_request: compiled_projection.gateway_request,
      runtime_request: compiled_projection.runtime_request,
      boundary_request: compiled_projection.boundary_request,
      execution_intent_family: "process",
      execution_intent: %{"argv" => ["echo", "lower-facts"]},
      extensions: %{"submission_dedupe_key" => "lower-facts:#{token}"}
    })
  end

  defp run_fixture(token) do
    Run.new!(%{
      run_id: "run-lower-facts-#{token}",
      capability_id: "inference.execute",
      runtime_class: :direct,
      status: :completed,
      input: %{
        "prompt" => "Summarize the lower facts seam",
        "metadata" => %{
          "tenant_id" => "tenant-lower-facts",
          "installation_id" => "inst-lower-facts",
          "trace_id" => "trace-#{token}"
        }
      },
      credential_ref:
        CredentialRef.new!(%{
          id: "credential-ref-#{token}",
          subject: "tenant-lower-facts"
        }),
      result: %{"status" => "ok"},
      artifact_refs: []
    })
  end

  defp tenant_scope(token) do
    TenantScope.new!(
      tenant_id: "tenant-lower-facts",
      installation_id: "inst-lower-facts",
      actor_ref: %{id: "actor-lower-facts"},
      trace_id: "trace-#{token}",
      authorized_at: DateTime.utc_now()
    )
  end

  defp attempt_fixture(run_id) do
    Attempt.new!(%{
      run_id: run_id,
      attempt: 1,
      runtime_class: :direct,
      status: :completed,
      output: %{
        "inference_result" => %{
          "status" => "ok",
          "content" => "Lower facts proof is alive."
        }
      }
    })
  end

  defp event_fixtures(run_id, attempt_id, token) do
    [
      Event.new!(%{
        run_id: run_id,
        attempt_id: attempt_id,
        seq: 0,
        type: "inference.request_admitted",
        payload: %{"request_id" => "request-#{token}"}
      }),
      Event.new!(%{
        run_id: run_id,
        attempt_id: attempt_id,
        seq: 1,
        type: "inference.attempt_started",
        payload: %{"attempt_id" => attempt_id}
      }),
      Event.new!(%{
        run_id: run_id,
        attempt_id: attempt_id,
        seq: 2,
        type: "inference.attempt_completed",
        payload: %{"status" => "ok"}
      })
    ]
  end

  defp artifact_fixture(run_id, attempt_id, token) do
    checksum = "sha256:" <> String.duplicate("c", 64)

    ArtifactRef.new!(%{
      artifact_id: "artifact-lower-facts-#{token}",
      run_id: run_id,
      attempt_id: attempt_id,
      artifact_type: :tool_output,
      transport_mode: :object_store,
      checksum: checksum,
      size_bytes: 64,
      payload_ref: %{
        store: "s3",
        key: "lower-facts/#{run_id}/#{attempt_id}",
        ttl_s: 86_400,
        access_control: :run_scoped,
        checksum: checksum,
        size_bytes: 64
      },
      retention_class: "review_output",
      redaction_status: :clear,
      metadata: %{
        surface: "lower_facts",
        producer: "stack_lab"
      }
    })
  end

  defp execution_lineage_fixture(
         token,
         %Run{} = run,
         %Attempt{} = attempt,
         %ArtifactRef{} = artifact
       ) do
    ExecutionLineage.new!(%{
      trace_id: "trace-#{token}",
      tenant_id: "tenant-lower-facts",
      installation_id: "inst-lower-facts",
      subject_id: "subject-#{token}",
      execution_id: "execution-#{token}",
      ji_submission_key: "submission-key-#{token}",
      lower_run_id: run.run_id,
      lower_attempt_id: attempt.attempt_id,
      artifact_refs: [artifact.artifact_id]
    })
  end
end
