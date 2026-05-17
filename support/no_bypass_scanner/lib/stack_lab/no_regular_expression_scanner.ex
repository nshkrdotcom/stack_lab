defmodule StackLab.NoRegularExpressionScanner do
  @moduledoc """
  Phase 6B scanner for regular-expression API usage.
  """

  defmodule Finding do
    @moduledoc """
    In-scope regular-expression token finding.
    """
    @enforce_keys [:path, :line, :token, :owner_phase, :remediation]
    @type t :: %__MODULE__{
            path: String.t(),
            line: non_neg_integer(),
            token: String.t(),
            owner_phase: String.t(),
            remediation: String.t()
          }
    defstruct @enforce_keys
  end

  defmodule SkippedPath do
    @moduledoc """
    Path skipped by scanner traversal.
    """
    @enforce_keys [:path, :reason]
    @type t :: %__MODULE__{path: String.t(), reason: atom()}
    defstruct @enforce_keys
  end

  defmodule Receipt do
    @moduledoc """
    Scanner receipt for Phase 6B.
    """
    @enforce_keys [
      :scanner,
      :scanner_version,
      :mode,
      :target_roots,
      :checked_paths,
      :skipped_paths,
      :findings,
      :status
    ]
    @type t :: %__MODULE__{
            scanner: String.t(),
            scanner_version: String.t(),
            mode: atom(),
            target_roots: %{String.t() => String.t()},
            checked_paths: [String.t()],
            skipped_paths: [SkippedPath.t()],
            findings: [Finding.t()],
            status: :pass | :open_defect | :baseline_findings
          }
    defstruct @enforce_keys
  end

  @scanner "stack_lab.no_regular_expression_scanner"
  @scanner_version "0.1.0"
  @target_roots StackLab.StructuralGateScanner.target_roots()
  @excluded_segments [".git", "_build", "deps", "dist", "doc", "docs", "node_modules"]
  @source_extensions [".ex", ".exs", ".heex", ".leex", ".eex", ".sh"]

  @tokens [
    "Re" <> "gex",
    "~" <> "r",
    ":" <> "re" <> ".",
    ":" <> "re" <> ",",
    ":" <> "re" <> ")",
    ":" <> "re" <> " "
  ]

  @spec target_roots() :: %{String.t() => String.t()}
  def target_roots, do: @target_roots

  @spec all_target_paths() :: [String.t()]
  def all_target_paths do
    @target_roots
    |> Enum.sort_by(fn {repo, _path} -> repo end)
    |> Enum.map(fn {_repo, path} -> path end)
  end

  @spec scan([String.t()], keyword()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(paths, opts \\ []) when is_list(paths) do
    target_roots = opts |> Keyword.get(:target_roots, @target_roots) |> normalize_roots()
    mode = Keyword.get(opts, :mode, :hard_gate)

    with :ok <- validate_mode(mode),
         {:ok, scan_paths} <- validate_scope(paths, target_roots) do
      {checked_paths, skipped_paths} =
        scan_paths
        |> Enum.flat_map(&walk/1)
        |> Enum.split_with(&match?({:checked, _path}, &1))

      checked_paths = Enum.map(checked_paths, fn {:checked, path} -> path end)
      skipped_paths = Enum.map(skipped_paths, fn {:skipped, skipped_path} -> skipped_path end)

      findings =
        checked_paths
        |> Enum.flat_map(&scan_path/1)
        |> Enum.sort_by(&{&1.path, &1.line, &1.token})

      {:ok,
       %Receipt{
         scanner: @scanner,
         scanner_version: @scanner_version,
         mode: mode,
         target_roots: target_roots,
         checked_paths: checked_paths,
         skipped_paths: skipped_paths,
         findings: findings,
         status: status(mode, findings)
       }}
    end
  end

  @spec summary(Receipt.t()) :: map()
  def summary(%Receipt{} = receipt) do
    %{
      scanner: receipt.scanner,
      scanner_version: receipt.scanner_version,
      mode: receipt.mode,
      status: receipt.status,
      target_repos: receipt.target_roots |> Map.keys() |> Enum.sort(),
      checked_path_count: length(receipt.checked_paths),
      skipped_path_count: length(receipt.skipped_paths),
      finding_count: length(receipt.findings),
      findings_by_token: count_by(receipt.findings, & &1.token)
    }
  end

  defp validate_mode(mode) when mode in [:hard_gate, :baseline], do: :ok
  defp validate_mode(mode), do: {:error, {:invalid_scan_mode, mode}}

  defp validate_scope(paths, target_roots) do
    expanded_paths = Enum.map(paths, &Path.expand/1)
    outside_paths = Enum.reject(expanded_paths, &target_path?(&1, target_roots))

    case outside_paths do
      [] -> {:ok, expanded_paths}
      _ -> {:error, {:outside_target_scope, outside_paths}}
    end
  end

  defp target_path?(path, target_roots) do
    Enum.any?(target_roots, fn {_repo, root} ->
      path == root or String.starts_with?(path, root <> "/")
    end)
  end

  defp walk(path) do
    cond do
      excluded_path?(path) ->
        [{:skipped, %SkippedPath{path: path, reason: :excluded_path}}]

      File.dir?(path) ->
        path
        |> File.ls!()
        |> Enum.sort()
        |> Enum.flat_map(&walk(Path.join(path, &1)))

      source_path?(path) ->
        [{:checked, path}]

      true ->
        [{:skipped, %SkippedPath{path: path, reason: :unsupported_file_type}}]
    end
  end

  defp scan_path(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_number} ->
      @tokens
      |> Enum.filter(&String.contains?(line, &1))
      |> Enum.map(fn token ->
        %Finding{
          path: path,
          line: line_number,
          token: token,
          owner_phase: "Phase 6B",
          remediation: "Replace with explicit string, tokenizer, parser, or AST logic."
        }
      end)
    end)
  end

  defp excluded_path?(path), do: any_segment?(path_segments(path), @excluded_segments)
  defp source_path?(path), do: Path.extname(path) in @source_extensions
  defp any_segment?(segments, wanted), do: Enum.any?(wanted, &Enum.member?(segments, &1))

  defp path_segments(path) do
    path
    |> Path.expand()
    |> Path.split()
  end

  defp count_by(values, fun) do
    Enum.reduce(values, %{}, fn value, counts ->
      Map.update(counts, fun.(value), 1, &(&1 + 1))
    end)
  end

  defp status(_mode, []), do: :pass
  defp status(:baseline, [_ | _]), do: :baseline_findings
  defp status(:hard_gate, [_ | _]), do: :open_defect

  defp normalize_roots(roots) when is_map(roots) do
    roots
    |> Enum.map(fn {repo, path} -> {repo, Path.expand(path)} end)
    |> Map.new()
  end

  defp normalize_roots(roots) when is_list(roots), do: roots |> Map.new() |> normalize_roots()
end
