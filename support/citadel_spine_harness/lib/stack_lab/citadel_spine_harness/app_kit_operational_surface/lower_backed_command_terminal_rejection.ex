defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.LowerBackedCommandTerminalRejection do
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
      :app_kit_lower_backed_command_terminal_rejection,
      "tenant-app-kit-lower-backed-reject",
      fn env ->
        :ok =
          TransportRuntime.put!(
            lower_transport_config(self(), env.subject_ref.id, :scope_rejection)
          )

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

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(env.context, execution_ref, env.surface_opts)

        rejected_execution = execution_trace_step!(unified_trace, lower_dispatch.execution.id)

        {:ok,
         %{
           case: :lower_backed_command_terminal_rejection,
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
             execution_state: lower_dispatch.execution.dispatch_state,
             job_status: lower_dispatch.job_status,
             terminal_rejection_reason: lower_dispatch.execution.terminal_rejection_reason,
             rejection_reason: rejection_reason(lower_dispatch.rejection),
             rejection_family:
               if lower_dispatch.rejection do
                 to_string(lower_dispatch.rejection.rejection_family)
               end
           },
           trace: %{
             trace_id: unified_trace.trace_id,
             step_sources: Enum.map(unified_trace.steps, & &1.source),
             rejected_execution: rejected_execution
           }
         }}
      end
    )
  end
end
