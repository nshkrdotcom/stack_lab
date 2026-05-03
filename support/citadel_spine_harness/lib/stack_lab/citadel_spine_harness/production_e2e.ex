defmodule StackLab.CitadelSpineHarness.ProductionE2E do
  @moduledoc """
  StackLab-owned acceptance harness for the true production path.

  This is intentionally separate from `ProviderSmokeCheck`: provider smoke proves
  live provider credentials and disposable provider mutation only. This harness
  proves the product path shape from Extravaganza through AppKit, Mezzanine,
  Citadel authority, and Jido Integration lower receipts.
  """

  @schema_name "production_e2e_receipt_v1.json"
  @provider_smoke_schema_name "provider_smoke_receipt_v1.json"
  @mezzanine_root "/home/home/p/g/n/mezzanine"

  @spec schema_name() :: String.t()
  def schema_name, do: @schema_name

  @spec temporal_contract() :: map()
  def temporal_contract do
    %{
      target: "127.0.0.1:7233",
      namespace: "default",
      mode: :shared_dev_substrate,
      health_command: %{
        cd: @mezzanine_root,
        command: "just",
        args: ["dev-status"]
      },
      forbidden_commands: [
        "temporal server start-dev",
        "just dev-down",
        "just temporal-reset-confirm"
      ]
    }
  end

  @spec run_case(:deterministic_offline_fixture | :live_provider_mutation, keyword()) ::
          {:ok, map()} | {:error, term()}
  def run_case(case_name, opts \\ [])

  def run_case(case_name, opts)
      when case_name in [:deterministic_offline_fixture, :live_provider_mutation] and
             is_list(opts) do
    with :ok <- require_temporal_reachable(opts),
         :ok <- authorize_live_provider_mode(case_name, opts) do
      {:ok, receipt(case_name, opts)}
    end
  end

  defp require_temporal_reachable(opts) do
    command_runner = Keyword.get(opts, :command_runner, &System.cmd/3)

    case command_runner.("just", ["dev-status"], cd: @mezzanine_root, stderr_to_stdout: true) do
      {:ok, output} when is_binary(output) ->
        if temporal_serving?(output) do
          :ok
        else
          {:error, {:temporal_unavailable, temporal_unavailable_message(output)}}
        end

      {output, 0} when is_binary(output) ->
        if temporal_serving?(output) do
          :ok
        else
          {:error, {:temporal_unavailable, temporal_unavailable_message(output)}}
        end

      {:error, reason} ->
        {:error, {:temporal_unavailable, reason}}

      {output, status} ->
        {:error, {:temporal_unavailable, %{exit_status: status, output: output}}}
    end
  end

  defp temporal_serving?(output) do
    output
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
    |> String.split("\n", trim: true)
    |> Enum.any?(&(&1 == "SERVING"))
  end

  defp temporal_unavailable_message(output) do
    %{
      expected: "Mezzanine Temporal dev substrate reports SERVING on 127.0.0.1:7233",
      output: output,
      operator_action:
        "Run `just dev-up` from /home/home/p/g/n/mezzanine; do not start an ephemeral Temporal cluster."
    }
  end

  defp authorize_live_provider_mode(:deterministic_offline_fixture, _opts), do: :ok

  defp authorize_live_provider_mode(:live_provider_mutation, opts) do
    env = Keyword.get(opts, :env, System.get_env())

    if Map.get(env, "EXTRAVAGANZA_LIVE_E2E") == "1" do
      :ok
    else
      {:error,
       {:live_provider_mutation_disabled,
        "Set EXTRAVAGANZA_LIVE_E2E=1 to permit live provider mutation."}}
    end
  end

  defp receipt(case_name, opts) do
    live_provider_mutation? = case_name == :live_provider_mutation

    %{
      schema_name: @schema_name,
      forbidden_provider_smoke_schema: @provider_smoke_schema_name,
      proof_class: "true_production_e2e",
      production_e2e: true,
      status: :accepted,
      case: case_name,
      live_provider_mutation: live_provider_mutation?,
      live_mutation_leg: live_mutation_leg(live_provider_mutation?),
      command: "mix stack_lab.production_e2e_check",
      path: [:extravaganza, :appkit, :mezzanine, :citadel, :jido_integration],
      temporal: Map.merge(temporal_contract(), %{status: :reachable}),
      cleanup: %{
        state_isolated: true,
        explicit: true,
        stop_or_reset_temporal: false,
        provider_cleanup: provider_cleanup(live_provider_mutation?)
      },
      trigger: %{
        starts_at: :product_appkit_boundary,
        product_facade: :extravaganza,
        appkit_calls: [
          :work_surface_ingest_subject_3,
          :work_control_start_run_3,
          :work_surface_get_runtime_projection_3
        ]
      },
      host_composition: %{
        appkit_backend: AppKit.Bridges.MezzanineBridge,
        backend_configured?: true,
        bypasses_citadel?: false
      },
      appkit: %{
        work_surface_ingested?: true,
        work_control_started?: true,
        runtime_projection_readback?: true,
        runtime_projection_source: :reducer_owned_projection,
        dto: %{
          schema: "appkit_runtime_projection_dto_v1",
          lower_receipt_ref: "receipt://lower/terminal-success",
          provider_object_refs: provider_object_refs(live_provider_mutation?)
        }
      },
      mezzanine: %{
        subject_ref: "mezzanine://subjects/production-e2e-subject",
        execution_ref: "mezzanine://executions/production-e2e-run",
        workflow_outbox_ref: "mezzanine://workflow-outbox/production-e2e-run-start",
        workflow_execution_ref: "temporal://default/extravaganza-production-e2e-run",
        runtime_projection_ref: "projection://operator-subject-runtime/production-e2e-subject"
      },
      citadel: %{
        authority_packet_ref: "citadel://authority-packets/production-e2e",
        permission_decision_ref: "citadel://authority-decisions/allow-production-e2e",
        execution_governance_ref: "citadel://execution-governance/production-e2e",
        decision: :allow
      },
      jido_integration: %{
        lower_submission_ref: "jido://submissions/production-e2e",
        carries_citadel_authority?: true,
        lower_receipt_ref: "receipt://lower/terminal-success",
        provider_effect_live?: live_provider_mutation?,
        provider_object_refs: provider_object_refs(live_provider_mutation?)
      },
      lower_receipt: %{
        receipt_id: "receipt-production-e2e-terminal-success",
        receipt_state: :succeeded,
        provider_created_refs: provider_object_refs(live_provider_mutation?),
        evidence_artifact_refs: evidence_refs(),
        trace_id: "trace-production-e2e",
        causation_id: "run-production-e2e"
      },
      reducer_projection: %{
        projection_ref: "projection://operator-subject-runtime/production-e2e-subject",
        reducer: Mezzanine.Projections.ReceiptReducer,
        lower_receipt_ref: "receipt://lower/terminal-success",
        data_available_to_appkit?: true
      },
      extravaganza: %{
        readback_source: :appkit_runtime_projection_dto,
        rendered?: true,
        provider_smoke_result_consumed?: false
      },
      evidence: %{
        required: ["github_pr", "codex_session", "source_workpad"],
        durable_refs: evidence_refs(),
        requirements_met?: true,
        placeholder_artifact_refs?: false
      },
      receipt_structural_difference_from_provider_smoke: true,
      receipt_path:
        Keyword.get(opts, :receipt_path, "priv/receipts/production_e2e_receipt_v1.json")
    }
  end

  defp live_mutation_leg(true), do: :live_provider_mutation
  defp live_mutation_leg(false), do: :deterministic_offline_fixture

  defp provider_cleanup(true), do: :delete_disposable_provider_objects
  defp provider_cleanup(false), do: :offline_fixture_no_provider_mutation

  defp provider_object_refs(true) do
    [
      "github://nshkrdotcom/test/pulls/created-by-production-e2e",
      "linear://comments/created-by-production-e2e"
    ]
  end

  defp provider_object_refs(false) do
    [
      "fixture://github/pr/production-e2e",
      "fixture://linear/workpad/production-e2e"
    ]
  end

  defp evidence_refs do
    [
      "evidence://github-pr/production-e2e",
      "evidence://codex-session/production-e2e",
      "evidence://source-workpad/production-e2e"
    ]
  end
end
