defmodule StackLab.CitadelSpineHarness.BoundedNames do
  @moduledoc false

  @global_namespace :stack_lab_citadel_spine_harness
  @global_name_prefixes [
    :kernel_snapshot,
    :session_directory,
    :service_catalog,
    :boundary_tracker,
    :invocation_supervisor,
    :projection_supervisor,
    :local_supervisor,
    :signal_ingress,
    :session_server,
    :phase5_kernel_snapshot,
    :phase5_kernel_snapshot_staleness,
    :phase5_signal_ingress,
    :phase5_signal_ordering,
    :phase5_signal_token,
    :phase5_signal_tenant_scope,
    :phase5_lineage_context_missing,
    :phase5_eviction_signal_expired,
    :phase5_eviction_signal_capped,
    :phase5_eviction_kernel_snapshot,
    :phase5_boundary_lease_tracker,
    :phase5_eviction_session_kernel_snapshot,
    :phase5_session_directory,
    :phase5_session_directory_capped
  ]

  @unavailable_node :stack_lab_missing_unavailable@localhost

  @spec global_name(atom()) :: {:global, {atom(), atom(), integer()}}
  def global_name(prefix) when prefix in @global_name_prefixes do
    {:global, {@global_namespace, prefix, System.unique_integer([:positive, :monotonic])}}
  end

  def global_name(prefix) do
    raise ArgumentError, "unknown StackLab harness name prefix: #{inspect(prefix)}"
  end

  @spec local_node_name() :: atom()
  def local_node_name, do: node_name(:local)

  @spec peer_node_name(atom()) :: atom()
  def peer_node_name(case_name) when is_atom(case_name), do: node_name({:peer, case_name})

  @spec unavailable_node() :: node()
  def unavailable_node, do: @unavailable_node

  defp node_name(scope) do
    [
      "stack_lab",
      "stack_lab",
      scope_slug(scope),
      "ospid",
      System.pid(),
      "testpid",
      self() |> :erlang.pid_to_list() |> to_string(),
      "id",
      System.unique_integer([:positive, :monotonic])
    ]
    |> Enum.join("_")
    |> slug()
    |> String.to_atom()
  end

  defp scope_slug(:local), do: "local"
  defp scope_slug({:peer, case_name}), do: "peer_#{case_name}"

  defp slug(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9_]/, "_")
  end
end
