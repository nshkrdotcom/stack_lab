defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.LowerBackedCommandTrace do
  @moduledoc false

  alias AppKit.Core.ExecutionRef
  alias AppKit.OperatorSurface

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.{
    Environment,
    EvidenceWriter
  }

  alias StackLab.CitadelSpineHarness.TransportRuntime

  import Environment
  import EvidenceWriter

  def run do
    with_lower_backed_runtime(
      :app_kit_lower_backed_command_trace,
      "tenant-app-kit-lower-backed",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        receipt_proof =
          lower_receipt_proof!(
            env.context,
            env.installation_ref.id,
            lower_dispatch.execution.id,
            lower_dispatch.acceptance.submission_key
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(
            env.context,
            execution_ref,
            Keyword.merge(
              env.surface_opts,
              lower_operations: [:fetch_submission_receipt]
            )
          )

        {:ok,
         %{
           case: :lower_backed_command_trace,
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
             execution_id: lower_dispatch.execution.id,
             classification: lower_dispatch.classification,
             job_status: lower_dispatch.job_status,
             submission_status: lower_dispatch.execution.submission_ref["status"],
             submission_key: lower_dispatch.acceptance.submission_key,
             submission_receipt_ref: lower_dispatch.acceptance.submission_receipt_ref
           },
           receipt_proof: receipt_proof,
           trace: %{
             trace_id: unified_trace.trace_id,
             step_sources: Enum.map(unified_trace.steps, & &1.source),
             join_keys: unified_trace.join_keys
           }
         }}
      end
    )
  end
end
