defmodule StackLab.RuntimeBoundaryScanner do
  @moduledoc """
  Scanner for hidden runtime globals and raw side-effect boundaries.
  """

  defmodule Finding do
    @moduledoc """
    Production runtime-boundary finding.
    """
    @enforce_keys [:path, :line, :call, :rule, :classification, :owner_phase, :remediation]
    @type t :: %__MODULE__{
            path: String.t(),
            line: non_neg_integer(),
            call: String.t(),
            rule: atom(),
            classification: atom(),
            owner_phase: String.t(),
            remediation: String.t()
          }
    defstruct @enforce_keys
  end

  defmodule ClassifiedCall do
    @moduledoc """
    Runtime-boundary call classified outside production hard-gate scope.
    """
    @enforce_keys [:path, :line, :call, :rule, :classification]
    @type t :: %__MODULE__{
            path: String.t(),
            line: non_neg_integer(),
            call: String.t(),
            rule: atom(),
            classification: atom()
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
    Scanner receipt for runtime-boundary safety.
    """
    @enforce_keys [
      :scanner,
      :scanner_version,
      :mode,
      :target_roots,
      :checked_paths,
      :skipped_paths,
      :findings,
      :classified_calls,
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
            classified_calls: [ClassifiedCall.t()],
            status: :pass | :open_defect | :baseline_findings
          }
    defstruct @enforce_keys
  end

  @scanner "stack_lab.runtime_boundary_scanner"
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

      {findings, classified_calls} =
        checked_paths
        |> Enum.flat_map(&scan_path/1)
        |> Enum.sort_by(&{&1.path, &1.line, call_value(&1)})
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
         classified_calls: classified_calls,
         status: status(mode, findings)
       }}
    end
  end

  @spec scan_source(String.t(), String.t()) :: [Finding.t() | ClassifiedCall.t()]
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
      classified_call_count: length(receipt.classified_calls),
      findings_by_rule: count_by(receipt.findings, & &1.rule),
      classified_by_zone: count_by(receipt.classified_calls, & &1.classification)
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
    |> rule_for(remote_function)
    |> maybe_record(path, line(call_meta, meta), path_classification(path), acc)
  end

  defp collect_call(_node, _path, acc), do: acc

  defp rule_for(:persistent_term, :put), do: {:mutable_persistent_term, ":persistent_term.put"}

  defp rule_for(:persistent_term, :erase),
    do: {:mutable_persistent_term, ":persistent_term.erase"}

  defp rule_for(Application, :put_env), do: {:application_env_mutation, "Application.put_env"}

  defp rule_for(Application, :delete_env),
    do: {:application_env_mutation, "Application.delete_env"}

  defp rule_for(Application, :get_env), do: {:application_env_read, "Application.get_env"}
  defp rule_for(Application, :fetch_env), do: {:application_env_read, "Application.fetch_env"}
  defp rule_for(Application, :fetch_env!), do: {:application_env_read, "Application.fetch_env!"}
  defp rule_for(System, :cmd), do: {:raw_command_execution, "System.cmd"}
  defp rule_for(System, :get_env), do: {:system_env_read, "System.get_env"}
  defp rule_for(Process, :put), do: {:process_dictionary_context, "Process.put"}
  defp rule_for(Process, :get), do: {:process_dictionary_context, "Process.get"}
  defp rule_for(Process, :delete), do: {:process_dictionary_context, "Process.delete"}
  defp rule_for(_module, _function), do: nil

  defp maybe_record(nil, _path, _line, _classification, acc), do: acc

  defp maybe_record({rule, call}, path, line, :production, acc) do
    [
      %Finding{
        path: path,
        line: line,
        call: call,
        rule: rule,
        classification: :production,
        owner_phase: owner_phase(rule),
        remediation: remediation(rule)
      }
      | acc
    ]
  end

  defp maybe_record({rule, call}, path, line, classification, acc) do
    [
      %ClassifiedCall{
        path: path,
        line: line,
        call: call,
        rule: rule,
        classification: classification
      }
      | acc
    ]
  end

  defp parse_finding(path, line, error, token) do
    %Finding{
      path: path,
      line: line || 0,
      call: "parse_error",
      rule: :parse_error,
      classification: path_classification(path),
      owner_phase: "Phase 1",
      remediation: "Fix parse error before runtime-boundary scanning: #{inspect({error, token})}"
    }
  end

  defp owner_phase(:mutable_persistent_term), do: "Phase 15, 29, 35, 59, or 61"
  defp owner_phase(:application_env_mutation), do: "Phase 5, 10, 20, 49, or 55"
  defp owner_phase(:application_env_read), do: "Phase 5, 20, or 55"
  defp owner_phase(:raw_command_execution), do: "Phase 19, 38, or 48"
  defp owner_phase(:system_env_read), do: "Phase 11, 33, 38, or 48"
  defp owner_phase(:process_dictionary_context), do: "Phase 54"
  defp owner_phase(:parse_error), do: "Phase 1"

  defp remediation(:mutable_persistent_term) do
    "Move mutable runtime state to a supervised owner; keep :persistent_term only for immutable boot-time values."
  end

  defp remediation(:application_env_mutation) do
    "Replace runtime app-env mutation with explicit context or a scoped test sandbox."
  end

  defp remediation(:application_env_read) do
    "Load boot defaults at application startup and pass explicit runtime profiles through call boundaries."
  end

  defp remediation(:raw_command_execution) do
    "Route command execution through the owning execution boundary with cwd, env, timeout, and redaction policy."
  end

  defp remediation(:system_env_read) do
    "Materialize environment input at the boot or credential boundary and pass redacted context inward."
  end

  defp remediation(:process_dictionary_context) do
    "Replace process dictionary context with explicit trace/runtime context or a documented test-only wrapper."
  end

  defp remediation(:parse_error), do: "Fix parse error before scanner enforcement."

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

    special_path_classification(normalized) || ownership_path_classification(normalized)
  end

  defp special_path_classification(path) do
    cond do
      scanner_path?(path) -> :scanner
      test_path?(path) -> :test_owned
      path_has_segment?(path, "build_support") -> :build_support_static_manifest
      stack_lab_command_runner_path?(path) -> :command_boundary
      execution_plane_os_boundary_path?(path) -> :os_boundary
      path_has_segment?(path, "dev") -> :dev_support
      true -> nil
    end
  end

  defp ownership_path_classification(path) do
    cond do
      proof_harness_path?(path) -> :proof_harness_owned
      proof_app_path?(path) -> :proof_app_owned
      true -> :production
    end
  end

  defp execution_plane_os_boundary_path?(path) do
    String.ends_with?(
      path,
      "/execution_plane/runtimes/execution_plane_process/lib/execution_plane/process/os.ex"
    )
  end

  defp scanner_path?(path), do: String.contains?(path, "/stack_lab/support/no_bypass_scanner/")

  defp stack_lab_command_runner_path?(path) do
    String.ends_with?(path, "/stack_lab/support/lab_core/lib/stack_lab/command_runner.ex")
  end

  defp test_path?(path) do
    path_has_segment?(path, "test") or String.ends_with?(path, "_test.exs") or
      path_has_segment?(path, "test_support") or path_has_segment?(path, "fixtures")
  end

  defp proof_harness_path?(path) do
    String.contains?(path, "/stack_lab/support/citadel_spine_harness/")
  end

  defp proof_app_path?(path), do: String.contains?(path, "/stack_lab/examples/")

  defp excluded_path?(path), do: any_segment?(path_segments(path), @excluded_segments)
  defp source_path?(path), do: Path.extname(path) in @source_extensions
  defp any_segment?(segments, wanted), do: Enum.any?(wanted, &Enum.member?(segments, &1))
  defp path_has_segment?(path, segment), do: path |> path_segments() |> Enum.member?(segment)

  defp path_segments(path) do
    path
    |> Path.expand()
    |> Path.split()
  end

  defp call_value(%Finding{call: call}), do: call
  defp call_value(%ClassifiedCall{call: call}), do: call

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
