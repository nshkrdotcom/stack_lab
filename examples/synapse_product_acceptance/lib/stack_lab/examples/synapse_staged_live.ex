defmodule StackLab.Examples.SynapseStagedLive do
  @moduledoc """
  Governed-effect staged-live conformance proof for Synapse.

  The proof drives Synapse product code through AppKit EffectSurface, then uses
  proof-owned adapters to exercise Mezzanine governed effects, Citadel
  authority, Jido direct runtime, Execution Plane diagnostic execution, and
  AITrace governed-effect evidence.
  """

  alias AppKit.EffectSurface
  alias StackLab.Examples.SynapseProductAcceptance
  alias StackLab.Examples.SynapseStagedLive.{EffectBackend, Store}
  alias Synapse.{AgentRuns, Config, GovernedEffects, PlatformContext, ProductBootstrap}

  @schema_version "stack_lab.synapse_staged_live.v1"
  @default_synapse_root "/home/home/p/g/n/synapse"
  @trace_id "22222222222222222222222222222222"
  @run_token "stacklab-synapse-staged-live"
  @denial_effect_ref "effect://synapse/staged-live-denial/probe"

  @live_stack_code_apps [
    :app_kit_mezzanine_bridge,
    :mezzanine_workflow_runtime,
    :mezzanine_integration_bridge,
    :mezzanine_governed_effects,
    :mezzanine_core,
    :mezzanine_citadel_bridge,
    :citadel_authority_contract,
    :citadel_contract_core,
    :citadel_governance,
    :citadel_execution_governance_contract,
    :ground_plane_contracts,
    :ground_plane_persistence_policy,
    :jido_integration_v2_direct_runtime,
    :jido_integration_contracts,
    :execution_plane,
    :aitrace
  ]

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    synapse_root = Keyword.get(opts, :synapse_root, @default_synapse_root)
    ensure_live_stack_code_paths()
    Store.clear()

    with {:ok, fixture_receipt} <- SynapseProductAcceptance.run(synapse_root: synapse_root),
         {:ok, run_start} <- prove_run_start(),
         {:ok, governed_pipeline} <- prove_governed_pipeline(run_start),
         {:ok, timeline} <- prove_timeline(run_start),
         {:ok, denial_path} <- prove_denial_path(),
         {:ok, evidence_chain} <- prove_evidence_chain(run_start, timeline),
         no_bypass <- Map.fetch!(fixture_receipt, "no_bypass") do
      {:ok,
       %{
         "schema_version" => @schema_version,
         "status" => "pass",
         "product_repo" => "synapse",
         "product_path" => synapse_root,
         "stack_lab_role" => "synapse_governed_effect_conformance",
         "classification" => "staging_live",
         "proofs" => %{
           "fixture_acceptance" => %{
             "status" => fixture_receipt["status"],
             "classification" => fixture_receipt["classification"]
           },
           "run_start" => run_start,
           "governed_pipeline" => governed_pipeline,
           "timeline" => timeline,
           "denial_path" => denial_path,
           "evidence_chain" => evidence_chain
         },
         "no_bypass" => no_bypass,
         "not_proven" => [
           "live_provider_behavior",
           "production_deployment",
           "browser_rendering"
         ]
       }}
    end
  end

  defp prove_run_start do
    attrs = %{
      "title" => "StackLab Synapse staged-live proof",
      "goal_summary" => "Prove the governed-effect diagnostic path."
    }

    case AgentRuns.start_run(attrs, staged_live_opts()) do
      {:ok, run} ->
        refs = value(run, :governed_effect_refs) || %{}
        effect_ref = Map.get(refs, "effect_ref")

        with :ok <- require_equal(value(run, :state), :accepted, :run_not_accepted),
             :ok <-
               require_equal(value(run, :feature_status), :staging_live, :run_not_staging_live),
             :ok <-
               require_equal(
                 value(run, :effect_governance_mode),
                 :staging_live,
                 :governance_mode_not_staging_live
               ),
             :ok <- require_ref(effect_ref, :missing_effect_ref),
             {:ok, record} <- Store.fetch(effect_ref) do
          {:ok,
           %{
             "status" => "pass",
             "feature_status" => "staging_live",
             "surface" => value(run, :surface),
             "run_ref" => value(run, :ref),
             "workflow_ref" => value(run, :workflow_ref),
             "effect_ref" => effect_ref,
             "command_ref" => Map.get(refs, "command_ref"),
             "authority_ref" => Map.get(refs, "authority_ref"),
             "receipt_ref" => Map.get(refs, "receipt_ref"),
             "evidence_refs" => value(run, :evidence_refs) || [],
             "pipeline_stage_count" => length(record.pipeline_stages)
           }}
        else
          {:error, reason} -> {:error, reason}
        end

      other ->
        {:error, {:staged_run_start_failed, other}}
    end
  end

  defp prove_governed_pipeline(run_start) do
    with {:ok, record} <- Store.fetch(run_start["effect_ref"]),
         :ok <-
           require_present(record.pipeline_stages, "appkit_effect_surface", :missing_appkit_stage),
         :ok <-
           require_present(
             record.pipeline_stages,
             "mezzanine_governed_effect",
             :missing_mezzanine_stage
           ),
         :ok <-
           require_present(record.pipeline_stages, "citadel_authority", :missing_citadel_stage),
         :ok <-
           require_present(record.pipeline_stages, "jido_diagnostic_lane", :missing_jido_stage),
         :ok <-
           require_present(
             record.pipeline_stages,
             "execution_plane_diagnostic",
             :missing_execution_stage
           ),
         :ok <-
           require_present(record.pipeline_stages, "aitrace_evidence", :missing_aitrace_stage),
         :ok <- require_equal(record.citadel_decision, "allow", :citadel_not_allow),
         :ok <- require_equal(record.jido_receipt_status, "success", :jido_receipt_not_success),
         :ok <- require_equal(record.execution_plane_status, "ok", :execution_plane_not_ok) do
      {:ok,
       %{
         "status" => "pass",
         "stages" => record.pipeline_stages,
         "citadel_authority" => record.citadel_decision,
         "jido_receipt_status" => record.jido_receipt_status,
         "execution_plane_status" => record.execution_plane_status,
         "aitrace_span_count" => length(record.aitrace_span_names),
         "aitrace_span_names" => record.aitrace_span_names
       }}
    end
  end

  defp prove_timeline(run_start) do
    effect_ref = run_start["effect_ref"]

    with {:ok, timeline} <- GovernedEffects.get_effect_timeline(effect_ref, staged_live_opts()),
         statuses <- timeline_statuses(timeline),
         :ok <- require_present(statuses, "proposed", :missing_proposed),
         :ok <- require_present(statuses, "authorized", :missing_authorized),
         :ok <- require_present(statuses, "dispatched", :missing_dispatched),
         :ok <- require_present(statuses, "receipt_received", :missing_receipt_received),
         :ok <- require_present(statuses, "reduced", :missing_reduced),
         :ok <- require_present(statuses, "projected", :missing_projected),
         :ok <- require_present(statuses, "completed", :missing_completed),
         :ok <- require_ref(timeline.trace_summary_hash, :missing_trace_summary_hash),
         :ok <- require_entry_hashes(timeline.entries) do
      {:ok,
       %{
         "status" => "pass",
         "effect_ref" => effect_ref,
         "trace_summary_hash" => timeline.trace_summary_hash,
         "statuses" => statuses,
         "entry_count" => length(timeline.entries)
       }}
    end
  end

  defp prove_denial_path do
    attrs = %{
      effect_ref: @denial_effect_ref,
      effect_type: "diagnostic.probe",
      command_ref: "command://synapse/staged-live-denial/probe",
      tenant_ref: "tenant://default",
      actor_ref: "actor://synapse/operator",
      installation_ref: "installation://default",
      status: "proposed",
      trace_ref: "trace:synapse-staged-live-denial",
      expected_version: 1,
      metadata: %{
        "diagnostic_lane" => "probe",
        "product_slug" => "synapse",
        "run_ref" => "run://synapse/staged-live-denial"
      }
    }

    opts = Keyword.put(staged_live_opts(), :allowed_effect_types, ["diagnostic.echo"])

    with {:ok, dto} <- EffectSurface.propose_effect(product_context(opts), attrs, opts),
         denial_view <- GovernedEffects.effect_view(dto),
         {:ok, record} <- Store.fetch(dto.effect_ref),
         :ok <- require_equal(denial_view.status, "denied", :denial_status_not_visible),
         :ok <- require_equal(record.lower_invocation_submitted?, false, :denied_lower_submitted) do
      {:ok,
       %{
         "status" => "pass",
         "effect_ref" => dto.effect_ref,
         "authority_ref" => dto.authority_ref,
         "product_status" => denial_view.status,
         "lower_invocation_submitted?" => record.lower_invocation_submitted?,
         "citadel_authority" => record.citadel_decision
       }}
    end
  end

  defp prove_evidence_chain(run_start, timeline) do
    with {:ok, record} <- Store.fetch(run_start["effect_ref"]),
         :ok <- require_equal(record.command_ref, run_start["command_ref"], :command_ref_mismatch),
         :ok <- require_equal(record.effect_ref, run_start["effect_ref"], :effect_ref_mismatch),
         :ok <- require_equal(record.receipt_ref, run_start["receipt_ref"], :receipt_ref_mismatch),
         :ok <- require_non_empty(record.evidence_refs, :missing_evidence_refs),
         :ok <- require_ref(record.command_envelope_hash, :missing_command_envelope_hash),
         :ok <- require_ref(timeline["trace_summary_hash"], :missing_timeline_hash) do
      {:ok,
       %{
         "status" => "pass",
         "command_ref" => record.command_ref,
         "command_envelope_hash" => record.command_envelope_hash,
         "effect_ref" => record.effect_ref,
         "receipt_ref" => record.receipt_ref,
         "evidence_refs" => record.evidence_refs,
         "trace_ref" => record.trace_ref,
         "trace_summary_hash" => timeline["trace_summary_hash"]
       }}
    end
  end

  defp staged_live_opts do
    [
      effect_surface_adapter: EffectBackend,
      backend: AppKit.Bridges.MezzanineBridge,
      runtime_adapter: Mezzanine.WorkflowRuntime.AgentLoop,
      agent_loop_runtime: Mezzanine.WorkflowRuntime.AgentLoop,
      runtime_role_ref: :agent_loop_runtime,
      operation_role_ref: :start_run,
      runtime_binding: %{
        runtime_binding_ref: "runtime-binding://stack-lab/synapse/staged-live/agent-loop",
        adapter_module: Mezzanine.WorkflowRuntime.AgentLoop,
        operation_ref: "agent.run.start",
        allowed_operations: [
          "agent.run.start",
          "agent.turn.submit",
          "agent.run.cancel",
          "agent.run.await"
        ]
      },
      runtime_params: %{
        fixture_script: "success_first_try",
        max_turns: 2,
        initial_input: %{
          body: "StackLab staged-live diagnostic input",
          input_ref: "payload://stack-lab/synapse/staged-live/initial",
          content_hash: "sha256:stacklabsynapsestagedlive",
          source_ref: "stacklab://synapse-staged-live",
          rendered?: true,
          body_redacted?: true
        }
      },
      diagnostic_lane: :echo,
      live_stack?: true,
      run_token: @run_token,
      trace_id: @trace_id
    ]
  end

  defp product_context(opts) do
    config = Config.load(opts)

    {:ok, bootstrap} =
      ProductBootstrap.ensure_bootstrapped(Keyword.put(opts, :bootstrap_mode, :disabled))

    PlatformContext.product_context(config, bootstrap.installation_ref, opts)
  end

  defp timeline_statuses(timeline) do
    timeline.entries
    |> Enum.map(&Map.get(&1, :status))
    |> Enum.reject(&is_nil/1)
  end

  defp require_entry_hashes(entries) when is_list(entries) do
    if Enum.all?(entries, fn entry -> entry |> Map.get(:entry_hash) |> sha256_ref?() end) do
      :ok
    else
      {:error, :invalid_timeline_entry_hash}
    end
  end

  defp require_entry_hashes(_entries), do: {:error, :invalid_timeline_entries}

  defp require_equal(actual, expected, _reason) when actual == expected, do: :ok
  defp require_equal(actual, expected, reason), do: {:error, {reason, actual, expected}}

  defp require_present(values, value, reason) when is_list(values) do
    if value in values, do: :ok, else: {:error, {reason, values}}
  end

  defp require_non_empty(values, _reason) when is_list(values) and values != [], do: :ok
  defp require_non_empty(_values, reason), do: {:error, reason}

  defp require_ref(value, _reason) when is_binary(value) and value != "", do: :ok
  defp require_ref(_value, reason), do: {:error, reason}

  defp sha256_ref?("sha256:" <> rest), do: rest != ""
  defp sha256_ref?(_value), do: false

  defp value(%_{} = struct, key), do: struct |> Map.from_struct() |> value(key)

  defp value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value(%{} = map, key) when is_binary(key), do: Map.get(map, key)
  defp value(_other, _key), do: nil

  defp ensure_live_stack_code_paths do
    if Code.ensure_loaded?(Mix.Project) do
      add_live_stack_code_paths(Mix.Project.build_path())
    end

    ensure_runtime_projection_store_started()
    ensure_aitrace_started()
    ensure_store_started()
  end

  defp ensure_aitrace_started do
    case Application.ensure_all_started(:aitrace) do
      {:ok, _apps} -> :ok
      {:error, {:already_started, :aitrace}} -> :ok
    end
  end

  defp ensure_runtime_projection_store_started do
    store = AppKit.Bridges.MezzanineBridge.RuntimeProjectionStore

    case Process.whereis(store) do
      nil ->
        start_supervisor([store], StackLab.Examples.SynapseStagedLive.RuntimeProjectionSupervisor)

      _pid ->
        :ok
    end
  end

  defp ensure_store_started do
    case Process.whereis(Store) do
      nil -> start_supervisor([Store], StackLab.Examples.SynapseStagedLive.StoreSupervisor)
      _pid -> :ok
    end
  end

  defp start_supervisor(children, name) do
    case Supervisor.start_link(children, strategy: :one_for_one, name: name) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp add_live_stack_code_paths(build_path) do
    Enum.each(@live_stack_code_apps, fn app ->
      app
      |> live_stack_ebin_path(build_path)
      |> add_code_path_if_directory()
    end)
  end

  defp live_stack_ebin_path(app, build_path) do
    Path.join([build_path, "lib", Atom.to_string(app), "ebin"])
  end

  defp add_code_path_if_directory(path) do
    if File.dir?(path) do
      :code.add_patha(String.to_charlist(path))
    end
  end
