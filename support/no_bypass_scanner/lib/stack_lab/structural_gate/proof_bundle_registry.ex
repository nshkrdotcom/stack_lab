defmodule StackLab.StructuralGate.ProofBundleRegistry do
  @moduledoc """
  Registry of generic dispatch entrypoints that require structural proof bundles.

  The scanner uses this registry as executable inventory. Each entry ties an
  entrypoint to the smallest required proof set and the contract test that keeps
  the proof honest.
  """

  defmodule Entry do
    @moduledoc "Registered structural proof-bundle entry."

    @enforce_keys [
      :id,
      :path_suffix,
      :function,
      :arity,
      :entrypoint_kind,
      :requirements,
      :paired_test_path,
      :negative_fixture_id
    ]

    @type t :: %__MODULE__{
            id: atom(),
            path_suffix: String.t(),
            function: atom(),
            arity: non_neg_integer(),
            entrypoint_kind: atom(),
            requirements: [atom()],
            paired_test_path: String.t(),
            negative_fixture_id: atom()
          }

    defstruct @enforce_keys
  end

  @repo_root "/home/home/p/g/n"

  @appkit_surface_requirements [
    :product_role_ref,
    :generic_surface_dispatch,
    :bounded_ref_chasing
  ]

  @appkit_backend_surface_requirements [
    :product_role_ref,
    :backend_dispatch,
    :bounded_ref_chasing
  ]

  @adapter_dispatch_requirements [
    :product_role_ref,
    :binding_supplied,
    :adapter_resolved,
    :allowed_operations_scoped,
    :bounded_ref_chasing
  ]

  @binding_resolution_requirements [
    :binding_resolved,
    :operation_plan_captured,
    :manifest_resolved,
    :snapshot_or_epoch_checked,
    :bounded_ref_chasing
  ]

  @operation_graph_requirements [
    :operation_plan_captured,
    :operation_graph_schedules_intents,
    :operation_graph_records_results,
    :bounded_ref_chasing
  ]

  @operation_graph_step_requirements [
    :operation_graph_schedules_intents,
    :operation_graph_records_results,
    :bounded_ref_chasing
  ]

  @receipt_projection_requirements [
    :receipt_emitted,
    :lineage_events_emitted,
    :production_reducer_consumes_receipt,
    :bounded_ref_chasing
  ]

  def entries do
    [
      entry(
        :appkit_source_surface_sync_source,
        "app_kit/core/work_surface/lib/app_kit/source_surface.ex",
        :sync_source,
        4,
        :source,
        @appkit_backend_surface_requirements,
        "app_kit/core/work_surface/test/app_kit/source_surface_test.exs"
      ),
      entry(
        :appkit_source_surface_fetch_candidates,
        "app_kit/core/work_surface/lib/app_kit/source_surface.ex",
        :fetch_candidates,
        4,
        :source,
        @appkit_backend_surface_requirements,
        "app_kit/core/work_surface/test/app_kit/source_surface_test.exs"
      ),
      entry(
        :appkit_source_surface_current_states,
        "app_kit/core/work_surface/lib/app_kit/source_surface.ex",
        :current_states,
        4,
        :source,
        @appkit_backend_surface_requirements,
        "app_kit/core/work_surface/test/app_kit/source_surface_test.exs"
      ),
      entry(
        :appkit_source_surface_publish,
        "app_kit/core/work_surface/lib/app_kit/source_surface.ex",
        :publish,
        4,
        :publication,
        @appkit_backend_surface_requirements,
        "app_kit/core/work_surface/test/app_kit/source_surface_test.exs"
      ),
      entry(
        :appkit_sources_sync_source,
        "app_kit/core/app_kit_core/lib/app_kit/generic_surfaces.ex",
        :sync_source,
        4,
        :source,
        @appkit_surface_requirements,
        "app_kit/core/app_kit_core/test/app_kit/generic_surfaces_test.exs"
      ),
      entry(
        :appkit_sources_fetch_candidates,
        "app_kit/core/app_kit_core/lib/app_kit/generic_surfaces.ex",
        :fetch_candidates,
        4,
        :source,
        @appkit_surface_requirements,
        "app_kit/core/app_kit_core/test/app_kit/generic_surfaces_test.exs"
      ),
      entry(
        :appkit_sources_current_states,
        "app_kit/core/app_kit_core/lib/app_kit/generic_surfaces.ex",
        :current_states,
        4,
        :source,
        @appkit_surface_requirements,
        "app_kit/core/app_kit_core/test/app_kit/generic_surfaces_test.exs"
      ),
      entry(
        :appkit_sources_publish,
        "app_kit/core/app_kit_core/lib/app_kit/generic_surfaces.ex",
        :publish,
        4,
        :publication,
        @appkit_surface_requirements,
        "app_kit/core/app_kit_core/test/app_kit/generic_surfaces_test.exs"
      ),
      entry(
        :appkit_sources_execute_operation,
        "app_kit/core/app_kit_core/lib/app_kit/generic_surfaces.ex",
        :execute_operation,
        5,
        :source_operation,
        @appkit_surface_requirements,
        "app_kit/core/app_kit_core/test/app_kit/generic_surfaces_test.exs"
      ),
      entry(
        :appkit_evidence_collect,
        "app_kit/core/app_kit_core/lib/app_kit/generic_surfaces.ex",
        :collect,
        4,
        :evidence,
        @appkit_surface_requirements,
        "app_kit/core/app_kit_core/test/app_kit/generic_surfaces_test.exs"
      ),
      entry(
        :appkit_evidence_get_receipt,
        "app_kit/core/app_kit_core/lib/app_kit/generic_surfaces.ex",
        :get_receipt,
        3,
        :readback,
        @appkit_surface_requirements,
        "app_kit/core/app_kit_core/test/app_kit/generic_surfaces_test.exs"
      ),
      entry(
        :appkit_trace_export,
        "app_kit/core/app_kit_core/lib/app_kit/generic_surfaces.ex",
        :export,
        4,
        :aitrace_export,
        @appkit_surface_requirements,
        "app_kit/core/app_kit_core/test/app_kit/generic_surfaces_test.exs"
      ),
      entry(
        :appkit_runtime_gateway_invoke_runtime_operation,
        "app_kit/core/runtime_gateway/lib/app_kit/runtime_gateway.ex",
        :invoke_runtime_operation,
        5,
        :runtime,
        @appkit_surface_requirements,
        "app_kit/core/runtime_gateway/test/app_kit/runtime_gateway_test.exs"
      ),
      entry(
        :appkit_runtime_gateway_invoke_runtime_tool,
        "app_kit/core/runtime_gateway/lib/app_kit/runtime_gateway.ex",
        :invoke_runtime_tool,
        5,
        :tool,
        @appkit_surface_requirements,
        "app_kit/core/runtime_gateway/test/app_kit/runtime_gateway_test.exs"
      ),
      entry(
        :appkit_runtime_gateway_collect_evidence,
        "app_kit/core/runtime_gateway/lib/app_kit/runtime_gateway.ex",
        :collect_evidence,
        4,
        :evidence,
        @appkit_surface_requirements,
        "app_kit/core/runtime_gateway/test/app_kit/runtime_gateway_test.exs"
      ),
      entry(
        :appkit_runtime_gateway_invoke_resource_effect,
        "app_kit/core/runtime_gateway/lib/app_kit/runtime_gateway.ex",
        :invoke_resource_effect,
        4,
        :resource_effect,
        @appkit_surface_requirements,
        "app_kit/core/runtime_gateway/test/app_kit/runtime_gateway_test.exs"
      ),
      entry(
        :appkit_runtime_gateway_get_receipt,
        "app_kit/core/runtime_gateway/lib/app_kit/runtime_gateway.ex",
        :get_receipt,
        3,
        :readback,
        @appkit_surface_requirements,
        "app_kit/core/runtime_gateway/test/app_kit/runtime_gateway_test.exs"
      ),
      entry(
        :mezzanine_source_dispatcher_fetch_candidates,
        "mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/source_dispatcher.ex",
        :fetch_candidates,
        4,
        :source_adapter_resolution,
        @adapter_dispatch_requirements,
        "mezzanine/bridges/integration_bridge/test/mezzanine_integration_bridge_test.exs"
      ),
      entry(
        :mezzanine_source_dispatcher_current_states,
        "mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/source_dispatcher.ex",
        :current_states,
        5,
        :source_adapter_resolution,
        @adapter_dispatch_requirements,
        "mezzanine/bridges/integration_bridge/test/mezzanine_integration_bridge_test.exs"
      ),
      entry(
        :mezzanine_source_dispatcher_publish_source,
        "mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/source_dispatcher.ex",
        :publish_source,
        5,
        :publication_adapter_resolution,
        @adapter_dispatch_requirements,
        "mezzanine/bridges/integration_bridge/test/mezzanine_integration_bridge_test.exs"
      ),
      entry(
        :mezzanine_runtime_dispatcher_invoke_runtime_operation,
        "mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/runtime_dispatcher.ex",
        :invoke_runtime_operation,
        6,
        :runtime_adapter_resolution,
        @adapter_dispatch_requirements,
        "mezzanine/bridges/integration_bridge/test/mezzanine_integration_bridge_test.exs"
      ),
      entry(
        :mezzanine_tool_dispatcher_invoke_runtime_tool,
        "mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/tool_dispatcher.ex",
        :invoke_runtime_tool,
        6,
        :tool_adapter_resolution,
        @adapter_dispatch_requirements,
        "mezzanine/bridges/integration_bridge/test/mezzanine_integration_bridge_test.exs"
      ),
      entry(
        :mezzanine_evidence_dispatcher_collect_evidence,
        "mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/evidence_dispatcher.ex",
        :collect_evidence,
        4,
        :evidence_adapter_resolution,
        @adapter_dispatch_requirements,
        "mezzanine/bridges/integration_bridge/test/mezzanine_integration_bridge_test.exs"
      ),
      entry(
        :mezzanine_resource_effect_dispatcher_invoke_resource_effect,
        "mezzanine/bridges/integration_bridge/lib/mezzanine/integration_bridge/resource_effect_dispatcher.ex",
        :invoke_resource_effect,
        4,
        :resource_effect_adapter_resolution,
        @adapter_dispatch_requirements,
        "mezzanine/bridges/integration_bridge/test/mezzanine_integration_bridge_test.exs"
      ),
      entry(
        :mezzanine_config_registry_resolve_operation_plan,
        "mezzanine/core/config_registry/lib/mezzanine_config_registry.ex",
        :resolve_operation_plan,
        1,
        :binding_resolution,
        @binding_resolution_requirements,
        "mezzanine/core/config_registry/test/mezzanine/config_registry/binding_registry_test.exs"
      ),
      entry(
        :mezzanine_binding_registry_resolve_operation_plan,
        "mezzanine/core/config_registry/lib/mezzanine/config_registry/binding_registry.ex",
        :resolve_operation_plan,
        1,
        :binding_resolution,
        @binding_resolution_requirements,
        "mezzanine/core/config_registry/test/mezzanine/config_registry/binding_registry_test.exs"
      ),
      entry(
        :mezzanine_operation_graph_ready_activity_intents,
        "mezzanine/core/workflow_runtime/lib/mezzanine/workflow_runtime/operation_graph_executor.ex",
        :ready_activity_intents,
        3,
        :operation_graph_execution,
        @operation_graph_requirements,
        "mezzanine/core/workflow_runtime/test/mezzanine/workflow_runtime/operation_graph_executor_test.exs"
      ),
      entry(
        :mezzanine_operation_graph_record_activity_result,
        "mezzanine/core/workflow_runtime/lib/mezzanine/workflow_runtime/operation_graph_executor.ex",
        :record_activity_result,
        4,
        :operation_graph_execution,
        @operation_graph_requirements,
        "mezzanine/core/workflow_runtime/test/mezzanine/workflow_runtime/operation_graph_executor_test.exs"
      ),
      entry(
        :mezzanine_operation_graph_apply_cancellation_request,
        "mezzanine/core/workflow_runtime/lib/mezzanine/workflow_runtime/operation_graph_executor.ex",
        :apply_cancellation_request,
        3,
        :operation_graph_execution,
        @operation_graph_requirements,
        "mezzanine/core/workflow_runtime/test/mezzanine/workflow_runtime/operation_graph_executor_test.exs"
      ),
      entry(
        :mezzanine_operation_graph_cancellation_intents,
        "mezzanine/core/workflow_runtime/lib/mezzanine/workflow_runtime/operation_graph_executor.ex",
        :cancellation_intents,
        3,
        :operation_graph_execution,
        @operation_graph_requirements,
        "mezzanine/core/workflow_runtime/test/mezzanine/workflow_runtime/operation_graph_executor_test.exs"
      ),
      entry(
        :mezzanine_operation_graph_compensation_intents,
        "mezzanine/core/workflow_runtime/lib/mezzanine/workflow_runtime/operation_graph_executor.ex",
        :compensation_intents,
        3,
        :operation_graph_execution,
        @operation_graph_requirements,
        "mezzanine/core/workflow_runtime/test/mezzanine/workflow_runtime/operation_graph_executor_test.exs"
      ),
      entry(
        :mezzanine_operation_graph_workflow_step_apply_cancellation_request,
        "mezzanine/core/workflow_runtime/lib/mezzanine/workflow_runtime/operation_graph_workflow_step.ex",
        :apply_cancellation_request,
        4,
        :operation_graph_execution,
        @operation_graph_step_requirements,
        "mezzanine/core/workflow_runtime/test/mezzanine/workflow_runtime/operation_graph_workflow_step_test.exs"
      ),
      entry(
        :mezzanine_receipt_reducer_reduce_input,
        "mezzanine/core/projection_engine/lib/mezzanine/projections/receipt_reducer.ex",
        :reduce,
        1,
        :receipt_projection,
        @receipt_projection_requirements,
        "mezzanine/core/projection_engine/test/mezzanine/projections/receipt_reducer_test.exs"
      ),
      entry(
        :mezzanine_receipt_reducer_generic_reduce,
        "mezzanine/core/projection_engine/lib/mezzanine/projections/receipt_reducer.ex",
        :reduce,
        2,
        :receipt_projection,
        @receipt_projection_requirements,
        "mezzanine/core/projection_engine/test/mezzanine/projections/receipt_reducer_test.exs"
      )
    ]
  end

  @required_generic_functions [
    :sync_source,
    :fetch_candidates,
    :current_states,
    :publish,
    :publish_source,
    :execute_operation,
    :invoke_operation,
    :invoke_effect,
    :invoke_resource_effect,
    :collect,
    :collect_evidence,
    :invoke_runtime,
    :invoke_runtime_operation,
    :invoke_tool,
    :invoke_runtime_tool,
    :execute_tool,
    :get_receipt,
    :export,
    :resolve_binding,
    :resolve_operation,
    :resolve_operation_plan,
    :ready_activity_intents,
    :record_activity_result,
    :apply_cancellation_request,
    :cancellation_intents,
    :compensation_intents,
    :reduce
  ]

  @spec required_generic_functions() :: [atom()]
  def required_generic_functions, do: @required_generic_functions

  @spec find(String.t(), atom() | nil, non_neg_integer()) :: Entry.t() | nil
  def find(path, function, arity) when is_atom(function) do
    Enum.find(entries(), fn %Entry{} = entry ->
      entry.function == function and entry.arity == arity and
        String.ends_with?(Path.expand(path), entry.path_suffix)
    end)
  end

  def find(_path, _function, _arity), do: nil

  @spec validate_entries(keyword()) :: :ok | {:error, [map()]}
  def validate_entries(opts \\ []) do
    repo_root = Keyword.get(opts, :repo_root, @repo_root)

    errors =
      []
      |> Kernel.++(duplicate_errors())
      |> Kernel.++(missing_paired_test_errors(repo_root))
      |> Kernel.++(missing_entrypoint_file_errors(repo_root))

    case errors do
      [] -> :ok
      [_ | _] -> {:error, errors}
    end
  end

  @spec paired_test_exists?(Entry.t(), keyword()) :: boolean()
  def paired_test_exists?(%Entry{} = entry, opts \\ []) do
    repo_root = Keyword.get(opts, :repo_root, @repo_root)
    File.exists?(Path.join(repo_root, entry.paired_test_path))
  end

  defp entry(id, path_suffix, function, arity, entrypoint_kind, requirements, paired_test_path) do
    %Entry{
      id: id,
      path_suffix: path_suffix,
      function: function,
      arity: arity,
      entrypoint_kind: entrypoint_kind,
      requirements: requirements,
      paired_test_path: paired_test_path,
      negative_fixture_id: :unbundled_generic_dispatch_entrypoint
    }
  end

  defp duplicate_errors do
    entries()
    |> Enum.group_by(&{&1.path_suffix, &1.function, &1.arity})
    |> Enum.flat_map(fn {key, entries} ->
      if length(entries) > 1 do
        [
          %{
            error: :duplicate_proof_bundle_entry,
            entrypoint: key,
            ids: Enum.map(entries, & &1.id)
          }
        ]
      else
        []
      end
    end)
  end

  defp missing_paired_test_errors(repo_root) do
    entries()
    |> Enum.reject(&paired_test_exists?(&1, repo_root: repo_root))
    |> Enum.map(fn %Entry{} = entry ->
      %{
        error: :missing_paired_test,
        id: entry.id,
        paired_test_path: entry.paired_test_path
      }
    end)
  end

  defp missing_entrypoint_file_errors(repo_root) do
    entries()
    |> Enum.reject(&File.exists?(Path.join(repo_root, &1.path_suffix)))
    |> Enum.map(fn %Entry{} = entry ->
      %{error: :missing_entrypoint_file, id: entry.id, path_suffix: entry.path_suffix}
    end)
  end
end
