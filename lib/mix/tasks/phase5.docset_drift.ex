defmodule Mix.Tasks.Phase5.DocsetDrift do
  @moduledoc """
  Checks Phase 5 Stack Lab docset drift evidence.

  Pass `--docs-root` when the docs checkout is not at the local sibling path.
  """

  use Mix.Task

  @shortdoc "Checks Phase 5 Stack Lab docset drift evidence"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [docs_root: :string, json: :boolean])

    check_opts =
      case Keyword.get(opts, :docs_root) do
        nil -> []
        docs_root -> [docs_root: docs_root]
      end

    case StackLab.Phase5DocsetDrift.run(check_opts) do
      {:ok, result} ->
        print_success(result, Keyword.get(opts, :json, false))

      {:error, result} ->
        print_failure(result, Keyword.get(opts, :json, false))
        exit({:shutdown, 1})
    end
  end

  defp print_success(result, true), do: Mix.shell().info(Jason.encode!(result, pretty: true))

  defp print_success(result, false) do
    Mix.shell().info("phase5.docset_drift passed")
    Mix.shell().info("scenarios=#{Enum.join(result.release_manifest_scenario_ids, ",")}")
    Mix.shell().info("runbooks=#{length(result.runbook_readme_index)}")
    Mix.shell().info("source_backed=#{Enum.join(result.source_backed_scenario_ids, ",")}")
    Mix.shell().info("checker=#{result.checker_source_or_command_ref}")
    Mix.shell().info("checker_digest=#{result.checker_digest_or_commit_ref}")
  end

  defp print_failure(result, true), do: Mix.shell().error(Jason.encode!(result, pretty: true))

  defp print_failure(result, false) do
    Mix.shell().error("phase5.docset_drift failed")

    Enum.each(result.failures, fn failure ->
      Mix.shell().error("  #{inspect(failure)}")
    end)
  end
end
