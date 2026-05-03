defmodule StackLab.GnTen.TenantScanner do
  @moduledoc """
  Source scanner for gn-ten tenant-boundary posture.

  The scanner is intentionally narrow. It catches direct persistent queries
  that do not carry tenant language and credential lease records that do not
  carry an explicit tenant id/ref at construction or schema definition time.
  """

  alias StackLab.GnTen.Manifest

  defmodule Violation do
    @moduledoc "One tenant scanner violation."

    @enforce_keys [:code, :path, :line, :snippet]
    defstruct [:code, :path, :line, :snippet]

    @type t :: %__MODULE__{
            code: atom(),
            path: Path.t(),
            line: pos_integer(),
            snippet: String.t()
          }
  end

  @query_terms ~w(Repo.all Repo.one Repo.get Repo.get_by Repo.exists?)
  @query_file_markers ["@gn_ten_tenant_scoped", "@tenant_scoped"]
  @lease_constructor_terms ~w(CredentialLease.new CredentialLease.new! LeaseRecord.new LeaseRecord.new!)
  @tenant_terms ~w(tenant_id tenant_ref TenantScope)
  @ignored_segments MapSet.new([".git", "_build", "deps", "doc", "dist", "test"])
  @source_roots ~w(lib core apps connectors bridges surfaces)
  @query_repos ~w(mezzanine citadel outer_brain app_kit)
  @lease_repos ~w(jido_integration)

  @type mode :: :all | :query | :lease
  @type scan_option :: {:root, Path.t()} | {:mode, mode() | String.t()}
  @type report :: %{
          root: Path.t(),
          mode: mode(),
          checked_files: non_neg_integer(),
          violations: [Violation.t()]
        }

  @spec scan([scan_option()]) :: {:ok, report()} | {:error, report()}
  def scan(opts \\ []) do
    root = opts |> Keyword.get(:root, File.cwd!()) |> Path.expand()
    mode = opts |> Keyword.get(:mode, :all) |> normalize_mode!()
    files = source_files(root)

    violations =
      files
      |> Enum.flat_map(&scan_file(&1, mode))
      |> Enum.sort_by(&{&1.path, &1.line, &1.code})

    report = %{
      root: root,
      mode: mode,
      checked_files: length(files),
      violations: violations
    }

    if violations == [] do
      {:ok, report}
    else
      {:error, report}
    end
  end

  @spec scan_all_repos(keyword()) :: {:ok, map()} | {:error, map()}
  def scan_all_repos(opts \\ []) do
    manifest_path = Keyword.get(opts, :manifest, Manifest.default_path())

    case Manifest.validate_file(manifest_path) do
      {:ok, manifest} ->
        repo_reports =
          manifest.repo_entries
          |> Enum.filter(&tenant_repo?/1)
          |> Enum.map(&scan_repo_entry/1)

        failures =
          repo_reports
          |> Enum.filter(&(elem(&1.result, 0) == :error))
          |> Enum.map(&repo_failure/1)

        report = %{
          manifest: manifest_path,
          repo_reports: Enum.map(repo_reports, &repo_report/1),
          failures: failures
        }

        if failures == [] do
          {:ok, report}
        else
          {:error, report}
        end

      {:error, failures} ->
        {:error, %{manifest: manifest_path, repo_reports: [], failures: failures}}
    end
  end

  @spec format_violation(Violation.t()) :: String.t()
  def format_violation(%Violation{} = violation) do
    "#{violation.path}:#{violation.line}: #{violation.code}: #{violation.snippet}"
  end

  defp scan_repo_entry(%{name: name, path: path}) do
    mode = repo_mode(name)
    {status, report} = scan(root: path, mode: mode)
    %{name: name, path: path, mode: mode, result: {status, report}}
  end

  defp tenant_repo?(%{name: name}), do: name in @query_repos or name in @lease_repos

  defp repo_mode(name) when name in @query_repos, do: :query
  defp repo_mode(name) when name in @lease_repos, do: :lease

  defp repo_failure(%{name: name, result: {:error, report}}) do
    %{repo: name, violations: Enum.map(report.violations, &violation_map/1)}
  end

  defp repo_report(%{name: name, path: path, mode: mode, result: {status, report}}) do
    %{
      repo: name,
      path: path,
      mode: mode,
      status: status,
      checked_files: report.checked_files,
      violation_count: length(report.violations)
    }
  end

  defp normalize_mode!(:all), do: :all
  defp normalize_mode!("all"), do: :all
  defp normalize_mode!(:query), do: :query
  defp normalize_mode!("query"), do: :query
  defp normalize_mode!(:lease), do: :lease
  defp normalize_mode!("lease"), do: :lease

  defp normalize_mode!(mode),
    do: raise(ArgumentError, "unknown tenant scan mode #{inspect(mode)}")

  defp source_files(root) do
    @source_roots
    |> Enum.map(&Path.join(root, &1))
    |> Enum.flat_map(&walk_source_files/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp walk_source_files(path) do
    cond do
      ignored_path?(path) ->
        []

      File.regular?(path) and source_file?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.flat_map(&walk_source_files(Path.join(path, &1)))

      true ->
        []
    end
  end

  defp ignored_path?(path) do
    path
    |> Path.split()
    |> Enum.any?(&MapSet.member?(@ignored_segments, &1))
  end

  defp source_file?(path), do: String.ends_with?(path, [".ex", ".exs"])

  defp scan_file(path, mode) do
    content = File.read!(path)
    lines = String.split(content, "\n", trim: false)

    []
    |> maybe_scan_queries(path, lines, content, mode)
    |> maybe_scan_leases(path, lines, mode)
  end

  defp maybe_scan_queries(violations, path, lines, content, mode)
       when mode in [:all, :query] do
    if query_marker?(content) do
      query_violations(path, lines) ++ violations
    else
      violations
    end
  end

  defp maybe_scan_queries(violations, _path, _lines, _content, _mode), do: violations

  defp query_violations(path, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_no} -> query_call?(line) end)
    |> Enum.reject(fn {_line, line_no} -> tenant_context?(lines, line_no) end)
    |> Enum.map(fn {line, line_no} ->
      violation("tenant_unscoped_query", path, line_no, line)
    end)
  end

  defp maybe_scan_leases(violations, path, lines, mode) when mode in [:all, :lease] do
    lease_shape_violations(path, lines) ++ lease_constructor_violations(path, lines) ++ violations
  end

  defp maybe_scan_leases(violations, _path, _lines, _mode), do: violations

  defp tenant_context?(lines, line_no) do
    lines
    |> window(line_no, 6)
    |> Enum.join("\n")
    |> scoped?()
  end

  defp lease_shape_violations(path, lines) do
    content = Enum.join(lines, "\n")

    if lease_shape_file?(path, content) and not scoped?(content) do
      [violation("tenant_lease_no_tenant_ref", path, 1, "lease shape lacks tenant_id/tenant_ref")]
    else
      []
    end
  end

  defp lease_shape_file?(path, content) do
    String.ends_with?(path, ["credential_lease.ex", "lease_record.ex"]) and
      String.contains?(content, "lease_id")
  end

  defp lease_constructor_violations(path, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_no} -> lease_entry?(line) end)
    |> Enum.reject(fn {line, line_no} -> lease_block_scoped?(line, block(lines, line_no, 32)) end)
    |> Enum.map(fn {line, line_no} ->
      violation("tenant_lease_no_tenant_ref", path, line_no, line)
    end)
  end

  defp lease_block_scoped?(line, block) do
    cond do
      String.contains?(line, ~s(schema "credential_leases")) ->
        scoped?(block)

      String.contains?(block, "lease_id:") ->
        scoped?(block)

      true ->
        true
    end
  end

  defp window(lines, line_no, radius) do
    start_index = max(line_no - radius - 1, 0)
    count = radius * 2 + 1
    Enum.slice(lines, start_index, count)
  end

  defp block(lines, line_no, count) do
    lines
    |> Enum.slice(line_no - 1, count)
    |> Enum.join("\n")
  end

  defp scoped?(content), do: Enum.any?(@tenant_terms, &String.contains?(content, &1))

  defp query_marker?(content) do
    Enum.any?(@query_file_markers, fn marker ->
      String.contains?(content, "#{marker} true")
    end)
  end

  defp query_call?(line), do: Enum.any?(@query_terms, &String.contains?(line, &1))

  defp lease_entry?(line) do
    Enum.any?(@lease_constructor_terms, &String.contains?(line, &1)) or
      (String.contains?(line, "schema") and String.contains?(line, "\"credential_leases\""))
  end

  defp violation(code, path, line_no, line) do
    %Violation{
      code: code,
      path: path,
      line: line_no,
      snippet: String.trim(line)
    }
  end

  defp violation_map(%Violation{} = violation) do
    %{
      code: violation.code,
      path: violation.path,
      line: violation.line,
      snippet: violation.snippet
    }
  end
end
