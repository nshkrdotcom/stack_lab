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

  @local_node_pool [
    :stack_lab_local_000,
    :stack_lab_local_001,
    :stack_lab_local_002,
    :stack_lab_local_003,
    :stack_lab_local_004,
    :stack_lab_local_005,
    :stack_lab_local_006,
    :stack_lab_local_007,
    :stack_lab_local_008,
    :stack_lab_local_009,
    :stack_lab_local_010,
    :stack_lab_local_011,
    :stack_lab_local_012,
    :stack_lab_local_013,
    :stack_lab_local_014,
    :stack_lab_local_015,
    :stack_lab_local_016,
    :stack_lab_local_017,
    :stack_lab_local_018,
    :stack_lab_local_019,
    :stack_lab_local_020,
    :stack_lab_local_021,
    :stack_lab_local_022,
    :stack_lab_local_023,
    :stack_lab_local_024,
    :stack_lab_local_025,
    :stack_lab_local_026,
    :stack_lab_local_027,
    :stack_lab_local_028,
    :stack_lab_local_029,
    :stack_lab_local_030,
    :stack_lab_local_031,
    :stack_lab_local_032,
    :stack_lab_local_033,
    :stack_lab_local_034,
    :stack_lab_local_035,
    :stack_lab_local_036,
    :stack_lab_local_037,
    :stack_lab_local_038,
    :stack_lab_local_039,
    :stack_lab_local_040,
    :stack_lab_local_041,
    :stack_lab_local_042,
    :stack_lab_local_043,
    :stack_lab_local_044,
    :stack_lab_local_045,
    :stack_lab_local_046,
    :stack_lab_local_047,
    :stack_lab_local_048,
    :stack_lab_local_049,
    :stack_lab_local_050,
    :stack_lab_local_051,
    :stack_lab_local_052,
    :stack_lab_local_053,
    :stack_lab_local_054,
    :stack_lab_local_055,
    :stack_lab_local_056,
    :stack_lab_local_057,
    :stack_lab_local_058,
    :stack_lab_local_059,
    :stack_lab_local_060,
    :stack_lab_local_061,
    :stack_lab_local_062,
    :stack_lab_local_063,
    :stack_lab_local_064,
    :stack_lab_local_065,
    :stack_lab_local_066,
    :stack_lab_local_067,
    :stack_lab_local_068,
    :stack_lab_local_069,
    :stack_lab_local_070,
    :stack_lab_local_071,
    :stack_lab_local_072,
    :stack_lab_local_073,
    :stack_lab_local_074,
    :stack_lab_local_075,
    :stack_lab_local_076,
    :stack_lab_local_077,
    :stack_lab_local_078,
    :stack_lab_local_079,
    :stack_lab_local_080,
    :stack_lab_local_081,
    :stack_lab_local_082,
    :stack_lab_local_083,
    :stack_lab_local_084,
    :stack_lab_local_085,
    :stack_lab_local_086,
    :stack_lab_local_087,
    :stack_lab_local_088,
    :stack_lab_local_089,
    :stack_lab_local_090,
    :stack_lab_local_091,
    :stack_lab_local_092,
    :stack_lab_local_093,
    :stack_lab_local_094,
    :stack_lab_local_095,
    :stack_lab_local_096,
    :stack_lab_local_097,
    :stack_lab_local_098,
    :stack_lab_local_099,
    :stack_lab_local_100,
    :stack_lab_local_101,
    :stack_lab_local_102,
    :stack_lab_local_103,
    :stack_lab_local_104,
    :stack_lab_local_105,
    :stack_lab_local_106,
    :stack_lab_local_107,
    :stack_lab_local_108,
    :stack_lab_local_109,
    :stack_lab_local_110,
    :stack_lab_local_111,
    :stack_lab_local_112,
    :stack_lab_local_113,
    :stack_lab_local_114,
    :stack_lab_local_115,
    :stack_lab_local_116,
    :stack_lab_local_117,
    :stack_lab_local_118,
    :stack_lab_local_119,
    :stack_lab_local_120,
    :stack_lab_local_121,
    :stack_lab_local_122,
    :stack_lab_local_123,
    :stack_lab_local_124,
    :stack_lab_local_125,
    :stack_lab_local_126,
    :stack_lab_local_127
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
  def local_node_name do
    pool_index =
      System.unique_integer([:positive, :monotonic])
      |> rem(length(@local_node_pool))

    Enum.fetch!(@local_node_pool, pool_index)
  end

  @spec peer_node_name(atom()) :: charlist()
  def peer_node_name(_case_name), do: :peer.random_name(peer_prefix())

  @spec unavailable_node() :: node()
  def unavailable_node, do: @unavailable_node

  defp peer_prefix, do: :stack_lab_peer
end
