defmodule Mix.Tasks.GnTen.RepoAgents.Validate do
  @moduledoc "Validates gn-ten repo-agent instruction drift."

  use Mix.Task

  alias StackLab.GnTen.RepoAgentInstructions

  @shortdoc "Validates gn-ten repo-agent instructions"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args, strict: [json: :boolean, drafts_root: :string])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    validate_opts =
      opts
      |> Keyword.take([:drafts_root])
      |> Keyword.new(fn
        {:drafts_root, root} -> {:drafts_root, root}
      end)

    json? = Keyword.get(opts, :json, false)

    case RepoAgentInstructions.validate(validate_opts) do
      {:ok, report} ->
        print_success(report, json?)

      {:error, report} ->
        print_failure(report, json?)
        exit({:shutdown, 1})
    end
  end

  defp print_success(report, true) do
    report
    |> Map.put(:status, :pass)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_success(report, false) do
    Mix.shell().info("gn_ten.repo_agents.validate passed")
    Mix.shell().info("repos=#{report.repo_count}")
  end

  defp print_failure(report, true) do
    report
    |> Map.put(:status, :fail)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_failure(report, false) do
    Mix.shell().error("gn_ten.repo_agents.validate failed")
    Enum.each(report.failures, &Mix.shell().error("  #{inspect(&1)}"))
  end
end
