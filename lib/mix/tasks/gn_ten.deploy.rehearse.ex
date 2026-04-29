defmodule Mix.Tasks.GnTen.Deploy.Rehearse do
  @moduledoc "Runs deterministic gn-ten single-node deployment rehearsals."

  use Mix.Task

  alias StackLab.GnTen.DeploymentDrills

  @shortdoc "Runs a gn-ten deployment rehearsal drill"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args, strict: [drill: :string, out: :string, force: :boolean])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    opts
    |> Keyword.fetch(:drill)
    |> rehearse(opts)
  end

  defp rehearse(:error, _opts), do: Mix.raise("expected --drill <id>")

  defp rehearse({:ok, drill}, opts) do
    drill_opts = [
      out_dir: Keyword.get(opts, :out, DeploymentDrills.default_out_dir()),
      force?: Keyword.get(opts, :force, false)
    ]

    case DeploymentDrills.rehearse(drill, drill_opts) do
      {:ok, result} -> print_result(result)
      {:error, error} -> Mix.raise("gn_ten.deploy.rehearse failed: #{inspect(error)}")
    end
  end

  defp print_result(%{drills: drills, drill_count: count}) do
    Mix.shell().info("gn_ten.deploy.rehearse wrote #{count} receipts")
    Enum.each(drills, &print_result/1)
  end

  defp print_result(result) do
    Mix.shell().info("gn_ten.deploy.rehearse wrote #{result.drill}")
    Mix.shell().info("markdown=#{result.markdown_path}")
    Mix.shell().info("json=#{result.json_path}")
  end
end
