defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.ObservabilityTraceJoinContinuity do
  @moduledoc false

  alias AppKit.Core.ExecutionRef
  alias AppKit.OperatorSurface
  alias Mezzanine.Archival.Scheduler
  alias StackLab.CitadelSpineHarness.AITraceClaimCheckTraceContinuity
  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.LowerFactsStub

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support.{
    Environment,
    EvidenceWriter,
    RepoSandbox
  }

  alias StackLab.CitadelSpineHarness.TransportRuntime

  @scenario_19_archive_now ~U[2026-04-16 12:00:00Z]

  import Environment
  import EvidenceWriter
  import RepoSandbox

  def run do
    with_lower_backed_runtime(
      :observability_trace_join_continuity,
      "tenant-observability-trace-join",
      fn env ->
        telemetry_handler_id = "stack-lab-scenario19-#{System.unique_integer([:positive])}"

        attach_observability_telemetry!(telemetry_handler_id, self())

        try do
          :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

          {:ok, lower_dispatch} =
            lower_backed_dispatch(
              env.context,
              env.installation_ref,
              env.subject_ref,
              env.run_result
            )

          trace_id = lower_dispatch.execution.trace_id
          execution_id = lower_dispatch.execution.id

          trace_graph =
            enrich_subject_trace_graph!(
              env.installation_ref.id,
              env.subject_ref.id,
              execution_id,
              trace_id
            )

          {:ok, execution_ref} =
            ExecutionRef.new(%{
              id: execution_id,
              subject_ref: env.subject_ref,
              recipe_ref: "expense_capture",
              dispatch_state: :completed
            })

          trace_opts = Keyword.put(env.surface_opts, :lower_facts, LowerFactsStub)

          {:ok, live_trace} =
            OperatorSurface.get_unified_trace(
              env.context,
              execution_ref,
              trace_opts
            )

          live_lower_fetches = collect_lower_fetch_messages!()

          {:ok, trace_surfaces} =
            AITraceClaimCheckTraceContinuity.prove_trace_surfaces(
              trace_id,
              env.tenant_id,
              execution_id,
              label: :observability_trace_join_continuity
            )

          execution_plane_backfill =
            emit_execution_plane_backfill!(trace_id, env.tenant_id)

          :ok = emit_citadel_trace_failure!(trace_id, env.tenant_id, execution_id)

          {:ok, archival_result} =
            Scheduler.archive_subject(
              env.installation_ref.id,
              env.subject_ref.id,
              now: @scenario_19_archive_now
            )

          archived_hot_reads =
            assert_archived_hot_reads!(
              env.context,
              env.subject_ref,
              env.surface_opts,
              archival_result.manifest_ref
            )

          {:ok, archived_trace} =
            OperatorSurface.get_unified_trace(
              env.context,
              execution_ref,
              trace_opts
            )

          archived_pivot_traces =
            archived_pivot_summaries!(
              env.installation_ref.id,
              %{
                trace_id: trace_id,
                subject_id: env.subject_ref.id,
                execution_id: execution_id,
                decision_id: trace_graph.decision_id,
                run_id: "run-#{execution_id}",
                attempt_id: "attempt-#{execution_id}",
                artifact_id: "artifact-#{execution_id}",
                manifest_ref: archival_result.manifest_ref
              }
            )

          archived_lower_fetches = collect_lower_fetch_messages!()
          Process.sleep(50)
          telemetry_events = collect_observability_telemetry!()
          telemetry = summarize_observability_telemetry!(telemetry_events)

          {:ok,
           %{
             case: :observability_trace_join_continuity,
             scenario: 19,
             tenant_id: env.tenant_id,
             installation_id: env.installation_ref.id,
             subject_id: env.subject_ref.id,
             execution_id: execution_id,
             trace_id: trace_id,
             live_path: %{
               request_edge_trace_id: env.context.trace_id,
               mezzanine_trace_id: lower_dispatch.execution.trace_id,
               lower_gateway_trace_id: lower_dispatch.gateway.trace_id,
               classification: lower_dispatch.classification,
               submission_key: lower_dispatch.acceptance.submission_key,
               step_sources: Enum.map(live_trace.steps, & &1.source),
               join_keys: live_trace.join_keys
             },
             telemetry: telemetry,
             execution_plane_backfill: execution_plane_backfill,
             claim_check: trace_surfaces.claim_check,
             execution_plane: trace_surfaces.execution_plane,
             aitrace: trace_surfaces.aitrace,
             archival: %{
               manifest_ref: archival_result.manifest_ref,
               hot_read_errors: archived_hot_reads,
               trace_id: archived_trace.trace_id,
               archived_manifest_ref: archived_trace.metadata.archived_manifest_ref,
               step_sources: Enum.map(archived_trace.steps, & &1.source),
               staleness_classes:
                 archived_trace.steps
                 |> Enum.map(& &1.staleness_class)
                 |> Enum.uniq()
                 |> Enum.sort(),
               join_keys: archived_trace.join_keys,
               live_lower_fetches: live_lower_fetches,
               archived_lower_fetches: archived_lower_fetches,
               pivot_traces: archived_pivot_traces,
               wrong_installation_pivot_error:
                 archived_pivot_error!(
                   Ecto.UUID.generate(),
                   :trace_id,
                   trace_id
                 )
             }
           }}
        after
          :telemetry.detach(telemetry_handler_id)
        end
      end
    )
  end
end
