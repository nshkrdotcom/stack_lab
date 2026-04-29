defmodule Mix.Tasks.GnTen.Deploy.Report do
  @moduledoc "Reports gn-ten deployment rehearsal receipt status."

  use Mix.Task

  alias StackLab.GnTen.DeploymentDrills

  @shortdoc "Reports gn-ten deployment rehearsal receipt status"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: [dir: :string, json: :boolean])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    report_opts = [out_dir: Keyword.get(opts, :dir, DeploymentDrills.default_out_dir())]

    case DeploymentDrills.report(report_opts) do
      {:ok, report} -> print_success(report, Keyword.get(opts, :json, false))
      {:error, report} -> print_failure(report, Keyword.get(opts, :json, false))
    end
  end

  defp print_success(report, true), do: Mix.shell().info(Jason.encode!(report, pretty: true))

  defp print_success(report, false) do
    Mix.shell().info("gn_ten.deploy.report passed")
    Mix.shell().info("profile=#{report["profile"]}")
    Mix.shell().info("drill_count=#{report["drill_count"]}")

    Enum.each(report["receipts"], fn receipt ->
      Mix.shell().info("receipt=#{receipt["drill"]} path=#{receipt["path"]}")
    end)
  end

  defp print_failure(report, true) do
    Mix.shell().error(Jason.encode!(report, pretty: true))
    exit({:shutdown, 1})
  end

  defp print_failure(report, false) do
    Mix.shell().error("gn_ten.deploy.report failed")
    Enum.each(report["failures"], &Mix.shell().error("  #{inspect(&1)}"))
    exit({:shutdown, 1})
  end
end
