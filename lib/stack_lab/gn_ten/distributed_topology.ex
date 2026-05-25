defmodule StackLab.GnTen.DistributedTopology do
  @moduledoc """
  Canonical topology freeze for the local gn-ten distributed proof plan.

  This module is deliberately smaller than the future node lab. It records the
  reviewed profile names, topology refs, owner repos, owner-defined discovery
  groups, and node caps that later orchestration code must implement.
  """

  alias StackLab.GnTen.Manifest

  @schema_version "stack_lab.gn_ten.distributed_topology_freeze.v1"
  @receipt_ref "receipt://stack_lab/gn_ten_distributed_topology_freeze/latest"
  @default_node_cap 32
  @stress_node_cap 49

  @owner_repos %{
    controller: "stack_lab",
    product_probe: "extravaganza",
    app_kit_surface: "app_kit",
    mezzanine_workflow: "mezzanine",
    citadel_authority: "citadel",
    outer_brain_context: "outer_brain",
    jido_model_runtime: "jido_integration",
    execution_plane_node: "execution_plane",
    ground_plane_projection: "ground_plane",
    aitrace_evidence: "AITrace"
  }

  @owner_groups %{
    app_kit_surface: {AppKit.RemoteFacade, :product_surface},
    mezzanine_workflow: {Mezzanine.RemoteFacade, :workflow},
    citadel_authority: {Citadel.RemoteFacade, :authority},
    outer_brain_context: {OuterBrain.RemoteFacade, :context},
    jido_model_runtime: {JidoIntegration.RemoteFacade, :model_runtime},
    execution_plane_node: {ExecutionPlane.RemoteFacade, :lane},
    ground_plane_projection: {GroundPlane.RemoteFacade, :projection},
    aitrace_evidence: {AITrace.RemoteFacade, :evidence}
  }

  @type topology :: map()
  @type failure :: %{required(:code) => String.t(), optional(atom()) => term()}

  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @spec receipt_ref() :: String.t()
  def receipt_ref, do: @receipt_ref

  @spec default_node_cap() :: pos_integer()
  def default_node_cap, do: @default_node_cap

  @spec stress_node_cap() :: pos_integer()
  def stress_node_cap, do: @stress_node_cap

  @spec owner_groups() :: map()
  def owner_groups, do: @owner_groups

  @spec canonical_topologies() :: [topology()]
  def canonical_topologies do
    [
      topology(:control_3_node, "control-3-node", [
        node(:app_kit_surface, 0),
        node(:mezzanine_workflow, 0),
        node(:citadel_authority, 0)
      ]),
      topology(:context_6_node, "context-6-node", [
        node(:controller, nil, id: "stack_lab_controller"),
        node(:app_kit_surface, 0),
        node(:mezzanine_workflow, 0),
        node(:citadel_authority, 0),
        node(:outer_brain_context, 0),
        node(:aitrace_evidence, 0)
      ]),
      topology(:full_9_node, "full-9-node", [
        node(:product_probe, 0),
        node(:app_kit_surface, 0),
        node(:mezzanine_workflow, 0),
        node(:citadel_authority, 0),
        node(:outer_brain_context, 0),
        node(:jido_model_runtime, 0),
        node(:execution_plane_node, 0),
        node(:ground_plane_projection, 0),
        node(:aitrace_evidence, 0)
      ]),
      topology(:partition_recovery, "partition-recovery", [
        node(:app_kit_surface, 0),
        node(:mezzanine_workflow, 0),
        node(:citadel_authority, 0),
        node(:outer_brain_context, 0),
        node(:jido_model_runtime, 0),
        node(:aitrace_evidence, 0)
      ]),
      topology(:scale_12_node, "scale-12-node", scale_12_nodes()),
      topology(:scale_32_node, "scale-32-node", scale_32_nodes()),
      topology(:scale_49_node, "scale-49-node", scale_49_nodes(), node_cap: @stress_node_cap)
    ]
  end

  @spec topology_by_profile(atom()) :: {:ok, topology()} | {:error, :unknown_topology_profile}
  def topology_by_profile(profile) when is_atom(profile) do
    case Enum.find(canonical_topologies(), &(&1.profile == profile)) do
      nil -> {:error, :unknown_topology_profile}
      topology -> {:ok, topology}
    end
  end

  @spec validate_canonical() :: {:ok, map()} | {:error, [failure()]}
  def validate_canonical do
    canonical_topologies()
    |> Enum.flat_map(fn topology ->
      case validate_topology(topology) do
        {:ok, _topology} -> []
        {:error, failures} -> failures
      end
    end)
    |> case do
      [] -> {:ok, receipt()}
      failures -> {:error, failures}
    end
  end

  @spec validate_topology(topology()) :: {:ok, topology()} | {:error, [failure()]}
  def validate_topology(topology) when is_map(topology) do
    failures =
      []
      |> validate_known_ref(topology)
      |> validate_node_cap(topology)
      |> validate_unique_node_ids(topology)
      |> validate_owner_repos(topology)
      |> validate_required_profiles(topology)
      |> validate_owner_groups(topology)

    case Enum.reverse(failures) do
      [] -> {:ok, topology}
      failures -> {:error, failures}
    end
  end

  @spec receipt() :: map()
  def receipt do
    %{
      "schema_version" => @schema_version,
      "status" => "pass",
      "receipt_ref" => @receipt_ref,
      "default_node_cap" => @default_node_cap,
      "stress_node_cap" => @stress_node_cap,
      "topology_count" => length(canonical_topologies()),
      "topology_refs" => Enum.map(canonical_topologies(), & &1.topology_ref),
      "topologies" => Enum.map(canonical_topologies(), &receipt_topology/1),
      "owner_group_posture" => "owner_defined_groups_mapped_by_stack_lab",
      "does_not_prove" => [
        "EPMD startup",
        "peer node lifecycle",
        "distributed business semantics",
        "owner facade availability",
        "monolith/distributed parity",
        "49-node scale feasibility"
      ]
    }
  end

  @spec default_receipt_path() :: String.t()
  def default_receipt_path do
    Path.expand("tmp/stack_lab/gn_ten_distributed/topology_freeze.json", File.cwd!())
  end

  @spec write_receipt!(map(), String.t()) :: String.t()
  def write_receipt!(receipt, path) when is_map(receipt) and is_binary(path) do
    path = Path.expand(path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(receipt, pretty: true))
    path
  end

  defp topology(profile, slug, nodes, opts \\ []) do
    node_cap = Keyword.get(opts, :node_cap, @default_node_cap)

    %{
      profile: profile,
      topology_ref: "topology://stack_lab/gn-ten/#{slug}/v1",
      node_cap: node_cap,
      nodes: nodes,
      required_profiles: required_profiles(nodes),
      monolith_baseline_required?: true
    }
  end

  defp node(profile, index, opts \\ []) do
    id = Keyword.get(opts, :id, node_id(profile, index))

    %{
      id: id,
      profile: profile,
      owner_repo: Keyword.get(opts, :owner_repo, Map.fetch!(@owner_repos, profile)),
      owner_group: Map.get(@owner_groups, profile),
      required?: Keyword.get(opts, :required?, true)
    }
  end

  defp node_id(profile, nil), do: Atom.to_string(profile)
  defp node_id(profile, index), do: "#{profile}_#{index}"

  defp many(profile, count) do
    Enum.map(0..(count - 1), &node(profile, &1))
  end

  defp scale_12_nodes do
    many(:app_kit_surface, 2) ++
      many(:mezzanine_workflow, 2) ++
      many(:citadel_authority, 1) ++
      many(:outer_brain_context, 2) ++
      many(:jido_model_runtime, 2) ++
      many(:execution_plane_node, 1) ++
      many(:aitrace_evidence, 1) ++
      many(:ground_plane_projection, 1)
  end

  defp scale_32_nodes do
    many(:app_kit_surface, 8) ++
      many(:mezzanine_workflow, 8) ++
      many(:citadel_authority, 2) ++
      many(:outer_brain_context, 4) ++
      many(:jido_model_runtime, 4) ++
      many(:aitrace_evidence, 2) ++
      many(:execution_plane_node, 4)
  end

  defp scale_49_nodes do
    many(:app_kit_surface, 14) ++
      many(:mezzanine_workflow, 12) ++
      many(:citadel_authority, 2) ++
      many(:outer_brain_context, 5) ++
      many(:jido_model_runtime, 8) ++
      many(:execution_plane_node, 5) ++
      many(:aitrace_evidence, 2) ++
      many(:ground_plane_projection, 1)
  end

  defp required_profiles(nodes) do
    nodes
    |> Enum.filter(& &1.required?)
    |> Enum.map(& &1.profile)
    |> Enum.reject(&(&1 == :controller))
    |> Enum.uniq()
  end

  defp validate_known_ref(failures, topology) do
    known_refs = canonical_topologies() |> Enum.map(& &1.topology_ref) |> MapSet.new()

    if MapSet.member?(known_refs, topology[:topology_ref]) do
      failures
    else
      [failure("unknown_topology_ref", topology_ref: topology[:topology_ref]) | failures]
    end
  end

  defp validate_node_cap(failures, topology) do
    nodes = Map.get(topology, :nodes, [])
    node_cap = Map.get(topology, :node_cap, @default_node_cap)

    if length(nodes) <= node_cap do
      failures
    else
      [
        failure("node_count_above_cap",
          topology_ref: topology[:topology_ref],
          node_count: length(nodes),
          node_cap: node_cap
        )
        | failures
      ]
    end
  end

  defp validate_unique_node_ids(failures, topology) do
    duplicates =
      topology
      |> Map.get(:nodes, [])
      |> Enum.map(& &1.id)
      |> Enum.frequencies()
      |> Enum.filter(fn {_id, count} -> count > 1 end)
      |> Enum.map(fn {id, _count} -> id end)

    if duplicates == [] do
      failures
    else
      [
        failure("duplicate_node_ids", topology_ref: topology[:topology_ref], ids: duplicates)
        | failures
      ]
    end
  end

  defp validate_owner_repos(failures, topology) do
    allowed = Manifest.expected_repos() |> MapSet.new()

    topology
    |> Map.get(:nodes, [])
    |> Enum.reduce(failures, fn node, acc ->
      if MapSet.member?(allowed, node.owner_repo) do
        acc
      else
        [
          failure("unknown_owner_repo",
            topology_ref: topology[:topology_ref],
            node_id: node.id,
            owner_repo: node.owner_repo
          )
          | acc
        ]
      end
    end)
  end

  defp validate_required_profiles(failures, topology) do
    present =
      topology
      |> Map.get(:nodes, [])
      |> Enum.map(& &1.profile)
      |> MapSet.new()

    missing =
      topology
      |> Map.get(:required_profiles, [])
      |> Enum.reject(&MapSet.member?(present, &1))

    if missing == [] do
      failures
    else
      [
        failure("missing_required_profiles",
          topology_ref: topology[:topology_ref],
          profiles: missing
        )
        | failures
      ]
    end
  end

  defp validate_owner_groups(failures, topology) do
    topology
    |> Map.get(:nodes, [])
    |> Enum.reduce(failures, fn node, acc ->
      expected = Map.get(@owner_groups, node.profile)

      cond do
        node.profile in [:controller, :product_probe] ->
          acc

        is_nil(expected) ->
          [
            failure("unknown_profile",
              topology_ref: topology[:topology_ref],
              profile: node.profile
            )
            | acc
          ]

        node.owner_group == expected ->
          acc

        true ->
          [
            failure("owner_group_mismatch",
              topology_ref: topology[:topology_ref],
              node_id: node.id,
              expected: inspect(expected),
              actual: inspect(node.owner_group)
            )
            | acc
          ]
      end
    end)
  end

  defp receipt_topology(topology) do
    %{
      "profile" => Atom.to_string(topology.profile),
      "topology_ref" => topology.topology_ref,
      "node_cap" => topology.node_cap,
      "node_count" => length(topology.nodes),
      "required_profiles" => Enum.map(topology.required_profiles, &Atom.to_string/1),
      "owner_groups" =>
        topology.nodes
        |> Enum.reject(&is_nil(&1.owner_group))
        |> Enum.map(fn node ->
          %{
            "profile" => Atom.to_string(node.profile),
            "owner_group" => inspect(node.owner_group)
          }
        end)
    }
  end

  defp failure(code, attrs) do
    attrs
    |> Map.new()
    |> Map.put(:code, code)
  end
end
