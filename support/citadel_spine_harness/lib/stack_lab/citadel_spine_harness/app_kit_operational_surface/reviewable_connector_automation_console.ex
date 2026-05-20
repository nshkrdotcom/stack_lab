defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.ReviewableConnectorAutomationConsole do
  @moduledoc false

  alias AppKit.Core.{ExecutionRef, OperatorActionRequest, PageRequest}
  alias AppKit.{OperatorSurface, ReviewSurface, WorkSurface}
  alias Mezzanine.AppKitBridge.SemanticFailureRecoveryService
  alias Mezzanine.Audit.ExecutionLineageStore
  alias Mezzanine.Execution.ExecutionRecord
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.Leasing
  alias Mezzanine.StreamAttachHost
  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.LowerFactsStub

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.{
    Environment,
    EvidenceWriter,
    Fixtures
  }

  alias StackLab.CitadelSpineHarness.TransportRuntime

  @scenario_24_poll_interval_ms 250

  import Environment
  import EvidenceWriter
  import Fixtures

  def run do
    with_lower_backed_runtime(
      :reviewable_connector_automation_console,
      "tenant-reviewable-connector-automation",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:ok, page_request} = PageRequest.new(%{limit: 10})

        {:ok, listed_subjects} =
          WorkSurface.list_subjects(env.context, page_request, env.surface_opts)

        {:ok, read_lease} =
          OperatorSurface.issue_read_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              allowed_operations: [:fetch_submission_receipt],
              scope: %{"mode" => "connector_console_receipt"}
            )
          )

        {:ok, live_stream_lease} =
          OperatorSurface.issue_stream_attach_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              poll_interval_ms: @scenario_24_poll_interval_ms,
              scope: %{"mode" => "connector_console_live_stream"}
            )
          )

        live_stream_lease_id = live_stream_lease.lease_ref.id

        {:ok, live_host} =
          StreamAttachHost.start_link(
            lease_id: live_stream_lease_id,
            token: live_stream_lease.attach_token,
            authorization_scope: authorization_scope!(live_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        live_attach_cursor = await_stream_attached!(live_stream_lease_id)

        direct_receipt =
          direct_submission_receipt_read!(
            read_lease,
            lower_dispatch.acceptance.submission_key
          )

        {:ok, failed_execution} =
          ExecutionRecord.record_semantic_failure(lower_dispatch.execution, %{
            lower_receipt: lower_dispatch.execution.lower_receipt,
            last_dispatch_error_payload: %{
              "error" => %{
                "kind" => "semantic_failure",
                "reason" => "connector_schema_mismatch"
              }
            },
            trace_id: lower_dispatch.execution.trace_id,
            causation_id: "connector-console-semantic-failure:#{lower_dispatch.execution.id}",
            actor_ref: %{kind: :reconciler}
          })

        {:ok, recovery} =
          SemanticFailureRecoveryService.recover_execution(env.tenant_id, failed_execution.id)

        {:ok, case_file_before_pause} =
          connector_console_case_file(env.context, env.subject_ref, env.surface_opts)

        {:ok, pending_reviews_before} =
          ReviewSurface.list_pending(env.context, page_request, env.surface_opts)

        decision_ref = hd(pending_reviews_before.entries).decision_ref

        {:ok, review_detail_before} =
          ReviewSurface.get_review(env.context, decision_ref, env.surface_opts)

        {:ok, failed_execution_ref} =
          ExecutionRef.new(%{
            id: failed_execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: failed_execution.dispatch_state
          })

        trace_opts = Keyword.put(env.surface_opts, :lower_facts, LowerFactsStub)

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(env.context, failed_execution_ref, trace_opts)

        failed_execution_step = execution_trace_step!(unified_trace, failed_execution.id)

        {:ok, failed_lineage} = ExecutionLineageStore.fetch(failed_execution.id)

        {:ok, actions} =
          OperatorSurface.available_actions(env.context, env.subject_ref, env.surface_opts)

        chosen_action = choose_operator_action(actions, "pause")

        {:ok, action_request} =
          OperatorActionRequest.new(%{
            action_ref: chosen_action.action_ref,
            params: %{"reason" => "connector case triage"}
          })

        {:ok, pause_result} =
          OperatorSurface.apply_action(
            env.context,
            env.subject_ref,
            action_request,
            env.surface_opts
          )

        post_pause_read_error =
          Leasing.authorize_read(
            authorization_scope!(read_lease),
            read_lease.lease_ref.id,
            read_lease.lease_token,
            :fetch_submission_receipt,
            repo: ExecutionRepo
          )

        post_pause_stream_error =
          Leasing.authorize_stream_attach(
            authorization_scope!(live_stream_lease),
            live_stream_lease_id,
            live_stream_lease.attach_token,
            repo: ExecutionRepo
          )

        if Process.alive?(live_host) do
          GenServer.stop(live_host, :normal)
        end

        {:ok, review_action} =
          ReviewSurface.record_decision(
            env.context,
            decision_ref,
            %{decision: :accept, reason: "connector recovery approved"},
            env.surface_opts
          )

        {:ok, pending_reviews_after} =
          ReviewSurface.list_pending(env.context, page_request, env.surface_opts)

        {:ok, review_detail_after} =
          ReviewSurface.get_review(env.context, decision_ref, env.surface_opts)

        {:ok, case_file_after_review} =
          connector_console_case_file(env.context, env.subject_ref, env.surface_opts)

        {:ok,
         %{
           case: :reviewable_connector_automation_console,
           scenario: 42,
           tenant_id: env.tenant_id,
           whitepaper_use_case: :"18.2_reviewable_connector_automation",
           synthetic_shape: %{
             surface_kind: :connector_automation_console,
             differs_from: :single_product_operator_shell,
             product_posture: :reviewable_connector_automation
           },
           console: %{
             listed_subject_ids: Enum.map(listed_subjects.entries, & &1.subject_ref.id),
             pending_review_ids_before:
               Enum.map(pending_reviews_before.entries, & &1.decision_ref.id),
             pending_review_ids_after:
               Enum.map(pending_reviews_after.entries, & &1.decision_ref.id),
             recovery_review_created?: recovery.review_created?
           },
           automation_case: %{
             subject_id: env.subject_ref.id,
             run_id: env.run_result.payload.run_ref.run_id,
             lifecycle_state_before_pause: case_file_before_pause.lifecycle_state,
             lifecycle_state_after_review: case_file_after_review.lifecycle_state,
             blocker_kinds_before_pause: case_file_before_pause.blocker_kinds,
             blocker_kinds_after_review: case_file_after_review.blocker_kinds,
             next_step_kind_before_pause: case_file_before_pause.next_step_kind,
             next_step_kind_after_review: case_file_after_review.next_step_kind,
             current_execution_ref_before_pause: case_file_before_pause.current_execution_ref,
             current_execution_ref_after_review: case_file_after_review.current_execution_ref,
             lineage_execution_ref_before_pause: case_file_before_pause.lineage_execution_ref,
             lineage_execution_ref_after_review: case_file_after_review.lineage_execution_ref,
             pending_review_ids_before: case_file_before_pause.pending_review_ids,
             pending_review_ids_after: case_file_after_review.pending_review_ids
           },
           operator: %{
             available_action_kinds: Enum.map(actions, & &1.action_ref.action_kind),
             applied_action: pause_result.action_ref.action_kind,
             action_status: pause_result.status,
             invalidated_live_leases?:
               leases_invalidated?([post_pause_read_error, post_pause_stream_error])
           },
           review: %{
             decision_id: decision_ref.id,
             status_before: review_detail_before.status,
             status_after: review_detail_after.status,
             recovery_kind:
               review_detail_before.payload.review_unit.decision_profile["recovery_kind"],
             action_kind: review_action.action_ref.action_kind
           },
           lower_access: %{
             submission_key: direct_receipt.submission_key,
             submission_receipt_ref: direct_receipt.submission_receipt_ref,
             stream_attached_cursor: live_attach_cursor,
             live_stream_lease_id: live_stream_lease_id,
             post_pause_read: normalize_read_error(post_pause_read_error),
             post_pause_stream: normalize_read_error(post_pause_stream_error)
           },
           trace: %{
             trace_id: unified_trace.trace_id,
             step_sources: Enum.map(unified_trace.steps, & &1.source),
             lower_lineage: %{
               execution_id: failed_lineage.execution_id,
               ji_submission_key: failed_lineage.ji_submission_key,
               lower_run_id: failed_lineage.lower_run_id,
               lower_attempt_id: failed_lineage.lower_attempt_id,
               artifact_refs: failed_lineage.artifact_refs
             },
             failed_execution: failed_execution_step
           }
         }}
      end
    )
  end
end
