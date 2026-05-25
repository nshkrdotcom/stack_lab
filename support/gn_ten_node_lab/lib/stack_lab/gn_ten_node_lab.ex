defmodule StackLab.GnTenNodeLab do
  @moduledoc """
  Generic local BEAM node lab support for StackLab gn-ten proofs.

  The package provides harness mechanics only. Domain DTOs, authority,
  workflow truth, context semantics, model invocation, lower execution, and
  evidence semantics remain in their owner repos.
  """

  alias StackLab.GnTenNodeLab.{
    BootPlan,
    EnvelopeScanner,
    FaultDrill,
    Peer,
    Preflight,
    Runner,
    Topology
  }

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

  @spec up(Path.t(), keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate up(topology_path, opts \\ []), to: Runner

  @spec status(keyword()) :: {:ok, map()}
  defdelegate status(opts \\ []), to: Runner

  @spec probe(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate probe(node_id, opts \\ []), to: Runner

  @spec down(keyword()) :: {:ok, map()} | {:error, map()}
  defdelegate down(opts \\ []), to: Runner

  @spec scan_envelope(map(), keyword()) :: map()
  defdelegate scan_envelope(envelope, opts \\ []), to: EnvelopeScanner, as: :scan

  @spec scan_envelopes([map()], keyword()) :: map()
  defdelegate scan_envelopes(envelopes, opts \\ []), to: EnvelopeScanner, as: :scan_many

  @spec crash_node!(map(), String.t()) :: map()
  defdelegate crash_node!(run, node_ref), to: FaultDrill

  @spec disconnect_nodes!(map(), String.t(), String.t()) :: map()
  defdelegate disconnect_nodes!(run, left_ref, right_ref), to: FaultDrill

  @spec heal_nodes!(map(), String.t(), String.t()) :: map()
  defdelegate heal_nodes!(run, left_ref, right_ref), to: FaultDrill

  @spec delay_facade!(map(), String.t(), String.t(), non_neg_integer()) :: map()
  defdelegate delay_facade!(run, node_ref, facade_ref, delay_ms), to: FaultDrill

  @spec inject_stale_dto!(map(), String.t(), String.t()) :: map()
  defdelegate inject_stale_dto!(run, seam_ref, fixture_ref), to: FaultDrill

  @spec duplicate_submit!(map(), String.t()) :: map()
  defdelegate duplicate_submit!(run, accepted_ref), to: FaultDrill

  @spec kill_exporter!(map(), atom()) :: map()
  defdelegate kill_exporter!(run, exporter_profile), to: FaultDrill

  @spec with_peer((Peer.t() -> term()), keyword()) :: {:ok, term()} | {:error, map()}
  defdelegate with_peer(fun, opts \\ []), to: Peer
end
