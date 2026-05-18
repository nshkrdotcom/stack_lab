defmodule StackLab.Examples.SynapseLiveSlice do
  @moduledoc """
  Deterministic live-stack slice proof for the Synapse rewrite.

  This proof keeps Synapse on its product boundary while driving the real
  AppKit -> Mezzanine bridge path with Mezzanine's deterministic AgentLoop
  runtime adapter. It is not a live-provider proof.
  """

  @schema_version "stack_lab.synapse_live_slice.v1"
  @default_synapse_root "/home/home/p/g/n/synapse"
  @trace_id "11111111111111111111111111111111"
  @run_token "stacklab-synapse-live-slice"
  @denied_run_token "stacklab-synapse-live-denied"
  @live_stack_code_apps [
    :app_kit_mezzanine_bridge,
    :mezzanine_workflow_runtime,
    :mezzanine_integration_bridge,
    :mezzanine_core,
    :mezzanine_citadel_bridge,
    :citadel_governance,
    :citadel_authority_contract,
    :citadel_execution_governance_contract,
    :ground_plane_contracts,
    :ground_plane_persistence_policy,
    :execution_plane,
    :jido_integration_contracts
  ]

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    synapse_root = Keyword.get(opts, :synapse_root, @default_synapse_root)
    ensure_live_stack_code_paths()

    with {:ok, fixture_receipt} <-
           StackLab.Examples.SynapseProductAcceptance.run(synapse_root: synapse_root),
         {:ok, run_start} <- prove_run_start(),
         {:ok, turn_submission} <- prove_turn_submission(run_start),
         {:ok, await} <- prove_await(run_start),
         {:ok, runtime_projection} <- prove_runtime_projection(run_start),
         {:ok, evidence_receipt} <- prove_evidence_receipt(runtime_projection),
         {:ok, denial_path} <- prove_denial_path(),
         no_bypass <- Map.fetch!(fixture_receipt, "no_bypass") do
      {:ok,
       %{
         "schema_version" => @schema_version,
         "status" => "pass",
         "product_repo" => "synapse",
         "product_path" => synapse_root,
         "stack_lab_role" => "synapse_live_slice_acceptance",
         "classification" => "live_stack_deterministic",
         "proofs" => %{
           "fixture_acceptance" => %{
             "status" => fixture_receipt["status"],
             "classification" => fixture_receipt["classification"]
           },
           "run_start" => run_start,
           "turn_submission" => turn_submission,
           "await" => await,
           "runtime_projection" => runtime_projection,
           "evidence_receipt" => evidence_receipt,
           "denial_path" => denial_path
         },
         "no_bypass" => no_bypass,
         "not_proven" => [
           "live_provider_behavior",
           "production_deployment",
           "teams_arbitration_live_execution",
           "memory_feedback_write",
           "catalog_assignment"
         ]
       }}
    end
  end

  defp prove_run_start do
    attrs = %{
      "title" => "StackLab Synapse live slice",
      "goal_summary" => "Prove AppKit-to-Mezzanine deterministic AgentLoop execution."
    }

    opts = Keyword.put(live_stack_opts(), :run_token, @run_token)

    case Synapse.AgentRuns.start_run(attrs, opts) do
      {:ok, run} ->
        with :ok <- require_equal(value(run, :state), :accepted, :run_not_accepted),
             :ok <-
               require_equal(
                 value(run, :feature_status),
                 :live_stack_deterministic,
                 :run_not_live_stack
               ),
             run_ref when is_binary(run_ref) <- value(run, :ref),
             workflow_ref when is_binary(workflow_ref) <- value(run, :workflow_ref) do
          {:ok,
           %{
             "status" => "pass",
             "feature_status" => "live_stack_deterministic",
             "surface" => value(run, :surface),
             "run_ref" => run_ref,
             "workflow_ref" => workflow_ref,
             "evidence_refs" => value(run, :evidence_refs) || []
           }}
        else
          {:error, reason} -> {:error, reason}
          other -> {:error, {:run_start_missing_ref, other}}
        end

      other ->
        {:error, {:run_start_failed, other}}
    end
  end

  defp prove_turn_submission(run_start) do
    attrs = %{"kind" => "user_input", "input_summary" => "StackLab live-slice turn"}

    case Synapse.Turns.submit_turn(run_start["run_ref"], attrs, live_stack_opts()) do
      {:ok, result} ->
        with :ok <- require_equal(value(result, :accepted?), true, :turn_not_accepted),
             :ok <- require_equal(value(result, :status), :accepted, :turn_status_not_accepted) do
          {:ok,
           %{
             "status" => "accepted",
             "feature_status" => "live_stack_deterministic",
             "command_kind" => atomish(value(result, :command_kind)),
             "command_ref" => value(result, :command_ref),
             "receipt_ref" => value(result, :receipt_ref)
           }}
        end

      other ->
        {:error, {:turn_submission_failed, other}}
    end
  end

  defp prove_await(run_start) do
    request = %{"workflow_ref" => run_start["workflow_ref"]}

    case Synapse.AgentRuns.await_run(run_start["run_ref"], request, live_stack_opts()) do
      {:ok, future} ->
        with :ok <- require_equal(value(future, :accepted?), true, :await_not_accepted) do
          {:ok,
           %{
             "status" => "accepted",
             "feature_status" => "live_stack_deterministic",
             "run_ref" => value(future, :run_ref),
             "workflow_ref" => value(future, :workflow_ref),
             "command_ref" => value(future, :command_ref)
           }}
        end

      other ->
        {:error, {:await_failed, other}}
    end
  end

  defp prove_runtime_projection(run_start) do
    case Synapse.AgentRuns.get_run(run_start["run_ref"], live_stack_opts()) do
      {:ok, detail} ->
        runtime_row = value(detail, :runtime_row) || %{}
        event_kinds = event_kinds(detail)
        turn_count = length(value(detail, :turns) || [])
        candidate_fact_refs = value(detail, :candidate_fact_refs) || []
        memory_proof_refs = value(detail, :memory_proof_refs) || []

        with :ok <- require_equal(value(runtime_row, :state), "completed", :runtime_not_completed),
             :ok <- require_present(event_kinds, "agent_run.accepted", :missing_accept_event),
             :ok <- require_present(event_kinds, "run.terminal", :missing_terminal_event),
             :ok <- require_non_empty(candidate_fact_refs, :missing_candidate_facts),
             :ok <- require_non_empty(memory_proof_refs, :missing_memory_proofs),
             true <- turn_count > 0 do
          {:ok,
           %{
             "status" => "pass",
             "feature_status" => "live_stack_deterministic",
             "run_ref" => value(detail, :run_ref),
             "workflow_ref" => value(runtime_row, :workflow_ref),
             "runtime_state" => value(runtime_row, :state),
             "event_kinds" => event_kinds,
             "turn_count" => turn_count,
             "candidate_fact_refs" => candidate_fact_refs,
             "memory_proof_refs" => memory_proof_refs,
             "detail" => detail_summary(detail)
           }}
        else
          false -> {:error, :runtime_turns_missing}
          {:error, reason} -> {:error, reason}
        end

      other ->
        {:error, {:runtime_projection_failed, other}}
    end
  end

  defp prove_evidence_receipt(runtime_projection) do
    detail = runtime_projection["detail"]
    receipt_ref = detail["tool_action_receipt_ref"]
    lower_receipt_ref = detail["lower_receipt_ref"]

    with :ok <- require_ref(receipt_ref, :missing_tool_action_receipt_ref),
         :ok <- require_ref(lower_receipt_ref, :missing_lower_receipt_ref),
         :ok <- require_non_empty(runtime_projection["candidate_fact_refs"], :missing_fact_refs),
         :ok <- require_non_empty(runtime_projection["memory_proof_refs"], :missing_memory_refs) do
      {:ok,
       %{
         "status" => "pass",
         "feature_status" => "live_stack_deterministic",
         "receipt_ref" => receipt_ref,
         "lower_receipt_ref" => lower_receipt_ref,
         "candidate_fact_ref_count" => length(runtime_projection["candidate_fact_refs"]),
         "memory_proof_ref_count" => length(runtime_projection["memory_proof_refs"])
       }}
    end
  end

  defp prove_denial_path do
    attrs = %{
      "title" => "StackLab Synapse denied live slice",
      "goal_summary" => "Prove denied lower write does not submit a lower action."
    }

    opts =
      %{fixture_script: "denied_write_then_allowed_read"}
      |> live_stack_opts()
      |> Keyword.put(:run_token, @denied_run_token)

    with {:ok, run} <- Synapse.AgentRuns.start_run(attrs, opts),
         {:ok, detail} <- Synapse.AgentRuns.get_run(value(run, :ref), opts) do
      runtime_row = value(detail, :runtime_row) || %{}
      event_kinds = event_kinds(detail)

      with :ok <- require_equal(value(runtime_row, :state), "blocked", :denial_not_blocked),
           :ok <- require_present(event_kinds, "authority.denied", :missing_denial_event),
           :ok <- reject_present(event_kinds, "action.submitted", :denied_action_submitted) do
        {:ok,
         %{
           "status" => "pass",
           "feature_status" => "live_stack_deterministic",
           "run_ref" => value(run, :ref),
           "runtime_state" => value(runtime_row, :state),
           "event_kinds" => event_kinds,
           "lower_effect_submitted?" => false
         }}
      end
    else
      {:error, reason} -> {:error, {:denial_path_failed, reason}}
    end
  end

  defp live_stack_opts(runtime_params \\ %{}) do
    runtime_params =
      %{
        fixture_script: "success_first_try",
        max_turns: 2,
        initial_input: %{
          body: "StackLab deterministic live slice input",
          input_ref: "payload://stack-lab/synapse/live-slice/initial",
          content_hash: "sha256:stacklabsynapseliveslice",
          source_ref: "stacklab://synapse-live-slice",
          rendered?: true,
          body_redacted?: true
        }
      }
      |> Map.merge(runtime_params)

    [
      backend: AppKit.Bridges.MezzanineBridge,
      runtime_adapter: Mezzanine.WorkflowRuntime.AgentLoop,
      agent_loop_runtime: Mezzanine.WorkflowRuntime.AgentLoop,
      runtime_role_ref: :agent_loop_runtime,
      operation_role_ref: :start_run,
      runtime_binding: %{
        runtime_binding_ref: "runtime-binding://stack-lab/synapse/live-slice/agent-loop",
        adapter_module: Mezzanine.WorkflowRuntime.AgentLoop,
        operation_ref: "agent.run.start",
        allowed_operations: [
          "agent.run.start",
          "agent.turn.submit",
          "agent.run.cancel",
          "agent.run.await"
        ]
      },
      runtime_params: runtime_params,
      live_stack?: true,
      trace_id: @trace_id
    ]
  end

  defp detail_summary(detail) do
    first_turn =
      detail
      |> value(:turns)
      |> case do
        [turn | _rest] -> turn
        _other -> %{}
      end

    %{
      "tool_action_receipt_ref" => value(first_turn, :tool_action_receipt_ref),
      "lower_receipt_ref" => value(first_turn, :observation_ref),
      "semantic_fact_refs" => value(first_turn, :semantic_fact_refs) || [],
      "memory_commit_ref" => value(first_turn, :memory_commit_ref)
    }
  end

  defp event_kinds(detail) do
    detail
    |> value(:events)
    |> case do
      events when is_list(events) -> Enum.map(events, &value(&1, :event_kind))
      _other -> []
    end
    |> Enum.reject(&is_nil/1)
  end

  defp require_equal(actual, expected, _reason) when actual == expected, do: :ok
  defp require_equal(actual, expected, reason), do: {:error, {reason, actual, expected}}

  defp require_present(values, value, reason) when is_list(values) do
    if value in values, do: :ok, else: {:error, {reason, values}}
  end

  defp reject_present(values, value, reason) when is_list(values) do
    if value in values, do: {:error, {reason, values}}, else: :ok
  end

  defp require_non_empty(values, _reason) when is_list(values) and values != [], do: :ok
  defp require_non_empty(_values, reason), do: {:error, reason}

  defp require_ref(value, _reason) when is_binary(value) and value != "", do: :ok
  defp require_ref(_value, reason), do: {:error, reason}

  defp value(%_{} = struct, key), do: struct |> Map.from_struct() |> value(key)

  defp value(%{} = map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp value(%{} = map, key) when is_binary(key) do
    Map.get(map, key) ||
      Enum.find_value(map, fn
        {atom_key, value} when is_atom(atom_key) ->
          if Atom.to_string(atom_key) == key, do: value

        _other ->
          nil
      end)
  end

  defp value(_other, _key), do: nil

  defp atomish(value) when is_atom(value), do: Atom.to_string(value)
  defp atomish(value), do: value

  defp ensure_live_stack_code_paths do
    if Code.ensure_loaded?(Mix.Project) do
      build_path = Mix.Project.build_path()

      Enum.each(@live_stack_code_apps, fn app ->
        ebin_path = Path.join([build_path, "lib", Atom.to_string(app), "ebin"])

        if File.dir?(ebin_path) do
          :code.add_patha(String.to_charlist(ebin_path))
        end
      end)
    end
  end
end
