defmodule Mix.Tasks.Phase6.EvidenceReport.Validate do
  @moduledoc """
  Generates and validates the Phase 6 simulation evidence report.
  """

  use Mix.Task

  alias StackLab.CitadelSpineHarness

  @shortdoc "Validate the Phase 6 simulation evidence report"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    case CitadelSpineHarness.exercise_phase6_evidence_report(:validated_report) do
      {:ok, result} ->
        Mix.shell().info("Phase 6 evidence report validation passed")
        Mix.shell().info("schema_ref=#{result.schema_ref}")
        Mix.shell().info("source_repo_count=#{length(result.report["source_repos"])}")
        Mix.shell().info("negative_control_count=#{map_size(result.negative_failures)}")

      {:error, reason} ->
        Mix.raise("Phase 6 evidence report validation failed: #{inspect(reason)}")
    end
  end
end
