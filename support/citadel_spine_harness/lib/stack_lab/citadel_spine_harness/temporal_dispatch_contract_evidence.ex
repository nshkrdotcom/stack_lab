defmodule StackLab.CitadelSpineHarness.TemporalDispatchContractEvidence do
  @moduledoc false

  alias Mezzanine.WorkflowRuntime.TemporalDispatchContract
  alias Mezzanine.WorkflowRuntime.TemporalSupervisor
  alias Mezzanine.WorkflowRuntime.WorkflowStarterOutbox

  defmodule RecordingOutboxStore do
    @moduledoc false
    @behaviour Mezzanine.WorkflowRuntime.OutboxPersistence

    @impl true
    def record_start_outcome(original_row, outcome_row) do
      send(self(), {:stack_lab_temporal_outcome_persisted, original_row, outcome_row})
      :ok
    end
  end

  defmodule FailingOutboxStore do
    @moduledoc false
    @behaviour Mezzanine.WorkflowRuntime.OutboxPersistence

    @impl true
    def record_start_outcome(_original_row, _outcome_row), do: {:error, :store_down}
  end

  @spec run_case(:restart_replay_owner_evidence) :: {:ok, map()}
  def run_case(:restart_replay_owner_evidence) do
    contract = TemporalDispatchContract.contract()
    {:ok, outbox_row} = WorkflowStarterOutbox.new_row(outbox_attrs())
    outcome_row = outcome_row(outbox_row)

    {:ok, positive} =
      TemporalDispatchContract.restart_replay_evidence(lifecycle_attrs(),
        outbox_row: outbox_row,
        outcome_row: outcome_row,
        outbox_persistence: RecordingOutboxStore,
        worker_specs: worker_specs()
      )

    persisted? =
      receive do
        {:stack_lab_temporal_outcome_persisted, _original_row, persisted_row} ->
          persisted_row.dispatch_state == "started" and
            persisted_row.workflow_run_id == lifecycle_attrs().workflow_run_id
      after
        1_000 -> false
      end

    {:ok,
     %{
       case: :restart_replay_owner_evidence,
       contract: contract,
       stack_lab_role: :evidence_composer_not_owner,
       service_mode_gate: %{
         temporal_required?: true,
         owner_contract_consumed?: positive.contract_id == contract.id,
         lower_harness_only_rejected?:
           :lower_runtime_smoke_claimed_as_service_mode_evidence in contract.forbidden,
         outcome_persistence_observed?: persisted?,
         raw_history_absent?: not positive.raw_workflow_history_included?
       },
       positive: positive,
       negative_failures: negative_failures()
     }}
  end

  defp negative_failures do
    {:ok, outbox_row} = WorkflowStarterOutbox.new_row(outbox_attrs())

    missing_worker_specs = Enum.reject(worker_specs(), &(&1.task_queue == "mezzanine.hazmat"))

    {:error, missing_worker} =
      TemporalDispatchContract.restart_replay_evidence(lifecycle_attrs(),
        outbox_row: outbox_row,
        worker_specs: missing_worker_specs
      )

    {:ok, wrong_queue_row} =
      outbox_attrs()
      |> Map.put(:workflow_type, "agent_run")
      |> Map.put(:workflow_version, "agent-run.v1")
      |> WorkflowStarterOutbox.new_row()

    {:error, wrong_task_queue} =
      TemporalDispatchContract.restart_replay_evidence(lifecycle_attrs(),
        outbox_row: wrong_queue_row,
        worker_specs: worker_specs()
      )

    {:error, outcome_persistence} =
      TemporalDispatchContract.persisted_outcome_state_ref(outbox_row, outcome_row(outbox_row),
        outbox_persistence: FailingOutboxStore
      )

    %{
      missing_worker: missing_worker,
      wrong_task_queue: wrong_task_queue,
      outcome_persistence: outcome_persistence
    }
  end

  defp worker_specs do
    TemporalSupervisor.task_queue_specs(
      enabled?: true,
      address: "127.0.0.1:7233",
      namespace: "default",
      instance_base: Mezzanine.WorkflowRuntime.StackLabPhase6Temporal
    )
  end

  defp outcome_row(outbox_row) do
    Map.merge(Map.from_struct(outbox_row), %{
      dispatch_state: "started",
      workflow_run_id: lifecycle_attrs().workflow_run_id
    })
  end

  defp lifecycle_attrs do
    %{
      tenant_ref: "tenant-stack-lab",
      installation_ref: "installation-stack-lab",
      workspace_ref: "workspace-stack-lab",
      project_ref: "project-stack-lab",
      environment_ref: "env-sim",
      principal_ref: "principal-operator",
      system_actor_ref: "system-workflow",
      resource_ref: "resource-stack-lab-work",
      subject_ref: "subject-stack-lab-m6",
      workflow_id: "stack-lab-phase6-temporal-dispatch",
      workflow_run_id: "run-stack-lab-phase6-temporal-dispatch",
      workflow_type: "execution_attempt",
      workflow_version: "execution-attempt.v1",
      command_id: "cmd-stack-lab-m6",
      command_receipt_ref: "command-receipt-stack-lab-m6",
      workflow_input_ref: "claim://stack-lab/phase6/m6/workflow-input",
      lower_submission_ref: "lower-submission-stack-lab-m6",
      lower_idempotency_key: "lower-idem-stack-lab-m6",
      activity_call_ref: "activity-call-stack-lab-m6",
      authority_packet_ref: "authpkt-stack-lab-m6",
      permission_decision_ref: "decision-stack-lab-m6",
      idempotency_key: "idem-stack-lab-m6",
      trace_id: "trace-stack-lab-m6",
      correlation_id: "corr-stack-lab-m6",
      release_manifest_ref: "phase6-m6-temporal-dispatch-contract",
      retry_policy: %{max_attempts: 3},
      terminal_policy: "quarantine_late_receipts",
      routing_facts: %{review_required: false, risk_band: "low"}
    }
  end

  defp outbox_attrs do
    %{
      outbox_id: "outbox-stack-lab-m6",
      tenant_ref: "tenant-stack-lab",
      installation_ref: "installation-stack-lab",
      principal_ref: "principal-operator",
      resource_ref: "resource-stack-lab-work",
      command_receipt_ref: "command-receipt-stack-lab-m6",
      command_id: "cmd-stack-lab-m6",
      workflow_type: "execution_attempt",
      workflow_id: "stack-lab-phase6-temporal-dispatch",
      workflow_version: "execution-attempt.v1",
      workflow_input_version: "execution-attempt-input.v1",
      workflow_input_ref: "claim://stack-lab/phase6/m6/workflow-input",
      authority_packet_ref: "authpkt-stack-lab-m6",
      permission_decision_ref: "decision-stack-lab-m6",
      idempotency_key: "idem-stack-lab-m6",
      dedupe_scope: "tenant:tenant-stack-lab/resource:resource-stack-lab-work",
      trace_id: "trace-stack-lab-m6",
      correlation_id: "corr-stack-lab-m6",
      release_manifest_ref: "phase6-m6-temporal-dispatch-contract",
      payload_hash: "sha256:stack-lab-phase6-m6-workflow-input"
    }
  end
end
