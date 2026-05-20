defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.UnauthorizedLowerTraceRead do
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
      :app_kit_unauthorized_lower_trace_read,
      "tenant-app-kit-lower-backed-authz",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        unauthorized_context =
          request_context(
            env.tenant_id,
            env.context.trace_id,
            %{program_id: env.program.id, work_class_id: env.work_class.id},
            %{
              id: "inst-other",
              pack_slug: env.installation_ref.pack_slug,
              status: :active
            }
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:error, error} =
          OperatorSurface.get_unified_trace(
            unauthorized_context,
            execution_ref,
            env.surface_opts
          )

        {:ok,
         %{
           case: :unauthorized_lower_trace_read,
           tenant_id: env.tenant_id,
           installation_id: env.installation_ref.id,
           execution_id: lower_dispatch.execution.id,
           error: %{
             code: error.code,
             kind: error.kind,
             retryable: error.retryable
           }
         }}
      end
    )
  end
end
