defmodule Mix.Tasks.GnTen.Status do
  @moduledoc "Reports read-only status for the main-only gn-ten workspace."

  use Mix.Task

  alias StackLab.GnTen.Manifest
  alias StackLab.GnTen.Status

  @shortdoc "Reports gn-ten workspace status"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [manifest: :string, json: :boolean])

    manifest_path = Keyword.get(opts, :manifest, Manifest.default_path())
    json? = Keyword.get(opts, :json, false)

    case Status.check(manifest_path) do
      {:ok, result} ->
        print_result(result, json?)

      {:error, %{repos: _repos} = result} ->
        print_result(result, json?)
        exit({:shutdown, 1})

      {:error, failures} ->
        print_manifest_failures(failures, json?)
        exit({:shutdown, 1})
    end
  end

  defp print_result(result, true) do
    result
    |> Map.put(:status, status(result))
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_result(result, false) do
    Mix.shell().info("gn_ten.status #{status(result)}")
    Mix.shell().info("workspace=#{result.workspace_ref}")
    Mix.shell().info("branch_policy=#{result.branch_policy}")

    Enum.each(result.repos, fn repo ->
      Mix.shell().info(
        "#{repo.name}: branch=#{repo.actual_branch || "unknown"} expected=#{repo.expected_branch} " <>
          "dirty?=#{repo.dirty?} sha=#{repo.head_sha || "unknown"}"
      )
    end)

    Enum.each(result.failures, &Mix.shell().error("  #{inspect(&1)}"))
  end

  defp print_manifest_failures(failures, true) do
    %{status: :fail, failures: failures}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_manifest_failures(failures, false) do
    Mix.shell().error("gn_ten.status failed before repo status checks")
    Enum.each(failures, &Mix.shell().error("  #{inspect(&1)}"))
  end

  defp status(%{clean?: true}), do: :pass
  defp status(%{clean?: false}), do: :fail
end
