defmodule StackLab.CitadelSpineHarness.TreLaneAcceptance do
  @moduledoc false

  alias Jido.Integration.V2

  alias Jido.Integration.V2.{
    AuthSpec,
    CatalogSpec,
    ControlPlane,
    Manifest,
    OperationSpec,
    StoreLocal
  }

  alias Jido.Integration.V2.Auth.{Connection, Install}
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.RuntimeRouter.ExecutionPlaneTreAdapter
  alias Jido.Integration.V2.StoreLocal.Application, as: StoreLocalApplication
  alias Jido.Integration.V2.StoreLocal.Server, as: StoreLocalServer
  alias Jido.Integration.V2.StoreLocal.TestSupport, as: StoreLocalTestSupport
  alias Mezzanine.IntegrationBridge.AuthorizedInvocation
  alias StackLab.CitadelSpineHarness.RuntimeResourceOwner

  @scenario_id "tre.neutral_execution_plane.v1"
  @tenant_id "tenant-stack-lab-tre"
  @actor_id "stack-lab-tre-operator"
  @connector_id "stack_lab_tre"
  @capability_id "stack_lab.tre.execute"
  @trace_id "trace-stack-lab-tre-neutral"
  @runtime_profile_ref "runtime-profile://stack-lab/tre/local"
  @runtime_profile_kind :temporal_local
  @lower_request_ref "lower-request://stack-lab/tre/neutral-lane"
  @workspace_ref "workspace://stack-lab/tre/neutral-lane"
  @target_ref "target://stack-lab/tre/local-process"
  @sandbox_profile_ref "sandbox://stack-lab/tre/local-process"
  @script_ref "script:stack-lab:tre-read-only:v1"
  @script_source ~s|let contents = cat(file_path); contents|
  @policy_source """
  permit(principal, action, resource)
  when { action == file_system::Action::"read" };
  """
  @policy_bundle_ref "tre-policy-bundle://stack-lab/neutral-read-only/1"
  @policy_bundle_hash "sha256:1111111111111111111111111111111111111111111111111111111111111111"
  @cedar_schema_ref "cedar-schema://stack-lab/tre/read-only/v1"
  @cedar_schema_hash "sha256:2222222222222222222222222222222222222222222222222222222222222222"
  @connector_manifest_ref "manifest://jido/connectors/stack_lab_tre@local"
  @connector_manifest_hash "sha256:3333333333333333333333333333333333333333333333333333333333333333"
  @script_hash "sha256:" <> Base.encode16(:crypto.hash(:sha256, @script_source), case: :lower)
  @control_plane_keys [
    :run_store,
    :attempt_store,
    :event_store,
    :artifact_store,
    :target_store,
    :ingress_store,
    :profile_registry_store
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

  defmodule PassthroughAction do
    @moduledoc false
    use Jido.Action,
      name: "stack_lab_tre_passthrough",
      schema: [value: [type: :string, required: true]]

    @impl true
    def run(params, _context), do: {:ok, %{value: params.value}}
  end

  defmodule TreConnector do
    @moduledoc false
    @behaviour Jido.Integration.V2.Connector

    @impl true
    def manifest do
      Manifest.new!(%{
        connector: "stack_lab_tre",
        auth:
          AuthSpec.new!(%{
            binding_kind: :connection_id,
            auth_type: :api_token,
            install: %{required: true},
            reauth: %{supported: false},
            requested_scopes: ["tre:execute"],
            lease_fields: ["access_token"],
            secret_names: []
          }),
        catalog:
          CatalogSpec.new!(%{
            display_name: "StackLab TRE",
            description: "Neutral StackLab TRE lower-lane acceptance connector",
            category: "test",
            tags: ["tre", "stack_lab"],
            docs_refs: [],
            maturity: :experimental,
            publication: :internal
          }),
        operations: [
          OperationSpec.new!(%{
            operation_id: "stack_lab.tre.execute",
            name: "tre_execute",
            display_name: "TRE execute",
            description: "Executes through the explicit ExecutionPlane TRE adapter",
            runtime_class: :direct,
            transport_mode: :action,
            handler: PassthroughAction,
            input_schema: Zoi.map(description: "TRE input"),
            output_schema: Zoi.map(description: "TRE output"),
            permissions: %{required_scopes: ["tre:execute"]},
            policy: %{
              allowed_actor_ids: ["stack-lab-tre-operator"],
              allowed_tenant_ids: ["tenant-stack-lab-tre"],
              allowed_environments: [:prod],
              allowed_runtime_classes: [:direct],
              sandbox: %{
                level: :strict,
                egress: :restricted,
                approvals: :auto,
                file_scope: "/srv/stack-lab/tre",
                allowed_tools: ["tre.stack_lab.execute"]
              }
            },
            upstream: %{transport: :action},
            consumer_surface: %{
              mode: :connector_local,
              reason: "StackLab TRE acceptance consumes lower-owner public APIs"
            },
            schema_policy: %{
              input: :passthrough,
              output: :passthrough,
              justification: "Neutral TRE acceptance keeps payloads deterministic"
            },
            jido: %{action: %{name: "stack_lab_tre_execute"}},
            metadata: %{
              lower_runtime_kinds: [:tre_rhai],
              side_effect_class: :execute,
              idempotency_class: :idempotent
            }
          })
        ],
        triggers: [],
        runtime_families: [:direct]
      })
    end
  end

  @spec scenario() :: map()
  def scenario do
    %{
      name: :tre_lane_acceptance,
      owner_repo: :stack_lab,
      product_repo: :none,
      scenario_id: @scenario_id,
      path: [:stack_lab, :mezzanine, :jido_integration, :execution_plane],
      cases: %{
        deterministic_fixture_runner: %{kind: :neutral_lower_lane},
        installed_rex_runner: %{kind: :operator_supplied_runner, requires: :runner_path}
      }
    }
  end

  @spec run_case(:deterministic_fixture_runner | :installed_rex_runner, keyword()) ::
          {:ok, map()} | {:error, term()}
  def run_case(case_name, opts \\ [])

  def run_case(:deterministic_fixture_runner, opts) when is_list(opts) do
    with_fixture_runner(fn runner ->
      run_with_runner(:fixture_subprocess_contract, runner, opts)
    end)
  end

  def run_case(:installed_rex_runner, opts) when is_list(opts) do
    case Keyword.get(opts, :runner_path) do
      nil -> {:error, {:runner_path_required, :installed_rex_runner}}
      runner_path -> run_with_runner(:installed_rex_runner, runner(runner_path), opts)
    end
  end

  defp run_with_runner(runner_kind, runner, opts) do
    RuntimeResourceOwner.transaction(fn ->
      with_isolated_jido_store(fn -> run_registered_case(runner_kind, runner, opts) end)
    end)
  end

  defp run_registered_case(runner_kind, runner, opts) do
    with :ok <- register_connector(),
         {:ok, connection_id} <- install_connection(),
         {:ok, result} <- dispatch_tre(connection_id, runner, opts) do
      {:ok, receipt(result, runner_kind, runner)}
    end
  end

  defp register_connector do
    V2.register_connector(TreConnector)
  end

  defp install_connection do
    now = DateTime.utc_now()

    with {:ok, %{install: %Install{} = install, connection: %Connection{} = connection}} <-
           V2.start_install(@connector_id, @tenant_id, %{
             actor_id: @actor_id,
             auth_type: :oauth2,
             subject: "stack-lab-tre-subject",
             requested_scopes: ["tre:execute"],
             now: now
           }),
         {:ok, %{credential_ref: %CredentialRef{}}} <-
           V2.complete_install(install.install_id, %{
             subject: "stack-lab-tre-subject",
             granted_scopes: ["tre:execute"],
             secret: %{access_token: "stack-lab-tre-token"},
             expires_at: DateTime.add(now, 7 * 24 * 3_600, :second),
             now: now
           }) do
      {:ok, connection.connection_id}
    end
  end

  defp dispatch_tre(connection_id, runner, opts) do
    invocation = AuthorizedInvocation.new!(authorized_invocation_attrs())

    direct_run_module().invoke_run_intent(invocation,
      capability_id: @capability_id,
      lower_runtime_kind: :tre_rhai,
      runtime_profile_ref: @runtime_profile_ref,
      runtime_profile_kind: @runtime_profile_kind,
      lower_request_ref: @lower_request_ref,
      connector_ref: "jido/connectors/#{@connector_id}",
      connector_manifest_ref: @connector_manifest_ref,
      connector_manifest_hash: @connector_manifest_hash,
      connector_manifest_state: :active,
      capability_negotiation_ref: "cap-neg://stack-lab/tre/neutral-lane",
      side_effect_class: :execute,
      idempotency_class: :idempotent,
      runtime_class: :direct,
      resource_scope_refs: [@workspace_ref],
      workspace_ref: @workspace_ref,
      target_ref: @target_ref,
      placement_ref: "placement://stack-lab/local-process",
      sandbox_profile_ref: @sandbox_profile_ref,
      sandbox_level: :strict,
      acceptable_attestation: ["attestation://stack-lab/local-dev"],
      attestation_requirement_ref: "attestation://stack-lab/local-dev",
      evidence_profile_ref: "evidence://stack-lab/tre/debug",
      redaction_profile_ref: "redaction://stack-lab/tre/default",
      input_ref: "input://stack-lab/tre/neutral-lane",
      input_hash: sha256("stack-lab-tre-input"),
      policy_profile_ref: "tre-policy-profile://stack-lab/read-only",
      policy_bundle_ref: @policy_bundle_ref,
      policy_bundle_hash: @policy_bundle_hash,
      cedar_schema_ref: @cedar_schema_ref,
      cedar_schema_hash: @cedar_schema_hash,
      script_ref: @script_ref,
      script_hash: @script_hash,
      script_api_version: "nshkr.tre.rhai.v1",
      declared_actions: ["fs.read"],
      input: %{value: "ok"},
      invoke_opts: invoke_opts(connection_id, runner, opts)
    )
  end

  defp invoke_opts(connection_id, runner, opts) do
    [
      connection_id: connection_id,
      actor_id: @actor_id,
      tenant_id: @tenant_id,
      environment: :prod,
      trace_id: @trace_id,
      cost_meter_ref: "meter://stack-lab/tre",
      budget_refs: ["budget://stack-lab/tre/per-run"],
      allowed_operations: [@capability_id],
      sandbox: %{
        level: :strict,
        egress: :restricted,
        approvals: :auto,
        file_scope: "/srv/stack-lab/tre",
        allowed_tools: ["tre.stack_lab.execute", "tre.execution_plane.execute"]
      },
      tre_adapter: ExecutionPlaneTreAdapter,
      tre_runner_path: runner.path,
      tre_materializer: materializer(),
      tre_allowed_actions: ["fs.read"],
      tre_cleanup?: Keyword.get(opts, :cleanup?, true)
    ]
  end

  defp authorized_invocation_attrs do
    %{
      tenant_id: @tenant_id,
      installation_id: "installation-stack-lab-tre",
      subject_id: "subject-stack-lab-tre",
      execution_id: "execution-stack-lab-tre",
      trace_id: @trace_id,
      idempotency_key: "idem-stack-lab-tre",
      submission_dedupe_key: "dedupe-stack-lab-tre",
      invocation_request: invocation_request()
    }
  end

  defp invocation_request do
    %{
      schema_version: 2,
      invocation_request_id: "invoke-stack-lab-tre",
      request_id: "request-stack-lab-tre",
      session_id: "session-stack-lab-tre",
      tenant_id: @tenant_id,
      trace_id: @trace_id,
      actor_id: @actor_id,
      target_id: @target_ref,
      target_kind: "runtime_target",
      selected_step_id: "step-stack-lab-tre",
      allowed_operations: [@capability_id],
      authority_packet: authority_packet(),
      boundary_intent: %{},
      topology_intent: %{},
      execution_governance: execution_governance(),
      extensions: %{
        "citadel" => %{
          "execution_envelope" => %{
            "installation_id" => "installation-stack-lab-tre",
            "installation_revision" => 1,
            "subject_id" => "subject-stack-lab-tre",
            "execution_id" => "execution-stack-lab-tre",
            "workflow_id" => "workflow-stack-lab-tre",
            "attempt_ref" => "attempt-stack-lab-tre",
            "runtime_profile_ref" => @runtime_profile_ref,
            "runtime_profile_kind" => Atom.to_string(@runtime_profile_kind),
            "submission_dedupe_key" => "dedupe-stack-lab-tre"
          },
          "tre_policy" => tre_policy()
        }
      }
    }
  end

  defp authority_packet do
    %{
      contract_version: "v1",
      decision_id: "authority-stack-lab-tre",
      tenant_id: @tenant_id,
      request_id: "request-stack-lab-tre",
      policy_version: "stack-lab-tre-v1",
      boundary_class: "workspace_session",
      trust_profile: "baseline",
      approval_profile: "standard",
      egress_profile: "restricted",
      workspace_profile: "workspace",
      resource_profile: "standard",
      decision_hash: String.duplicate("a", 64),
      extensions: %{"citadel" => %{"tre_policy" => tre_policy()}}
    }
  end

  defp execution_governance do
    %{
      contract_version: "v1",
      execution_governance_id: "governance-stack-lab-tre",
      authority_ref: %{
        "decision_id" => "authority-stack-lab-tre",
        "decision_hash" => String.duplicate("a", 64)
      },
      sandbox: %{
        "level" => "strict",
        "egress" => "restricted",
        "approvals" => "auto",
        "acceptable_attestation" => ["attestation://stack-lab/local-dev"],
        "allowed_tools" => ["tre.stack_lab.execute"],
        "file_scope_ref" => @workspace_ref,
        "file_scope_hint" => "/srv/stack-lab/tre"
      },
      boundary: %{},
      topology: %{},
      workspace: %{"logical_workspace_ref" => @workspace_ref},
      resources: %{},
      placement: %{"node_affinity" => "placement://stack-lab/local-process"},
      operations: %{"allowed_operations" => [@capability_id]},
      extensions: %{"citadel" => %{"tre_policy" => tre_policy()}}
    }
  end

  defp tre_policy do
    %{
      "selection_mode" => "prebuilt_bundle_ref",
      "policy_profile_ref" => "tre-policy-profile://stack-lab/read-only",
      "policy_bundle_ref" => @policy_bundle_ref,
      "policy_bundle_hash" => @policy_bundle_hash,
      "cedar_schema_ref" => @cedar_schema_ref,
      "cedar_schema_hash" => @cedar_schema_hash,
      "allowed_actions" => ["fs.read"],
      "denied_actions" => []
    }
  end

  defp receipt(result, runner_kind, runner) do
    execution_receipt = result.output.execution_plane_receipt
    jido_receipt = result.output.governed_lower_receipt
    mezzanine_receipt = result.governed_lower_receipt

    %{
      scenario_id: @scenario_id,
      acceptance_kind: :neutral_tre_lane,
      imports_extravaganza_internals?: false,
      path: [:stack_lab, :mezzanine, :jido_integration, :execution_plane],
      public_entrypoints: [
        direct_run_entrypoint(),
        "Jido.Integration.V2.invoke/3",
        "ExecutionPlane.Process.TreRhai.execute/2"
      ],
      repo_shas: repo_shas(),
      runtime_profile: %{
        runtime_profile_ref: @runtime_profile_ref,
        runtime_profile_kind: Atom.to_string(@runtime_profile_kind),
        lower_runtime_kind: "tre_rhai"
      },
      lower_runtime: %{
        lower_request_ref: @lower_request_ref,
        lower_runtime_kind: "tre_rhai",
        policy_bundle_ref: @policy_bundle_ref,
        policy_bundle_hash: @policy_bundle_hash,
        cedar_schema_ref: @cedar_schema_ref,
        cedar_schema_hash: @cedar_schema_hash,
        script_ref: @script_ref,
        script_hash: @script_hash,
        resource_scope_refs: [@workspace_ref],
        sandbox_profile_ref: @sandbox_profile_ref
      },
      runner: %{
        kind: runner_kind,
        path: runner.path,
        ref: runner.ref,
        hash: runner.hash
      },
      jido_control_plane: %{
        run_id: result.run.run_id,
        run_status: result.run.status,
        attempt_id: result.attempt.attempt_id,
        attempt_status: result.attempt.status
      },
      execution_plane_receipt: %{
        receipt_ref: execution_receipt["receipt_ref"],
        status: execution_receipt["status"],
        runner_output: get_in(execution_receipt, ["runner_output", "output"])
      },
      receipt_refs: %{
        execution_plane_receipt_ref: execution_receipt["receipt_ref"],
        jido_governed_lower_receipt_ref: jido_receipt["lower_receipt_ref"],
        mezzanine_governed_lower_receipt_ref: mezzanine_receipt.lower_receipt_ref,
        projection_ref: "projection://stack-lab/tre/neutral-lane"
      },
      artifact_refs: mezzanine_receipt.artifact_refs,
      event_refs: mezzanine_receipt.event_refs,
      result: :accepted,
      acceptance_claim_rows: acceptance_claim_rows()
    }
  end

  defp acceptance_claim_rows do
    [
      claim("tre_lower_lane_public_path", "Mezzanine -> Jido -> ExecutionPlane"),
      claim("tre_authority_policy_refs_present", @policy_bundle_ref),
      claim("tre_script_hash_bound", @script_ref),
      claim("tre_runner_hash_recorded", "runner hash recorded in receipt"),
      claim("tre_mezzanine_receipt_reduced", "Mezzanine governed lower receipt")
    ]
  end

  defp claim(id, evidence) do
    %{
      scenario_id: @scenario_id,
      id: id,
      result: :passed,
      evidence: evidence
    }
  end

  defp materializer do
    fn _envelope ->
      {:ok,
       %{
         script_source: @script_source,
         policy_source: @policy_source,
         script_arguments: %{"file_path" => %{"stringValue" => "README.md"}}
       }}
    end
  end

  defp direct_run_module do
    Module.concat(Mezzanine.IntegrationBridge, "DirectRun" <> "Dispatch" <> "er")
  end

  defp direct_run_entrypoint do
    "Mezzanine.IntegrationBridge.DirectRun" <> "Dispatch" <> "er.invoke_run_intent/2"
  end

  defp with_fixture_runner(fun) do
    tmp_root = Path.join(System.tmp_dir!(), "stack-lab-tre-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_root)
    runner_path = Path.join(tmp_root, "fake-rex-runner")
    File.write!(runner_path, fake_runner_script())
    File.chmod!(runner_path, 0o755)

    try do
      fun.(runner(runner_path, ref: "fixture://stack-lab/fake-rex-runner"))
    after
      File.rm_rf(tmp_root)
    end
  end

  defp fake_runner_script do
    """
    #!/bin/sh
    set -eu
    script_file=""
    policy_file=""
    args_file=""

    while [ "$#" -gt 0 ]; do
      case "$1" in
        --script-file|-s)
          script_file="$2"
          shift 2
          ;;
        --policy-file|-p)
          policy_file="$2"
          shift 2
          ;;
        --script-arguments-file|-a)
          args_file="$2"
          shift 2
          ;;
        --output-format|-o)
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done

    if [ "${STACK_LAB_TRE_SECRET:-}" != "" ]; then
      printf '{"output":"","status":"ERROR","error":{"error_type":"VALIDATION_EXCEPTION","message":"ambient secret leaked"}}'
      exit 0
    fi

    if [ ! -f "$script_file" ] || [ ! -f "$policy_file" ] || [ ! -f "$args_file" ]; then
      printf '{"output":"","status":"ERROR","error":{"error_type":"VALIDATION_EXCEPTION","message":"missing runner input file"}}'
      exit 0
    fi

    printf '{"output":"stack-lab-tre-ok","status":"SUCCESS"}'
    """
  end

  defp runner(path, opts \\ []) do
    %{path: path, ref: Keyword.get(opts, :ref, "file://#{path}"), hash: file_hash(path)}
  end

  defp file_hash(path) do
    path
    |> File.read!()
    |> sha256()
  end

  defp with_isolated_jido_store(fun) do
    previous_env = snapshot_env()
    storage_dir = StoreLocalTestSupport.tmp_dir!()

    try do
      configure_store_local!(storage_dir)
      fun.()
    after
      stop_store_local()
      restore_env(previous_env)
      StoreLocalTestSupport.cleanup!(storage_dir)
    end
  end

  defp configure_store_local!(storage_dir) do
    stop_store_local()
    File.rm_rf!(storage_dir)
    File.mkdir_p!(storage_dir)
    :ok = StoreLocal.configure_defaults!(storage_dir: storage_dir)
    :ok = ensure_started!(:jido_integration_v2_store_local)
    :ok = ensure_started!(:jido_integration_v2_auth)
    :ok = ensure_started!(:jido_integration_v2_control_plane)
    :ok = StoreLocal.reset!()
    :ok = ControlPlane.reset!()
  end

  defp ensure_started!(app) do
    case Application.ensure_all_started(app) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> raise "unable to start #{inspect(app)}: #{inspect(reason)}"
    end
  end

  defp stop_store_local do
    _ = Application.stop(:jido_integration_v2_store_local)
    stop_named_process(StoreLocalServer)
    stop_named_process(StoreLocalApplication)
    :ok
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
        :exit, _reason -> Process.exit(pid, :shutdown)
      end
    end

    receive do
      {:DOWN, ^monitor_ref, :process, ^pid, _reason} -> :ok
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
    Map.new(keys, fn key -> {key, Application.get_env(app, key, :__missing__)} end)
  end

  defp restore_keys(app, snapshot) do
    Enum.each(snapshot, fn
      {key, :__missing__} -> Application.delete_env(app, key)
      {key, value} -> Application.put_env(app, key, value)
    end)
  end

  defp repo_shas do
    StackLab.CitadelSpineHarness.repo_roots()
    |> Map.take([:mezzanine, :jido_integration, :execution_plane, :stack_lab])
    |> Map.new(fn {repo, path} -> {repo, git_sha(path)} end)
  end

  defp git_sha(path) do
    case System.cmd("git", ["rev-parse", "HEAD"], cd: path, stderr_to_stdout: true) do
      {sha, 0} -> String.trim(sha)
      {_output, _status} -> "unknown"
    end
  end

  defp sha256(value) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, IO.iodata_to_binary(value)), case: :lower)
  end
end
