defmodule Mix.Tasks.Phase5Prelim.EvidenceReport.Validate do
  @moduledoc """
  Generates and validates the Phase 5PRELIM evidence report.

  This task uses the same service-mode harness path as the executable tests.
  It expects the local Temporal substrate to be serving through the
  Mezzanine-owned `just dev-status` command.
  """

  use Mix.Task

  alias StackLab.CitadelSpineHarness

  @shortdoc "Validate the Phase 5PRELIM evidence report"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    case CitadelSpineHarness.exercise_prelim_service_mode(:m6_evidence_report) do
      {:ok, result} ->
        Mix.shell().info("Phase 5PRELIM evidence report validation passed")
        Mix.shell().info("schema_ref=#{result.schema_ref}")
        Mix.shell().info("scenario_count=#{length(result.report.scenario_results)}")

      {:error, reason} ->
        Mix.raise("Phase 5PRELIM evidence report validation failed: #{inspect(reason)}")
    end
  end
end
