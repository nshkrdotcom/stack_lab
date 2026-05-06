defmodule StackLab.MemoryFabricScanner do
  @moduledoc """
  Pattern-engine-free memory fabric proof scanner.

  Static checks use exact path comparisons and quoted AST traversal. Runtime
  checks validate explicit facts supplied by tests or telemetry collectors.
  """

  defmodule Finding do
    @moduledoc "Memory fabric scanner finding."
    @enforce_keys [:rule, :reason, :path]
    defstruct [:details | @enforce_keys]
    @type t :: %__MODULE__{}
  end

  defmodule Receipt do
    @moduledoc "Memory fabric scanner receipt."
    @enforce_keys [
      :receipt_ref,
      :fixture_ref,
      :scanner_ref,
      :owner_repo,
      :status,
      :checked_rules,
      :findings
    ]
    defstruct @enforce_keys
    @type t :: %__MODULE__{}
  end

  @fixture_ref "MEM-012"
  @scanner_ref "stack-lab.memory-fabric-scanner.v1"
  @required_runtime_refs [
    :tenant_ref,
    :authority_ref,
    :installation_ref,
    :idempotency_key,
    :trace_ref
  ]
  @direct_adapter_module "OuterBrain.MemoryEngine.Store"
  @owner_path "outer_brain/core/memory_engine"
  @rules [:direct_adapter_calls, :required_runtime_refs]

  @spec scan(map()) :: {:ok, Receipt.t()} | {:error, term()}
  def scan(attrs) when is_map(attrs) do
    owner_repo = Map.get(attrs, :owner_repo, "stack_lab")
    source_paths = List.wrap(Map.get(attrs, :source_paths, []))
    runtime_facts = List.wrap(Map.get(attrs, :runtime_facts, []))

    findings =
      static_findings(source_paths) ++
        runtime_findings(runtime_facts)

    {:ok,
     %Receipt{
       receipt_ref: receipt_ref(owner_repo),
       fixture_ref: @fixture_ref,
       scanner_ref: @scanner_ref,
       owner_repo: owner_repo,
       status: status(findings),
       checked_rules: @rules,
       findings: findings
     }}
  end

  @spec static_findings([String.t()]) :: [Finding.t()]
  def static_findings(paths) when is_list(paths) do
    paths
    |> Enum.flat_map(&static_file_findings/1)
  end

  @spec runtime_findings([map()]) :: [Finding.t()]
  def runtime_findings(facts) when is_list(facts) do
    facts
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {fact, index} -> runtime_fact_findings(fact, index) end)
  end

  defp static_file_findings(path) when is_binary(path) do
    cond do
      owner_path?(path) ->
        []

      not File.regular?(path) ->
        [finding(:direct_adapter_calls, :missing_source_path, path, %{})]

      true ->
        path
        |> File.read!()
        |> quoted_direct_adapter_findings(path)
    end
  end

  defp quoted_direct_adapter_findings(source, path) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        if direct_adapter_reference?(ast) do
          [finding(:direct_adapter_calls, :direct_memory_adapter_reference, path, %{})]
        else
          []
        end

      {:error, error} ->
        [finding(:direct_adapter_calls, :invalid_source_ast, path, %{error: inspect(error)})]
    end
  end

  defp direct_adapter_reference?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn node, found? ->
        {node, found? or adapter_alias?(node) or adapter_remote_call?(node)}
      end)

    found?
  end

  defp adapter_alias?({:__aliases__, _meta, parts}) do
    Enum.join(parts, ".") == @direct_adapter_module or
      String.starts_with?(Enum.join(parts, "."), @direct_adapter_module <> ".")
  end

  defp adapter_alias?(_node), do: false

  defp adapter_remote_call?({{:., _meta, [module_ast, _function]}, _call_meta, _args}) do
    adapter_alias?(module_ast)
  end

  defp adapter_remote_call?(_node), do: false

  defp runtime_fact_findings(fact, index) when is_map(fact) do
    missing =
      @required_runtime_refs
      |> Enum.reject(&present_string?(fact, &1))

    case missing do
      [] ->
        []

      fields ->
        [
          finding(
            :required_runtime_refs,
            :missing_required_memory_refs,
            "runtime_fact:#{index}",
            %{fields: fields}
          )
        ]
    end
  end

  defp runtime_fact_findings(_fact, index),
    do: [finding(:required_runtime_refs, :invalid_runtime_fact, "runtime_fact:#{index}", %{})]

  defp present_string?(fact, field) do
    case Map.get(fact, field) || Map.get(fact, Atom.to_string(field)) do
      value when is_binary(value) -> String.trim(value) != ""
      _other -> false
    end
  end

  defp owner_path?(path), do: String.contains?(path, @owner_path)

  defp status([]), do: :pass
  defp status([_ | _]), do: :open_defect

  defp finding(rule, reason, path, details),
    do: %Finding{rule: rule, reason: reason, path: path, details: details}

  defp receipt_ref(owner_repo), do: "memory-fabric-scan://#{owner_repo}/phase-a"
end
