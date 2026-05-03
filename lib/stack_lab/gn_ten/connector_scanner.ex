defmodule StackLab.GnTen.ConnectorScanner do
  @moduledoc """
  Source scanner for gn-ten provider and connector boundary posture.

  The scanner is intentionally conservative. It catches raw non-fixture secret
  literals, provider/model calls that do not carry token-budget language, and
  live-provider proof claims that lack a provider-free baseline.
  """

  alias StackLab.GnTen.Manifest

  defmodule Violation do
    @moduledoc "One connector scanner violation."

    @enforce_keys [:code, :path, :line, :snippet]
    defstruct [:code, :path, :line, :snippet]

    @type t :: %__MODULE__{
            code: atom(),
            path: Path.t(),
            line: pos_integer(),
            snippet: String.t()
          }
  end

  @secret_keys ~w(api_key access_token refresh_token client_secret secret provider_token)
  @safe_secret_values ~w(demo fixture test sample redacted example mock dummy)
  @safe_secret_line_terms ~w(
    lease_fields
    durable_secret_fields
    secret_names
    secret_ref
    external_secret_ref
    auth_binding
    digest
    fingerprint
    redacted
    hash
  )
  @provider_call_names ~w(Provider OpenAI Anthropic Model LLM)
  @provider_call_methods ~w(call chat complete completion stream)
  @provider_call_terms ~w(model_call provider_call live_provider_call)
  @budget_terms ~w(token_budget max_tokens max_output_tokens budget_ref budget_gate spend_limit)
  @ignored_segments MapSet.new([".git", "_build", "deps", "doc", "dist", "test"])
  @source_roots ~w(lib core apps connectors bridges surfaces)
  @source_repos ~w(jido_integration outer_brain citadel)
  @proof_repos ~w(stack_lab)

  @type mode :: :all | :source | :proof
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
    files = scan_files(root, mode)

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
          |> Enum.filter(&connector_repo?/1)
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

  defp connector_repo?(%{name: name}), do: name in @source_repos or name in @proof_repos

  defp repo_mode(name) when name in @source_repos, do: :source
  defp repo_mode(name) when name in @proof_repos, do: :proof

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

  defp scan_files(root, :source), do: source_files(root)
  defp scan_files(root, :proof), do: proof_files(root)
  defp scan_files(root, :all), do: source_files(root) ++ proof_files(root)

  defp normalize_mode!(:all), do: :all
  defp normalize_mode!("all"), do: :all
  defp normalize_mode!(:source), do: :source
  defp normalize_mode!("source"), do: :source
  defp normalize_mode!(:proof), do: :proof
  defp normalize_mode!("proof"), do: :proof

  defp normalize_mode!(mode),
    do: raise(ArgumentError, "unknown connector scan mode #{inspect(mode)}")

  defp source_files(root) do
    @source_roots
    |> Enum.map(&Path.join(root, &1))
    |> Enum.flat_map(&walk_source_files/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp proof_files(root) do
    root
    |> Path.join("proof_matrix.yml")
    |> then(fn path -> if File.regular?(path), do: [path], else: [] end)
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
    |> maybe_scan_source(path, lines, mode)
    |> maybe_scan_proofs(path, lines, content, mode)
  end

  defp maybe_scan_source(violations, path, lines, mode) when mode in [:all, :source] do
    secret_literal_violations(path, lines) ++ token_budget_violations(path, lines) ++ violations
  end

  defp maybe_scan_source(violations, _path, _lines, _mode), do: violations

  defp maybe_scan_proofs(violations, path, lines, content, mode) when mode in [:all, :proof] do
    live_provider_proof_violations(path, lines, content) ++ violations
  end

  defp maybe_scan_proofs(violations, _path, _lines, _content, _mode), do: violations

  defp secret_literal_violations(path, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_no} -> unwrapped_secret?(line) end)
    |> Enum.map(fn {line, line_no} ->
      violation("connector_unwrapped_secret", path, line_no, line)
    end)
  end

  defp unwrapped_secret?(line) do
    case secret_literal_value(line) do
      nil ->
        false

      value ->
        not (safe_secret_line?(line) or safe_secret_value?(value) or env_var_name?(value))
    end
  end

  defp env_var_name?(value) do
    value == String.upcase(value) and String.contains?(value, "_")
  end

  defp token_budget_violations(path, lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_no} -> provider_call?(line) end)
    |> Enum.reject(fn {_line, line_no} -> budget_context?(lines, line_no) end)
    |> Enum.map(fn {line, line_no} ->
      violation("connector_unbounded_token_budget", path, line_no, line)
    end)
  end

  defp budget_context?(lines, line_no) do
    lines
    |> window(line_no, 8)
    |> Enum.join("\n")
    |> contains_any_downcased?(@budget_terms)
  end

  defp live_provider_proof_violations(path, lines, content) do
    if live_provider_claim?(content) and not provider_free_baseline?(content) do
      lines
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_no} -> live_provider_claim?(line) end)
      |> Enum.map(fn {line, line_no} ->
        violation("connector_no_provider_free_proof", path, line_no, line)
      end)
    else
      []
    end
  end

  defp live_provider_claim?(content) do
    downcased = String.downcase(content)

    (String.contains?(downcased, "live_provider:") and String.contains?(downcased, "true")) or
      (String.contains?(downcased, "profile:") and String.contains?(downcased, "live_provider"))
  end

  defp provider_free_baseline?(content) do
    String.contains?(content, "connector_provider_free") and
      String.contains?(content, "status: implemented")
  end

  defp secret_literal_value(line) do
    downcased = String.downcase(line)

    Enum.find_value(@secret_keys, fn key ->
      case :binary.match(downcased, key) do
        {index, size} ->
          binary_part(line, index + size, byte_size(line) - index - size)
          |> quoted_value_after_separator()

        :nomatch ->
          nil
      end
    end)
  end

  defp quoted_value_after_separator(after_key) do
    after_key = String.trim_leading(after_key)

    cond do
      String.starts_with?(after_key, "=>") ->
        after_key |> String.replace_prefix("=>", "") |> quoted_value()

      String.starts_with?(after_key, ":") ->
        after_key |> String.replace_prefix(":", "") |> quoted_value()

      true ->
        nil
    end
  end

  defp quoted_value(text) do
    text = String.trim_leading(text)

    if String.starts_with?(text, "\"") do
      text
      |> String.replace_prefix("\"", "")
      |> String.split("\"", parts: 2)
      |> List.first()
    end
  end

  defp safe_secret_line?(line), do: contains_any_downcased?(line, @safe_secret_line_terms)
  defp safe_secret_value?(value), do: contains_any_downcased?(value, @safe_secret_values)

  defp provider_call?(line) do
    dotted_call? =
      Enum.any?(@provider_call_names, fn name ->
        Enum.any?(@provider_call_methods, fn method ->
          String.contains?(line, "#{name}.#{method}")
        end)
      end)

    dotted_call? or contains_any_downcased?(line, @provider_call_terms)
  end

  defp contains_any_downcased?(content, terms) do
    content = String.downcase(content)
    Enum.any?(terms, &String.contains?(content, &1))
  end

  defp window(lines, line_no, radius) do
    start_index = max(line_no - radius - 1, 0)
    count = radius * 2 + 1

    lines
    |> Enum.drop(start_index)
    |> Enum.take(count)
  end

  defp violation(code, path, line_no, line) do
    %Violation{
      code: code,
      path: path,
      line: line_no,
      snippet: String.trim(line)
    }
  end

  defp violation_map(%Violation{} = violation), do: Map.from_struct(violation)
end
