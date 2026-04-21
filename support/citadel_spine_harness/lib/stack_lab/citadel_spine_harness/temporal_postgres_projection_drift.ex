defmodule StackLab.CitadelSpineHarness.TemporalPostgresProjectionDrift do
  @moduledoc false

  alias Mezzanine.WorkflowDescription
  alias Mezzanine.WorkflowQueryResult
  alias Mezzanine.WorkflowRuntime.ProjectionReconciliation
  alias Mezzanine.WorkflowRuntime.WorkflowFanoutFanin

  @scenario 201
  @runbook "runbooks/temporal_postgres_projection_drift.md"
  @runtime_envelope %{
    runtime_class: :temporal_postgres_integration,
    expected_local_max_ms: 120_000,
    ci_timeout_ms: 180_000,
    measurement_scope: :fixture_after_mezzanine_temporal_preflight_and_service_health,
    timeout_safe_action: :fail_milestone_and_capture_temporal_postgres_diagnostics
  }
  @release_manifest_ref "targeted_proofs[0]/stack_lab_runtime_envelopes[0]"

  @spec run_case(:temporal_postgres_projection_drift) :: {:ok, map()}
  def run_case(:temporal_postgres_projection_drift) do
    compact_temporal = compact_temporal_lookup()

    {:ok, active_projection} =
      ProjectionReconciliation.authorize_lifecycle_projection(
        %{workflow_id: compact_temporal.workflow_id, postgres_state: "accepted_active"},
        compact_temporal.state
      )

    {:ok, terminal_projection} =
      ProjectionReconciliation.authorize_lifecycle_projection(
        %{workflow_id: "workflow-terminal-201", postgres_state: "completed"},
        %{
          description: %{status: "completed"},
          query: %{summary: %{workflow_state: "completed", terminal_event_ref: "event-terminal"}}
        }
      )

    {:ok,
     %{
       case: :temporal_postgres_projection_drift,
       scenario: @scenario,
       runbook: @runbook,
       release_manifest_ref: @release_manifest_ref,
       runtime_envelope: @runtime_envelope,
       positive_path: %{
         compact_temporal_lookup: compact_temporal.evidence,
         active_projection: active_projection,
         temporal_terminal_projection: terminal_projection,
         outbox_drain_plan: outbox_drain_evidence(),
         dispatch_state_reduction: dispatch_state_reduction_evidence(),
         fanout_fanin: fanout_fanin_positive_evidence()
       },
       negative_failures: %{
         drift_actions: drift_action_evidence(),
         conflicting_terminal: conflicting_terminal_evidence(),
         missing_terminal_event_ref: missing_terminal_event_ref_evidence(),
         workflow_start_outbox_bypass: workflow_start_outbox_bypass_evidence(),
         unreduced_dispatch_states: unreduced_dispatch_state_evidence(),
         fanout_late_duplicate_close: fanout_late_duplicate_evidence()
       }
     }}
  end

  defmodule CompactRuntime do
    @moduledoc false
    @behaviour Mezzanine.WorkflowRuntime

    @impl true
    def start_workflow(_request), do: {:error, :not_used}

    @impl true
    def signal_workflow(_request), do: {:error, :not_used}

    @impl true
    def query_workflow(request) do
      {:ok,
       %WorkflowQueryResult{
         workflow_ref: "workflow://#{request.workflow_id}",
         query_name: request.query_name,
         state_ref: "workflow-state://#{request.workflow_id}",
         summary: %{
           workflow_state: "accepted_active",
           workflow_version: "execution-attempt.v1",
           last_observed_workflow_event_ref: "event-201"
         },
         trace_id: "trace-scenario-201"
       }}
    end

    @impl true
    def cancel_workflow(_request), do: {:error, :not_used}

    @impl true
    def describe_workflow(request) do
      {:ok,
       %WorkflowDescription{
         workflow_ref: "workflow://#{request.workflow_id}",
         status: "running",
         search_attributes: %{
           "phase5.workflow_version" => "execution-attempt.v1",
           "phase5.release_manifest_ref" => request.release_manifest_ref
         },
         trace_id: "trace-scenario-201"
       }}
    end

    @impl true
    def fetch_workflow_history_ref(_request), do: {:error, :raw_history_not_used}
  end

  defp compact_temporal_lookup do
    candidate = %{
      workflow_id: "tenant:tenant-1:execution:exec-201:attempt:1",
      workflow_run_id: "run-201",
      workflow_type: "execution_attempt",
      workflow_version: "execution-attempt.v1"
    }

    {:ok, state} = ProjectionReconciliation.lookup_temporal_state(candidate, CompactRuntime)

    requests = ProjectionReconciliation.temporal_lookup_requests(candidate)

    %{
      workflow_id: candidate.workflow_id,
      state: state,
      evidence: %{
        lookup_operations: Enum.map(requests, & &1.operation),
        query_name: state.query_name,
        workflow_run_id: state.workflow_run_id,
        compact_status: state.description.status,
        compact_projection_state: state.query.summary.workflow_state,
        raw_history?: state.raw_history?,
        last_observed_workflow_event_ref: state.query.summary.last_observed_workflow_event_ref
      }
    }
  end

  defp outbox_drain_evidence do
    plan = ProjectionReconciliation.outbox_drain_plan()
    retirement_gate = ProjectionReconciliation.workflow_starter_retirement_gate()

    %{
      retryable_states: plan.retryable_states,
      evidence_only_states: plan.evidence_only_states,
      invalid_row_action: plan.invalid_row_action,
      start_authority: plan.start_authority,
      forbidden_worker_authority: plan.forbidden_worker_authority,
      retirement_gate: retirement_gate,
      legacy_worker_allowed?: plan.forbidden_worker_authority != :workflow_lifecycle_decision
    }
  end

  defp dispatch_state_reduction_evidence do
    reduction = ProjectionReconciliation.dispatch_state_reduction_profile()

    %{
      active_targets: reduction.active_targets,
      legacy_aliases: reduction.legacy_aliases,
      evidence_fields: reduction.evidence_fields,
      new_legacy_writes_allowed?: reduction.new_legacy_writes_allowed?,
      reader_policy: reduction.reader_policy,
      drain_gate: reduction.drain_gate
    }
  end

  defp drift_action_evidence do
    ProjectionReconciliation.drift_actions()
    |> Enum.map(fn action ->
      %{
        drift_class: action.drift_class,
        detection: action.detection,
        automatic_repair: action.automatic_repair,
        operator_repair: action.operator_repair,
        safe_operator_action: action.safe_operator_action,
        sla: action.sla
      }
    end)
  end

  defp conflicting_terminal_evidence do
    {:error, evidence} =
      ProjectionReconciliation.authorize_lifecycle_projection(
        %{workflow_id: "workflow-conflicting-terminal", postgres_state: "cancelled"},
        %{description: %{status: "running"}, query: %{summary: %{workflow_state: "running"}}}
      )

    evidence
  end

  defp missing_terminal_event_ref_evidence do
    {:error, evidence} =
      ProjectionReconciliation.authorize_lifecycle_projection(
        %{workflow_id: "workflow-missing-terminal-event", postgres_state: "completed"},
        %{
          description: %{status: "completed"},
          query: %{summary: %{workflow_state: "completed"}}
        }
      )

    evidence
  end

  defp workflow_start_outbox_bypass_evidence do
    plan = ProjectionReconciliation.outbox_drain_plan()

    %{
      legacy_direct_enqueue: classify_workflow_start_writer(:legacy_direct_enqueue, plan),
      oban_lifecycle_worker: classify_workflow_start_writer(:oban_lifecycle_worker, plan),
      workflow_runtime_adapter:
        classify_workflow_start_writer(:workflow_runtime_delivery_adapter, plan),
      started_state_authority: classify_outbox_state_authority("started", plan),
      duplicate_started_state_authority:
        classify_outbox_state_authority("duplicate_started", plan)
    }
  end

  defp unreduced_dispatch_state_evidence do
    reduction = ProjectionReconciliation.dispatch_state_reduction_profile()

    %{
      legacy_aliases: reduction.legacy_aliases,
      writable?: reduction.new_legacy_writes_allowed?,
      drain_gate: reduction.drain_gate,
      safe_action: :fail_closed_after_strict_greenfield_cutover
    }
  end

  defp fanout_fanin_positive_evidence do
    state =
      fanout_input()
      |> WorkflowFanoutFanin.new_parent_state!()
      |> apply_completion!("branch-a", "complete-a-1")
      |> apply_completion!("branch-b", "complete-b-1")

    duplicate_state = elem_apply(state, completion("branch-b", "complete-b-1"))

    %{
      status: state.status,
      close_count: state.close_count,
      close_decision: state.close_decision,
      close_event_ref: state.close_event_ref,
      duplicate_close_count: duplicate_state.close_count,
      duplicate_completion_count: duplicate_state.duplicate_completion_count,
      operator_query: WorkflowFanoutFanin.operator_query(duplicate_state)
    }
  end

  defp fanout_late_duplicate_evidence do
    state =
      fanout_input(%{join_policy: :k_of_n, required_success_count: 1})
      |> WorkflowFanoutFanin.new_parent_state!()
      |> apply_completion!("branch-a", "complete-a-1")

    duplicate_state = elem_apply(state, completion("branch-a", "complete-a-1"))

    late_completion =
      completion("branch-b", "complete-b-late", :failed)
      |> Map.merge(%{
        failure_class: :child_workflow_timeout,
        safe_action: :retry_optional_branch,
        compensation_ref: "compensation://scenario-201/branch-b"
      })

    {:ok, late_state, [late_event]} =
      WorkflowFanoutFanin.apply_completion(duplicate_state, late_completion)

    %{
      close_count: late_state.close_count,
      close_decision: late_state.close_decision,
      duplicate_completion_count: duplicate_state.duplicate_completion_count,
      late_completion_count: late_state.late_completion_count,
      late_event: late_event,
      failure_summary: WorkflowFanoutFanin.failure_summary(late_state)
    }
  end

  defp classify_workflow_start_writer(:workflow_runtime_delivery_adapter, plan) do
    %{
      accepted?: plan.start_authority == :mezzanine_workflow_runtime_idempotency,
      authority: plan.start_authority,
      safe_action: :drain_through_workflow_runtime_idempotency
    }
  end

  defp classify_workflow_start_writer(_legacy_writer, plan) do
    %{
      accepted?: false,
      forbidden_worker_authority: plan.forbidden_worker_authority,
      safe_action: :quarantine_or_dead_letter
    }
  end

  defp classify_outbox_state_authority(state, plan) do
    if state in plan.evidence_only_states do
      :delivery_evidence_only
    else
      :requires_workflow_runtime_idempotency_or_quarantine
    end
  end

  defp apply_completion!(state, branch_ref, completion_ref) do
    elem_apply(state, completion(branch_ref, completion_ref))
  end

  defp elem_apply(state, completion) do
    {:ok, next_state, _events} = WorkflowFanoutFanin.apply_completion(state, completion)
    next_state
  end

  defp fanout_input(overrides \\ %{}) do
    Map.merge(
      %{
        tenant_ref: "tenant-1",
        resource_ref: "work-object-201",
        trace_id: "trace-scenario-201",
        parent_workflow_ref: %{workflow_id: "parent-workflow-201", workflow_version: "v1"},
        fanout_group_ref: "fanout-group-201",
        idempotency_scope: "scenario-201",
        authority_context: %{authority_packet_ref: "authority-scenario-201"},
        release_manifest_ref: @release_manifest_ref,
        join_policy: :all_required,
        branches: [
          branch("branch-a", required?: true),
          branch("branch-b", required?: true)
        ]
      },
      overrides
    )
  end

  defp branch(branch_ref, opts) do
    %{
      branch_ref: branch_ref,
      tenant_ref: "tenant-1",
      resource_ref: "work-object-201",
      trace_id: "trace-scenario-201",
      parent_workflow_ref: %{workflow_id: "parent-workflow-201", workflow_version: "v1"},
      child_workflow_ref: %{workflow_id: "child-workflow-#{branch_ref}"},
      idempotency_scope: "scenario-201:#{branch_ref}",
      authority_context: %{authority_packet_ref: "authority-scenario-201"},
      required?: Keyword.fetch!(opts, :required?),
      release_manifest_ref: @release_manifest_ref
    }
  end

  defp completion(branch_ref, completion_ref, status \\ :completed) do
    %{
      branch_ref: branch_ref,
      completion_ref: completion_ref,
      completion_idempotency_key: completion_ref,
      status: status,
      completed_at: ~U[2026-04-20 20:10:00Z],
      terminal_event_ref: "event://#{completion_ref}"
    }
  end
end
