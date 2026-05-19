defmodule StackLab.ProcessSupervisionScanner do
  @moduledoc """
  Phase 6C scanner for unsupervised process primitives.
  """

  defmodule Finding do
    @moduledoc """
    Unsupervised process primitive finding.
    """
    @enforce_keys [:path, :line, :primitive, :classification, :owner_phase, :remediation]
    @type t :: %__MODULE__{
            path: String.t(),
            line: non_neg_integer(),
            primitive: String.t(),
            classification: atom(),
            owner_phase: String.t(),
            remediation: String.t()
          }
    defstruct @enforce_keys
  end

  defmodule ClassifiedPrimitive do
    @moduledoc """
    Process primitive classified outside production hard-gate scope.
    """
    @enforce_keys [:path, :line, :primitive, :classification]
    @type t :: %__MODULE__{
            path: String.t(),
            line: non_neg_integer(),
            primitive: String.t(),
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
    Scanner receipt for Phase 6C.
    """
    @enforce_keys [
      :scanner,
      :scanner_version,
      :mode,
      :target_roots,
      :checked_paths,
      :skipped_paths,
      :findings,
      :classified_primitives,
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
            classified_primitives: [ClassifiedPrimitive.t()],
            status: :pass | :open_defect | :baseline_findings
          }
    defstruct @enforce_keys
  end

  @scanner "stack_lab.process_supervision_scanner"
  @scanner_version "0.1.0"
  @target_roots StackLab.StructuralGateScanner.target_roots()
  @excluded_segments [".git", "_build", "deps", "dist", "doc", "docs", "node_modules"]
  @source_extensions [".ex", ".exs"]
  @supervised_transport_start_link_modules MapSet.new([
                                             ExecutionPlane.Process.Transport.GuestBridge,
                                             ExecutionPlane.Process.Transport.SSHExec,
                                             ExecutionPlane.Process.Transport.Subprocess,
                                             GuestBridge,
                                             SSHExec,
                                             Subprocess
                                           ])

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

      {findings, classified_primitives} =
        checked_paths
        |> Enum.flat_map(&scan_path/1)
        |> Enum.sort_by(&{&1.path, &1.line, &1.primitive})
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
         classified_primitives: classified_primitives,
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
      classified_primitive_count: length(receipt.classified_primitives),
      findings_by_primitive: count_by(receipt.findings, & &1.primitive),
      classified_by_zone: count_by(receipt.classified_primitives, & &1.classification)
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
    |> Code.string_to_quoted(file: path)
    |> case do
      {:ok, ast} -> collect_calls(ast, path)
      {:error, {line, error, token}} -> [parse_finding(path, line, error, token)]
    end
  end

  defp collect_calls(ast, path) do
    ast
    |> collect_node(path, nil, [])
    |> Enum.reverse()
  end

  defp collect_node({def_kind, _meta, [head, clauses]}, path, _function, acc)
       when def_kind in [:def, :defp, :defmacro, :defmacrop] and is_list(clauses) do
    function = function_name(head)

    clauses
    |> Keyword.values()
    |> Enum.reduce(acc, fn clause_body, clause_acc ->
      collect_node(clause_body, path, function, clause_acc)
    end)
  end

  defp collect_node(node, path, function, acc) do
    acc = collect_call(node, path, function, acc)

    case node do
      {left, right} ->
        acc |> collect_child(left, path, function) |> collect_child(right, path, function)

      {_form, _meta, args} when is_list(args) ->
        Enum.reduce(args, acc, &collect_child(&2, &1, path, function))

      list when is_list(list) ->
        Enum.reduce(list, acc, &collect_child(&2, &1, path, function))

      _other ->
        acc
    end
  end

  defp collect_child(acc, child, path, function), do: collect_node(child, path, function, acc)

  defp collect_call(
         {{:., meta, [module_ast, remote_function]}, call_meta, _args},
         path,
         context,
         acc
       )
       when is_atom(remote_function) do
    module_ast
    |> remote_module()
    |> primitive(remote_function, context)
    |> maybe_record(path, line(call_meta, meta), path_classification(path), acc)
  end

  defp collect_call({function, meta, args}, path, _context, acc)
       when function in [:spawn, :spawn_monitor] and is_list(args) do
    function
    |> local_primitive()
    |> maybe_record(path, line(meta, []), path_classification(path), acc)
  end

  defp collect_call(_node, _path, _function, acc), do: acc

  defp primitive(Task, :async, _context), do: "Task.async"
  defp primitive(Task, :async_stream, _context), do: "Task.async_stream"
  defp primitive(Task, :start, _context), do: "Task.start"
  defp primitive(Agent, :start, _context), do: "Agent.start"
  defp primitive(GenServer, :start, _context), do: "GenServer.start"
  defp primitive(module, :start_link, context), do: start_link_primitive(module, context)
  defp primitive(Kernel, :spawn, _context), do: "spawn"
  defp primitive(Kernel, :spawn_monitor, _context), do: "spawn_monitor"
  defp primitive(_module, _function, _context), do: nil

  defp start_link_primitive(module, context) do
    if supervised_transport_start_link_module?(module) and context != :start_link do
      "#{module_name(module)}.start_link"
    else
      built_in_start_link_primitive(module, context)
    end
  end

  defp built_in_start_link_primitive(Task, _context), do: "Task.start_link"
  defp built_in_start_link_primitive(Agent, :start_link), do: nil
  defp built_in_start_link_primitive(Agent, _context), do: "Agent.start_link"
  defp built_in_start_link_primitive(GenServer, :start_link), do: nil
  defp built_in_start_link_primitive(GenServer, _context), do: "GenServer.start_link"
  defp built_in_start_link_primitive(_module, _context), do: nil

  defp supervised_transport_start_link_module?(module) do
    MapSet.member?(@supervised_transport_start_link_modules, module)
  end

  defp module_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp local_primitive(:spawn), do: "spawn"
  defp local_primitive(:spawn_monitor), do: "spawn_monitor"

  defp maybe_record(nil, _path, _line, _classification, acc), do: acc

  defp maybe_record(primitive, path, line, :production, acc) do
    [
      %Finding{
        path: path,
        line: line,
        primitive: primitive,
        classification: :production,
        owner_phase: "Phase 6C",
        remediation:
          "Move the work under a Supervisor, DynamicSupervisor, Task.Supervisor, or explicit synchronous boundary."
      }
      | acc
    ]
  end

  defp maybe_record(primitive, path, line, classification, acc) do
    [
      %ClassifiedPrimitive{
        path: path,
        line: line,
        primitive: primitive,
        classification: classification
      }
      | acc
    ]
  end

  defp parse_finding(path, line, error, token) do
    %Finding{
      path: path,
      line: line || 0,
      primitive: "parse_error",
      classification: path_classification(path),
      owner_phase: "Phase 6C",
      remediation:
        "Fix parse error before process-supervision scanning: #{inspect({error, token})}"
    }
  end

  defp remote_module({:__aliases__, _meta, parts}) do
    if Enum.all?(parts, &is_atom/1), do: Module.concat(parts)
  end

  defp remote_module({:__MODULE__, _meta, _args}), do: nil
  defp remote_module(module) when is_atom(module), do: module
  defp remote_module(_other), do: nil

  defp function_name({:when, _meta, [head | _guards]}), do: function_name(head)
  defp function_name({name, _meta, _args}) when is_atom(name), do: name
  defp function_name(_head), do: nil

  defp line(primary, fallback) do
    Keyword.get(primary, :line) || Keyword.get(fallback, :line) || 0
  end

  defp path_classification(path) do
    normalized = Path.expand(path)

    cond do
      path_has_segment?(normalized, "test") or String.ends_with?(normalized, "_test.exs") ->
        :test_owned

      path_has_segment?(normalized, "dev") ->
        :dev_support

      String.contains?(normalized, "/stack_lab/support/citadel_spine_harness/") ->
        :proof_harness_owned

      String.contains?(normalized, "/stack_lab/examples/") ->
        :proof_app_owned

      true ->
        :production
    end
  end

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