end

defmodule StackLab.Examples.SynapseStagedLive.Store do
  @moduledoc false

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, %{}, Keyword.put(opts, :name, __MODULE__))

  @spec clear() :: :ok
  def clear, do: GenServer.call(__MODULE__, :clear)

  @spec put(String.t(), map()) :: :ok
  def put(effect_ref, record) when is_binary(effect_ref) and is_map(record) do
    GenServer.call(__MODULE__, {:put, effect_ref, record})
  end

  @spec fetch(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch(effect_ref) when is_binary(effect_ref) do
    GenServer.call(__MODULE__, {:fetch, effect_ref})
  end

  @spec list() :: [map()]
  def list, do: GenServer.call(__MODULE__, :list)

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:clear, _from, _state), do: {:reply, :ok, %{}}

  def handle_call({:put, effect_ref, record}, _from, state) do
    {:reply, :ok, Map.put(state, effect_ref, record)}
  end

  def handle_call({:fetch, effect_ref}, _from, state) do
    {:reply, Map.fetch(state, effect_ref), state}
  end

  def handle_call(:list, _from, state), do: {:reply, Map.values(state), state}
end

defmodule StackLab.Examples.SynapseStagedLive.EffectBackend do
  @moduledoc false

  @behaviour AppKit.EffectSurface

  alias AITrace.GovernedEffectEvidence
  alias AppKit.Core.{EffectTimelineDTO, GovernedEffectDTO, RequestContext}
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1
  alias Citadel.AuthorityContract.GovernedEffectAuthority
  alias GroundPlane.BoundaryProtocol.CommandEnvelope
  alias Jido.Integration.Lanes.DiagnosticLane
  alias Jido.Integration.V2.{Capability, DirectRuntime, GovernedLowerEnvelope, Manifest}
  alias Mezzanine.Core.GovernedEffects.Coordinator
  alias Mezzanine.Core.GovernedEffects.Projection
  alias StackLab.Examples.SynapseStagedLive.Store

  @impl true
  def propose_effect(%RequestContext{}, effect_params, opts) when is_map(effect_params) do
    with {:ok, record} <- run_pipeline(effect_params, opts) do
      Store.put(record.effect_ref, record)
      {:ok, record.dto}
    end
  end

  @impl true
  def get_effect(%RequestContext{}, effect_ref, _opts) when is_binary(effect_ref) do
    with {:ok, record} <- Store.fetch(effect_ref), do: {:ok, record.dto}
  end

  @impl true
  def list_effects(%RequestContext{}, _run_ref, _opts) do
    {:ok, Enum.map(Store.list(), & &1.dto)}
  end

  @impl true
  def get_effect_timeline(%RequestContext{}, effect_ref, _opts) when is_binary(effect_ref) do
    with {:ok, record} <- Store.fetch(effect_ref) do
      EffectTimelineDTO.new(%{
        effect_ref: effect_ref,
        trace_summary_hash: record.trace_summary_hash,
        entries: record.timeline,
        metadata: %{"source" => "stack_lab.synapse.staged_live.v1"}
      })
    end
  end

  defp run_pipeline(effect_params, opts) do
    attrs = normalize_attrs(effect_params)
    command_envelope = command_envelope!(attrs)

    with {:ok, run} <- Coordinator.propose(command_attrs(attrs)),
         {:ok, authority_decision} <-
           GovernedEffectAuthority.authorize(authority_request(attrs), opts),
         {:ok, final_run, lower_output} <-
           apply_authority_and_dispatch(run, attrs, authority_decision),
         {:ok, evidence_trace} <-
           evidence_trace(final_run, authority_decision, lower_output, command_envelope),
         {:ok, dto} <-
           GovernedEffectDTO.new(
             dto_attrs(final_run, evidence_trace, command_envelope, lower_output)
           ) do
      {:ok,
       record(final_run, dto, evidence_trace, command_envelope, lower_output, authority_decision)}
    end
  end

  defp apply_authority_and_dispatch(run, attrs, authority_decision) do
    decision = AuthorityDecisionV1.governed_effect_decision(authority_decision)

    case decision do
      "allow" -> run_allowed_path(run, attrs, authority_decision)
      "deny" -> run_denied_path(run, authority_decision)
      other -> {:error, {:unsupported_authority_decision, other}}
    end
  end

  defp run_allowed_path(run, attrs, authority_decision) do
    dispatch_adapter = fn envelope ->
      dispatch_to_jido(envelope, attrs, authority_decision)
    end

    with {:ok, run} <- Coordinator.authorize(run, authority_attrs(attrs, authority_decision)),
         {:ok, run} <- Coordinator.dispatch(run, dispatch_adapter: dispatch_adapter),
         lower_output <- Map.get(run.invocation_envelope, "lower_output", %{}),
         receipt <- lower_output |> Map.fetch!("lower_effect_receipt") |> effect_receipt_attrs(),
         {:ok, run} <- Coordinator.receive_receipt(run, receipt),
         {:ok, run} <- Coordinator.reduce(run),
         {:ok, run} <- Coordinator.project(run),
         {:ok, run} <- Coordinator.complete(run) do
      {:ok, run, lower_output}
    end
  end

  defp run_denied_path(run, authority_decision) do
    with {:ok, run} <- Coordinator.deny(run, authority_attrs(run.command, authority_decision)) do
      {:ok, run, %{"lower_invocation_submitted?" => false}}
    end
  end

  defp dispatch_to_jido(envelope, attrs, authority_decision) do
    operation = Map.fetch!(envelope, "operation")
    capability = capability!(operation)
    governed_envelope = governed_lower_envelope!(envelope, attrs, authority_decision, capability)
    payload = Map.get(envelope, "payload", %{})

    case DirectRuntime.execute(capability, payload, %{
           capability: capability,
           governed_lower_envelope: governed_envelope
         }) do
      {:ok, result} ->
        lower_output = result.output

        {:ok,
         envelope
         |> Map.put("dispatch_ref", governed_envelope.lower_request_ref)
         |> Map.put("lower_output", lower_output)}

      {:error, reason, result} ->
        {:error, {reason, result.output}}
    end
  end

  defp effect_receipt_attrs(receipt) do
    Map.take(receipt, [
      "receipt_ref",
      "effect_ref",
      "status",
      "lower_receipt_ref",
      "lower_facts",
      "projection_updates",
      "evidence_refs",
      "trace_ref",
      "completed_at"
    ])
  end

  defp capability!(operation) do
    manifest = DiagnosticLane.manifest()
    operation_spec = Manifest.fetch_operation(manifest, operation)
    Capability.from_operation!(manifest.connector, operation_spec)
  end

  defp governed_lower_envelope!(envelope, attrs, authority_decision, capability) do
    GovernedLowerEnvelope.new!(%{
      lower_request_ref: Map.get(envelope, "invocation_ref"),
      lower_runtime_kind: :direct_connector,
      runtime_profile_ref: "runtime-profile://synapse/diagnostic/direct",
      runtime_profile_kind: :diagnostic,
      capability_id: capability.id,
      action_id: capability.id,
      tenant_ref: Map.fetch!(envelope, "tenant_ref"),
      run_ref: metadata_value(attrs, "run_ref") || "run://synapse/staged-live",
      trace_id: Map.fetch!(envelope, "trace_ref"),
      idempotency_key: Map.fetch!(attrs, :command_ref),
      authority_ref: authority_decision.decision_id,
      authority_decision_hash: authority_decision.decision_hash,
      allowed_operations: [capability.id],
      connector_ref: DiagnosticLane.connector_ref(),
      connector_manifest_ref: DiagnosticLane.manifest_ref(),
      connector_manifest_hash: DiagnosticLane.manifest_hash(),
      connector_manifest_state: :active,
      side_effect_class: :read,
      idempotency_class: :idempotent,
      runtime_class: :direct,
      effect_ref: Map.fetch!(envelope, "effect_ref"),
      expected_version: Map.get(attrs, :expected_version, 1),
      compensation_posture: :not_required,
      evidence_profile_ref: "evidence-profile://governed-effect",
      redaction_profile_ref: "redaction-profile://standard"
    })
  end

  defp evidence_trace(run, authority_decision, lower_output, _command_envelope) do
    projection = Projection.product_safe(run)
    lower_receipt = Map.get(lower_output, "lower_effect_receipt", %{})

    GovernedEffectEvidence.new(%{
      trace_ref: run.effect.trace_ref,
      effect_ref: run.effect.effect_ref,
      command_ref: run.effect.command_ref,
      authority_ref: run.effect.authority_ref || authority_decision.decision_id,
      receipt_ref:
        run.effect.receipt_ref || Map.get(lower_receipt, "receipt_ref", "receipt://denied"),
      transitions: Map.get(projection, "timeline", []),
      authority_decision: %{
        "decision" => AuthorityDecisionV1.governed_effect_decision(authority_decision),
        "decision_hash" => authority_decision.decision_hash,
        "boundary_class" => authority_decision.boundary_class
      },
      lower_execution:
        Map.get(lower_output, "aitrace_evidence", %{"lower_invocation_submitted?" => false}),
      receipt_reduction: %{
        "receipt_ref" => run.effect.receipt_ref || Map.get(lower_receipt, "receipt_ref"),
        "trace_summary_hash" => Map.get(projection, "trace_summary_hash")
      }
    })
    |> case do
      {:ok, evidence} -> {:ok, GovernedEffectEvidence.to_trace(evidence)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dto_attrs(run, evidence_trace, command_envelope, lower_output) do
    projection = Projection.product_safe(run)
    lower_receipt = Map.get(lower_output, "lower_effect_receipt", %{})
    evidence_refs = Map.get(lower_receipt, "evidence_refs", [])

    %{
      effect_ref: run.effect.effect_ref,
      effect_type: run.effect.effect_type,
      command_ref: run.effect.command_ref,
      tenant_ref: run.effect.tenant_ref,
      actor_ref: run.effect.actor_ref,
      installation_ref: run.effect.installation_ref,
      status: Map.get(projection, "status"),
      trace_ref: run.effect.trace_ref,
      authority_ref: run.effect.authority_ref,
      receipt_ref: run.effect.receipt_ref,
      dispatch_ref: run.effect.dispatch_ref,
      expected_version: run.effect.expected_version,
      metadata: %{
        "source" => "stack_lab.synapse.staged_live.v1",
        "run_ref" => metadata_value(run.command, "run_ref"),
        "command_envelope_ref" => command_envelope.command_ref,
        "command_envelope_hash" => CommandEnvelope.digest(command_envelope),
        "trace_summary_hash" => Map.get(projection, "trace_summary_hash"),
        "evidence_refs" => evidence_refs,
        "aitrace_trace_ref" => evidence_trace.trace_id,
        "aitrace_span_names" => Enum.map(evidence_trace.spans, & &1.name)
      }
    }
  end

  defp record(run, dto, evidence_trace, command_envelope, lower_output, authority_decision) do
    projection = Projection.product_safe(run)
    lower_receipt = Map.get(lower_output, "lower_effect_receipt", %{})
    diagnostic_result = get_in(lower_receipt, ["lower_facts", "diagnostic_result"]) || %{}

    %{
      dto: dto,
      effect_ref: run.effect.effect_ref,
      command_ref: run.effect.command_ref,
      authority_ref: run.effect.authority_ref,
      receipt_ref: run.effect.receipt_ref,
      trace_ref: run.effect.trace_ref,
      timeline: Map.get(projection, "timeline", []),
      trace_summary_hash: Map.get(projection, "trace_summary_hash"),
      evidence_refs: Map.get(lower_receipt, "evidence_refs", []),
      command_envelope_hash: CommandEnvelope.digest(command_envelope),
      citadel_decision: AuthorityDecisionV1.governed_effect_decision(authority_decision),
      jido_receipt_status: Map.get(lower_receipt, "status", "not_submitted"),
      execution_plane_status: get_in(diagnostic_result, ["status"]) || "not_submitted",
      lower_invocation_submitted?: Map.has_key?(lower_output, "lower_effect_receipt"),
      aitrace_span_names: Enum.map(evidence_trace.spans, & &1.name),
      pipeline_stages: pipeline_stages(lower_output)
    }
  end

  defp pipeline_stages(lower_output) do
    base = [
      "appkit_effect_surface",
      "mezzanine_governed_effect",
      "citadel_authority"
    ]

    if Map.has_key?(lower_output, "lower_effect_receipt") do
      base ++
        [
          "jido_diagnostic_lane",
          "execution_plane_diagnostic",
          "mezzanine_receipt_reduction",
          "aitrace_evidence",
          "appkit_product_safe_projection"
        ]
    else
      base ++
        ["mezzanine_denial_projection", "aitrace_evidence", "appkit_product_safe_projection"]
    end
  end

  defp command_attrs(attrs) do
    %{
      effect_ref: Map.fetch!(attrs, :effect_ref),
      effect_type: Map.fetch!(attrs, :effect_type),
      command_ref: Map.fetch!(attrs, :command_ref),
      tenant_ref: Map.fetch!(attrs, :tenant_ref),
      actor_ref: Map.get(attrs, :actor_ref),
      installation_ref: Map.get(attrs, :installation_ref),
      trace_ref: Map.fetch!(attrs, :trace_ref),
      expected_version: Map.get(attrs, :expected_version, 1),
      operation: Map.fetch!(attrs, :effect_type),
      payload: diagnostic_payload(attrs),
      run_ref: metadata_value(attrs, "run_ref")
    }
  end

  defp command_envelope!(attrs) do
    CommandEnvelope.new!(%{
      command_ref: Map.fetch!(attrs, :command_ref),
      tenant_ref: Map.fetch!(attrs, :tenant_ref),
      actor_ref: Map.get(attrs, :actor_ref, "actor://synapse/operator"),
      installation_ref: Map.get(attrs, :installation_ref),
      schema_ref: "schema://gaop/command-envelope/diagnostic/v1",
      idempotency_key: Map.fetch!(attrs, :command_ref),
      trace_ref: Map.fetch!(attrs, :trace_ref),
      operation_type: Map.fetch!(attrs, :effect_type),
      payload: diagnostic_payload(attrs),
      expected_version: Map.get(attrs, :expected_version, 1),
      resource_scopes: [%{"scope_ref" => "diagnostic://synapse", "access" => "read"}],
      intent: %{
        "product_slug" => "synapse",
        "reason" => "stack_lab_staged_live_conformance"
      },
      created_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      effect_class: "observe"
    })
  end

  defp diagnostic_payload(attrs) do
    %{
      "message" =>
        attrs
        |> metadata_value("goal_summary")
        |> case do
          value when is_binary(value) and value != "" -> value
          _missing -> "StackLab staged-live diagnostic"
        end
    }
  end

  defp authority_request(attrs) do
    %{
      request_ref:
        "authority-request://synapse/#{safe_ref_segment(Map.fetch!(attrs, :effect_ref))}",
      tenant_ref: Map.fetch!(attrs, :tenant_ref),
      actor_ref: Map.get(attrs, :actor_ref, "actor://synapse/operator"),
      installation_ref: Map.get(attrs, :installation_ref),
      effect_ref: Map.fetch!(attrs, :effect_ref),
      effect_type: Map.fetch!(attrs, :effect_type),
      operation_type: Map.fetch!(attrs, :effect_type),
      resource_class: "diagnostic_lane",
      side_effect_class: "read",
      target_refs: ["diagnostic://synapse"],
      budget_refs: ["budget://synapse/diagnostic"]
    }
  end

  defp authority_attrs(attrs, authority_decision) do
    %{
      authority_ref: authority_decision.decision_id,
      decision: AuthorityDecisionV1.governed_effect_decision(authority_decision),
      tenant_ref: Map.fetch!(attrs, :tenant_ref),
      actor_ref: Map.get(attrs, :actor_ref, "actor://synapse/operator"),
      command_ref: Map.fetch!(attrs, :command_ref),
      trace_ref: Map.fetch!(attrs, :trace_ref),
      decision_hash: authority_decision.decision_hash,
      boundary_class: authority_decision.boundary_class,
      posture: authority_decision.approval_profile
    }
  end

  defp normalize_attrs(%GovernedEffectDTO{} = effect), do: GovernedEffectDTO.dump(effect)

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> Map.new(fn {key, value} -> {normalize_key(key), value} end)
    |> Map.put_new(:status, "proposed")
    |> Map.put_new(:expected_version, 1)
  end

  defp normalize_key(key) when is_atom(key), do: key
  defp normalize_key("effect_ref"), do: :effect_ref
  defp normalize_key("effect_type"), do: :effect_type
  defp normalize_key("command_ref"), do: :command_ref
  defp normalize_key("tenant_ref"), do: :tenant_ref
  defp normalize_key("actor_ref"), do: :actor_ref
  defp normalize_key("installation_ref"), do: :installation_ref
  defp normalize_key("status"), do: :status
  defp normalize_key("trace_ref"), do: :trace_ref
  defp normalize_key("expected_version"), do: :expected_version
  defp normalize_key("metadata"), do: :metadata
  defp normalize_key(key), do: key

  defp metadata_value(attrs, key) when is_map(attrs) do
    metadata =
      case Map.get(attrs, :metadata, Map.get(attrs, "metadata")) do
        %{} = metadata -> metadata
        _missing -> %{}
      end

    Map.get(metadata, key) || Map.get(attrs, key) || Map.get(attrs, string_to_known_atom(key))
  end

  defp string_to_known_atom("run_ref"), do: :run_ref
  defp string_to_known_atom("goal_summary"), do: :goal_summary
  defp string_to_known_atom(_key), do: :unknown

  defp safe_ref_segment(value) when is_binary(value) do
    value
    |> String.replace("://", "/")
    |> String.replace("/", "-")
  end
end
