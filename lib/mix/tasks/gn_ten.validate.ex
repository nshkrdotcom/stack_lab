defmodule Mix.Tasks.GnTen.Validate do
  @moduledoc "Validates the local gn-ten workspace manifest and proof matrix."

  use Mix.Task

  alias StackLab.GnTen.Manifest

  @shortdoc "Validates gn-ten manifest"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [manifest: :string, json: :boolean])

    manifest_path = Keyword.get(opts, :manifest, Manifest.default_path())
    json? = Keyword.get(opts, :json, false)

    case Manifest.validate_file(manifest_path) do
      {:ok, result} ->
        print_success(result, manifest_path, json?)

      {:error, failures} ->
        print_failure(failures, json?)
        exit({:shutdown, 1})
    end
  end

  defp print_success(result, _manifest_path, true) do
    result
    |> Map.put(:status, :pass)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_success(result, manifest_path, false) do
    Mix.shell().info("gn_ten.validate passed")
    Mix.shell().info("manifest=#{manifest_path}")
    Mix.shell().info("repos=#{Enum.join(result.repos, ",")}")
    Mix.shell().info("proof_matrix=#{result.proof_matrix}")
  end

  defp print_failure(failures, true) do
    %{status: :fail, failures: failures}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_failure(failures, false) do
    Mix.shell().error("gn_ten.validate failed")
    Enum.each(failures, &Mix.shell().error("  #{inspect(&1)}"))
  end
end
