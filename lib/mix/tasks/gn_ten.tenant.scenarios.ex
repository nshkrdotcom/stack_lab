defmodule Mix.Tasks.GnTen.Tenant.Scenarios do
  @moduledoc "Runs provider-free gn-ten tenant isolation scenarios."

  use Mix.Task

  alias StackLab.GnTen.TenantScenarios

  @shortdoc "Runs tenant isolation scenarios"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} = OptionParser.parse(args, strict: [json: :boolean])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    report = TenantScenarios.report()

    case TenantScenarios.validate_report(report) do
      :ok ->
        print_success(report, Keyword.get(opts, :json, false))

      {:error, failures} ->
        print_failure(failures, Keyword.get(opts, :json, false))
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
    Mix.shell().info("gn_ten.tenant.scenarios passed")
    Mix.shell().info("schema_version=#{report.schema_version}")
    Mix.shell().info("profile=#{report.profile}")
    Mix.shell().info("scenarios=#{Enum.map_join(report.scenarios, ",", & &1.id)}")
  end

  defp print_failure(failures, true) do
    %{status: :fail, failures: failures}
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_failure(failures, false) do
    Mix.shell().error("gn_ten.tenant.scenarios failed")
    Enum.each(failures, &Mix.shell().error("  #{inspect(&1)}"))
  end
end
