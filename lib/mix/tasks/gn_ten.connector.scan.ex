defmodule Mix.Tasks.GnTen.Connector.Scan do
  @moduledoc "Scans gn-ten provider and connector boundary posture."

  use Mix.Task

  alias StackLab.GnTen.ConnectorScanner

  @shortdoc "Scans provider/connector boundaries"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [root: :string, mode: :string, json: :boolean, all_repos: :boolean]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    if Keyword.get(opts, :all_repos, false) do
      run_all_repos(opts)
    else
      run_single_root(opts)
    end
  end

  defp run_single_root(opts) do
    scan_opts = [
      root: Keyword.get(opts, :root, File.cwd!()),
      mode: Keyword.get(opts, :mode, "all")
    ]

    case ConnectorScanner.scan(scan_opts) do
      {:ok, report} ->
        print_success(report, Keyword.get(opts, :json, false))

      {:error, report} ->
        print_failure(report, Keyword.get(opts, :json, false))
        exit({:shutdown, 1})
    end
  end

  defp run_all_repos(opts) do
    case ConnectorScanner.scan_all_repos() do
      {:ok, report} ->
        print_all_success(report, Keyword.get(opts, :json, false))

      {:error, report} ->
        print_all_failure(report, Keyword.get(opts, :json, false))
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
    Mix.shell().info("gn_ten.connector.scan passed")
    Mix.shell().info("root=#{report.root}")
    Mix.shell().info("mode=#{report.mode}")
    Mix.shell().info("checked_files=#{report.checked_files}")
  end

  defp print_failure(report, true) do
    report
    |> Map.update!(:violations, &Enum.map(&1, fn violation -> Map.from_struct(violation) end))
    |> Map.put(:status, :fail)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_failure(report, false) do
    Mix.shell().error("gn_ten.connector.scan failed")
    Mix.shell().error("root=#{report.root}")
    Mix.shell().error("mode=#{report.mode}")
    Mix.shell().error("checked_files=#{report.checked_files}")
    Enum.each(report.violations, &Mix.shell().error("  #{ConnectorScanner.format_violation(&1)}"))
  end

  defp print_all_success(report, true) do
    report
    |> Map.put(:status, :pass)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp print_all_success(report, false) do
    Mix.shell().info("gn_ten.connector.scan --all-repos passed")

    Enum.each(report.repo_reports, fn repo ->
      Mix.shell().info(
        "#{repo.repo}: mode=#{repo.mode} checked_files=#{repo.checked_files} violations=0"
      )
    end)
  end

  defp print_all_failure(report, true) do
    report
    |> Map.put(:status, :fail)
    |> Jason.encode!(pretty: true)
    |> Mix.shell().error()
  end

  defp print_all_failure(report, false) do
    Mix.shell().error("gn_ten.connector.scan --all-repos failed")
    Enum.each(report.failures, &Mix.shell().error("  #{inspect(&1)}"))
  end
end
