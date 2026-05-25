defmodule StackLab.GnTenNodeLab do
  @moduledoc """
  Generic local BEAM node lab support for StackLab gn-ten proofs.

  The package provides harness mechanics only. Domain DTOs, authority,
  workflow truth, context semantics, model invocation, lower execution, and
  evidence semantics remain in their owner repos.
  """

  alias StackLab.GnTenNodeLab.{BootPlan, Peer, Preflight, Topology}

  @spec preflight(keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate preflight(opts \\ []), to: Preflight, as: :run

  @spec validate_topology(map()) :: {:ok, Topology.t()} | {:error, [map()]}
  defdelegate validate_topology(spec), to: Topology, as: :validate

  @spec load_topology(Path.t()) :: {:ok, Topology.t()} | {:error, [map()]}
  defdelegate load_topology(path), to: Topology, as: :load_file

  @spec topology_instances(Topology.t()) :: [map()]
  defdelegate topology_instances(topology), to: BootPlan, as: :instances

  @spec boot_instance(Peer.t() | node(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate boot_instance(target, instance, opts \\ []), to: BootPlan

  @spec with_peer((Peer.t() -> term()), keyword()) :: {:ok, term()} | {:error, map()}
  defdelegate with_peer(fun, opts \\ []), to: Peer
end
