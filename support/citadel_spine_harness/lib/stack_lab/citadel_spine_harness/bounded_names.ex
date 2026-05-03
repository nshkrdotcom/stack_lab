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

  @local_node_slots [
    :stack_lab_local_a,
    :stack_lab_local_b,
    :stack_lab_local_c,
    :stack_lab_local_d,
    :stack_lab_local_e,
    :stack_lab_local_f,
    :stack_lab_local_g,
    :stack_lab_local_h,
    :stack_lab_local_i,
    :stack_lab_local_j,
    :stack_lab_local_k,
    :stack_lab_local_l,
    :stack_lab_local_m,
    :stack_lab_local_n,
    :stack_lab_local_o,
    :stack_lab_local_p,
    :stack_lab_local_q,
    :stack_lab_local_r,
    :stack_lab_local_s,
    :stack_lab_local_t,
    :stack_lab_local_u,
    :stack_lab_local_v,
    :stack_lab_local_w,
    :stack_lab_local_x,
    :stack_lab_local_y,
    :stack_lab_local_z
  ]

  @unavailable_node :stack_lab_missing_unavailable@localhost

  @spec global_name(atom()) :: {:global, {atom(), atom(), integer()}}
  def global_name(prefix) when prefix in @global_name_prefixes do
    {:global, {@global_namespace, prefix, System.unique_integer([:positive, :monotonic])}}
  end

  def global_name(prefix) do
    raise ArgumentError, "unknown StackLab harness name prefix: #{inspect(prefix)}"
  end

  @spec local_node_slots() :: [atom()]
  def local_node_slots, do: rotated(@local_node_slots)

  @spec unavailable_node() :: node()
  def unavailable_node, do: @unavailable_node

  defp rotated(slots) do
    offset = rem(System.unique_integer([:positive, :monotonic]), length(slots))
    Enum.drop(slots, offset) ++ Enum.take(slots, offset)
  end
end
