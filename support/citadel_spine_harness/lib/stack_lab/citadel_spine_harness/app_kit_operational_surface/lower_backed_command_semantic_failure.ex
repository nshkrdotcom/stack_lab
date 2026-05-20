defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.LowerBackedCommandSemanticFailure do
  @moduledoc false

  alias AppKit.Core.{ExecutionRef, PageRequest}
  alias AppKit.{OperatorSurface, ReviewSurface, WorkSurface}
  alias Mezzanine.AppKitBridge.SemanticFailureRecoveryService
  alias Mezzanine.Execution.ExecutionRecord
  alias OuterBrain.Contracts.SemanticFailure

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.{
    Environment,
    EvidenceWriter,
    Fixtures
  }

  alias StackLab.CitadelSpineHarness.TransportRuntime

  import Environment
  import EvidenceWriter
  import Fixtures

  def run do
    with_lower_backed_runtime(
      :app_kit_lower_backed_command_semantic_failure,
      "tenant-app-kit-lower-backed-semantic-failure",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        semantic_failure_carrier =
          semantic_failure_carrier!(
            env.tenant_id,
            lower_dispatch.execution.trace_id,
            lower_dispatch.execution.id
          )

        {:ok, failed_execution} =
          ExecutionRecord.record_semantic_failure(lower_dispatch.execution, %{
            lower_receipt: lower_dispatch.execution.lower_receipt,
            last_dispatch_error_payload: %{
              "error" => %{
                "kind" => "semantic_failure",
                "carrier" => SemanticFailure.to_payload(semantic_failure_carrier)
              }
            },
            trace_id: lower_dispatch.execution.trace_id,
            causation_id: "semantic-failure:#{lower_dispatch.execution.id}",
            actor_ref: %{kind: :reconciler}
          })

        {:ok, recovery} =
          SemanticFailureRecoveryService.recover_execution(env.tenant_id, failed_execution.id)

        {:ok, page_request} = PageRequest.new(%{limit: 10})

        {:ok, subject_detail} =
          WorkSurface.get_subject(env.context, env.subject_ref, env.surface_opts)

        {:ok, operator_projection} =
          OperatorSurface.subject_status(env.context, env.subject_ref, env.surface_opts)

        {:ok, pending_reviews} =
          ReviewSurface.list_pending(env.context, page_request, env.surface_opts)

        decision_ref = hd(pending_reviews.entries).decision_ref

        {:ok, review_detail} =
          ReviewSurface.get_review(env.context, decision_ref, env.surface_opts)

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: failed_execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: failed_execution.dispatch_state
          })

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(env.context, execution_ref, env.surface_opts)

        failed_execution_step = execution_trace_step!(unified_trace, failed_execution.id)

        {:ok,
         %{
           case: :lower_backed_command_semantic_failure,
           tenant_id: env.tenant_id,
           installation: %{
             created_status: env.install_result.status,
             installation_id: env.installation_ref.id,
             pack_slug: env.installation_ref.pack_slug
           },
           work: %{
             subject_id: env.subject_ref.id,
             run_id: env.run_result.payload.run_ref.run_id,
             state: env.run_result.state
           },
           dispatch: %{
             execution_id: failed_execution.id,
             classification: :semantic_failure,
             execution_state: failed_execution.dispatch_state,
             failure_kind: failed_execution.failure_kind,
             job_status: :completed
           },
           recovery: %{
             work_state: subject_detail.lifecycle_state,
             active_run_state: subject_detail.payload.active_run_status,
             pending_review_ids: Enum.map(subject_detail.pending_decision_refs, & &1.id),
             operator_lifecycle_state: operator_projection.lifecycle_state,
             operator_pending_decision_ids:
               Enum.map(operator_projection.pending_decision_refs, & &1.id),
             review_id: decision_ref.id,
             review_status: review_detail.status,
             review_recovery_kind:
               review_detail.payload.review_unit.decision_profile["recovery_kind"],
             timeline_kinds: Enum.map(operator_projection.payload.timeline, & &1.event_kind),
             recovery_review_created?: recovery.review_created?
           },
           trace: %{
             trace_id: unified_trace.trace_id,
             step_sources: Enum.map(unified_trace.steps, & &1.source),
             failed_execution:
               Map.merge(failed_execution_step, %{
                 semantic_failure_kind: semantic_failure_carrier_value(failed_execution, "kind"),
                 semantic_failure_retry_class:
                   semantic_failure_carrier_value(failed_execution, "retry_class"),
                 semantic_failure_trace_id:
                   semantic_failure_carrier_value(failed_execution, "request_trace_id")
               })
           }
         }}
      end
    )
  end
end
