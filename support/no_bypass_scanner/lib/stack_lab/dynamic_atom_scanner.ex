defmodule StackLab.DynamicAtomScanner do
  @moduledoc """
  Scanner for dynamic atom construction reachable from runtime code.
  """

  defmodule Finding do
    @moduledoc """
    Dynamic atom constructor finding in production/runtime code.
    """
    @enforce_keys [:path, :line, :constructor, :classification, :owner_phase, :remediation]
    @type t :: %__MODULE__{
            path: String.t(),
            line: non_neg_integer(),
            constructor: String.t(),
            classification: atom(),
            owner_phase: String.t(),
            remediation: String.t()
          }
    defstruct @enforce_keys
  end

  defmodule ClassifiedConversion do
    @moduledoc """
    Dynamic atom constructor classified outside runtime hard-gate scope.
    """
    @enforce_keys [:path, :line, :constructor, :classification, :reason]
    @type t :: %__MODULE__{
            path: String.t(),
            line: non_neg_integer(),
            constructor: String.t(),
            classification: atom(),
            reason: String.t()
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
    Scanner receipt for dynamic atom safety.
    """
    @enforce_keys [
      :scanner,
      :scanner_version,
      :mode,
      :target_roots,
      :checked_paths,
      :skipped_paths,
      :findings,
      :classified_conversions,
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
            classified_conversions: [ClassifiedConversion.t()],
            status: :pass | :open_defect | :baseline_findings
          }
    defstruct @enforce_keys
  end

  @scanner "stack_lab.dynamic_atom_scanner"
  @scanner_version "0.1.0"
  @target_roots StackLab.StructuralGateScanner.target_roots()
  @excluded_segments [".git", "_build", "deps", "dist", "doc", "docs", "node_modules"]
  @source_extensions [".ex", ".exs"]

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

      {findings, classified_conversions} =
        checked_paths
        |> Enum.flat_map(fn path -> scan_file(path) end)
        |> Enum.sort_by(&{&1.path, &1.line, constructor_value(&1)})
        |> Enum.split_with(&match?(%Finding{}, &1))

      {:ok,
       %Receipt{
         scanner: @scanner,
         scanner_version: @scanner_version,
         mode: mode,
         target_roots: target_roots,
         checked_paths: checked_paths,
         skipped_paths: skipped_paths,
         findings: findings,
         classified_conversions: classified_conversions,
         status: status(mode, findings)
       }}
    end
  end

  @spec scan_source(String.t(), String.t()) :: [Finding.t() | ClassifiedConversion.t()]
  def scan_source(source, path) when is_binary(source) and is_binary(path) do
    case Code.string_to_quoted(source, file: path) do
      {:ok, ast} -> collect_calls(ast, path)
      {:error, {line, error, token}} -> [parse_finding(path, line, error, token)]
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
      classified_conversion_count: length(receipt.classified_conversions),
      findings_by_constructor: count_by(receipt.findings, & &1.constructor),
      classified_by_zone: count_by(receipt.classified_conversions, & &1.classification)
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

  defp scan_file(path) do
    path
    |> File.read!()
    |> scan_source(path)
  end

  defp collect_calls(ast, path) do
    ast
    |> collect_node(path, [])
    |> Enum.reverse()
  end

  defp collect_node(node, path, acc) do
    acc = collect_call(node, path, acc)

    case node do
      {left, right} ->
        acc |> collect_child(left, path) |> collect_child(right, path)

      {_form, _meta, args} when is_list(args) ->
        Enum.reduce(args, acc, &collect_child(&2, &1, path))

      list when is_list(list) ->
        Enum.reduce(list, acc, &collect_child(&2, &1, path))

      _other ->
        acc
    end
  end

  defp collect_child(acc, child, path), do: collect_node(child, path, acc)

  defp collect_call({{:., meta, [module_ast, remote_function]}, call_meta, _args}, path, acc)
       when is_atom(remote_function) do
    module_ast
    |> remote_module()
    |> constructor(remote_function)
    |> maybe_record(path, line(call_meta, meta), path_classification(path), acc)
  end

  defp collect_call({function, meta, args}, path, acc)
       when function in [
              :binary_to_atom,
              :binary_to_existing_atom,
              :list_to_atom,
              :list_to_existing_atom
            ] and is_list(args) do
    function
    |> local_constructor()
    |> maybe_record(path, line(meta, []), path_classification(path), acc)
  end

  defp collect_call(_node, _path, acc), do: acc

  defp constructor(String, :to_atom), do: "String.to_atom"
  defp constructor(String, :to_existing_atom), do: "String.to_existing_atom"
  defp constructor(:erlang, :binary_to_atom), do: ":erlang.binary_to_atom"
  defp constructor(:erlang, :binary_to_existing_atom), do: ":erlang.binary_to_existing_atom"
  defp constructor(Kernel, function), do: local_constructor(function)
  defp constructor(_module, _function), do: nil

  defp local_constructor(:binary_to_atom), do: "binary_to_atom"
  defp local_constructor(:binary_to_existing_atom), do: "binary_to_existing_atom"
  defp local_constructor(:list_to_atom), do: "list_to_atom"
  defp local_constructor(:list_to_existing_atom), do: "list_to_existing_atom"
  defp local_constructor(_function), do: nil

  defp maybe_record(nil, _path, _line, _classification, acc), do: acc

  defp maybe_record(constructor, path, line, :production, acc) do
    [
      %Finding{
        path: path,
        line: line,
        constructor: constructor,
        classification: :production,
        owner_phase: "Phase 2",
        remediation:
          "Replace runtime atom conversion with binary keys, explicit closed lookup maps, or compile-time literal maps."
      }
      | acc
    ]
  end

  defp maybe_record(constructor, path, line, classification, acc) do
    [
      %ClassifiedConversion{
        path: path,
        line: line,
        constructor: constructor,
        classification: classification,
        reason: classification_reason(classification)
      }
      | acc
    ]
  end

  defp parse_finding(path, line, error, token) do
    %Finding{
      path: path,
      line: line || 0,
      constructor: "parse_error",
      classification: path_classification(path),
      owner_phase: "Phase 2",
      remediation: "Fix parse error before dynamic-atom scanning: #{inspect({error, token})}"
    }
  end

  defp remote_module({:__aliases__, _meta, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Module.concat(parts)
  end

  defp remote_module(module) when is_atom(module), do: module
  defp remote_module(_other), do: nil

  defp line(primary, fallback) do
    Keyword.get(primary, :line) || Keyword.get(fallback, :line) || 0
  end

  defp path_classification(path) do
    normalized = Path.expand(path)

    cond do
      String.ends_with?(
        normalized,
        "/stack_lab/support/no_bypass_scanner/lib/stack_lab/gap_closure_negative_fixtures.ex"
      ) ->
        :scanner_negative_fixture

      path_has_segment?(normalized, "test") or String.ends_with?(normalized, "_test.exs") ->
        :test_owned

      path_has_segment?(normalized, "test_support") or path_has_segment?(normalized, "fixtures") ->
        :test_owned

      path_has_segment?(normalized, "build_support") ->
        :build_support_static_manifest

      String.contains?(normalized, "/stack_lab/examples/") ->
        :proof_app_owned

      true ->
        :production
    end
  end

  defp classification_reason(:scanner_negative_fixture), do: "scanner-owned negative fixture"
  defp classification_reason(:test_owned), do: "test-only closed fixture vocabulary"

  defp classification_reason(:build_support_static_manifest),
    do: "static repo-owned build manifest"

  defp classification_reason(:proof_app_owned), do: "StackLab proof app fixture or harness"
  defp classification_reason(_classification), do: "classified outside runtime hard-gate scope"

  defp constructor_value(%Finding{constructor: constructor}), do: constructor
  defp constructor_value(%ClassifiedConversion{constructor: constructor}), do: constructor

  defp excluded_path?(path), do: any_segment?(path_segments(path), @excluded_segments)
  defp source_path?(path), do: Path.extname(path) in @source_extensions
  defp path_has_segment?(path, segment), do: Enum.member?(path_segments(path), segment)
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
