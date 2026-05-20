defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.AppKitOperationalSurface.Scenarios.{
    GovernedAgentWorkloadContract,
    InstallIngestReviewTrace,
    LeasedDirectReadAndStreamInvalidation,
    LowerBackedCommandSemanticFailure,
    LowerBackedCommandTerminalRejection,
    LowerBackedCommandTrace,
    ObservabilityTraceJoinContinuity,
    ReviewableConnectorAutomationConsole,
    UnauthorizedLowerTraceRead
  }

  @type case_name ::
          :install_ingest_review_trace
          | :governed_agent_workload_contract
          | :lower_backed_command_trace
          | :lower_backed_command_terminal_rejection
          | :lower_backed_command_semantic_failure
          | :reviewable_connector_automation_console
          | :leased_direct_read_and_stream_invalidation
          | :observability_trace_join_continuity
          | :unauthorized_lower_trace_read

  @spec run_case(case_name()) :: {:ok, map()} | {:error, term()}
  def run_case(:install_ingest_review_trace), do: run_scenario(InstallIngestReviewTrace)

  def run_case(:governed_agent_workload_contract),
    do: run_scenario(GovernedAgentWorkloadContract)

  def run_case(:lower_backed_command_trace), do: run_scenario(LowerBackedCommandTrace)

  def run_case(:lower_backed_command_terminal_rejection),
    do: run_scenario(LowerBackedCommandTerminalRejection)

  def run_case(:lower_backed_command_semantic_failure),
    do: run_scenario(LowerBackedCommandSemanticFailure)

  def run_case(:reviewable_connector_automation_console),
    do: run_scenario(ReviewableConnectorAutomationConsole)

  def run_case(:leased_direct_read_and_stream_invalidation),
    do: run_scenario(LeasedDirectReadAndStreamInvalidation)

  def run_case(:observability_trace_join_continuity),
    do: run_scenario(ObservabilityTraceJoinContinuity)

  def run_case(:unauthorized_lower_trace_read), do: run_scenario(UnauthorizedLowerTraceRead)

  defp run_scenario(module) do
    with {:ok, result} <- module.run() do
      {:ok, attach_receipt(result)}
    end
  end

  defp attach_receipt(%{case: case_name} = result) do
    Map.put(result, :receipt, %{
      receipt_ref: "receipt://stack-lab/app-kit-operational-surface/#{case_name}",
      case: case_name,
      scenario: Map.get(result, :scenario),
      status: :succeeded,
      tenant_id: Map.get(result, :tenant_id),
      evidence_groups:
        result
        |> Map.keys()
        |> Enum.reject(&(&1 == :receipt))
        |> Enum.sort()
    })
  end
end
