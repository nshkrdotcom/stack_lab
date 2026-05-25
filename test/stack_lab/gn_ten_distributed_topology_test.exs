defmodule StackLab.GnTenDistributedTopologyTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.DistributedTopology

  test "validates the canonical distributed topology catalog" do
    assert {:ok, receipt} = DistributedTopology.validate_canonical()
    assert receipt["schema_version"] == "stack_lab.gn_ten.distributed_topology_freeze.v1"
    assert receipt["status"] == "pass"
    assert receipt["default_node_cap"] == 32
    assert receipt["stress_node_cap"] == 49
    assert receipt["topology_count"] == 7

    assert "topology://stack_lab/gn-ten/context-6-node/v1" in receipt["topology_refs"]
    assert "topology://stack_lab/gn-ten/scale-49-node/v1" in receipt["topology_refs"]
  end

  test "freezes exact scale topology counts" do
    assert {:ok, scale_12} = DistributedTopology.topology_by_profile(:scale_12_node)
    assert {:ok, scale_32} = DistributedTopology.topology_by_profile(:scale_32_node)
    assert {:ok, scale_49} = DistributedTopology.topology_by_profile(:scale_49_node)

    assert length(scale_12.nodes) == 12
    assert length(scale_32.nodes) == 32
    assert length(scale_49.nodes) == 49
    assert scale_49.node_cap == 49
  end

  test "rejects unknown owner repos" do
    assert {:ok, topology} = DistributedTopology.topology_by_profile(:context_6_node)

    bad_topology =
      update_in(topology.nodes, fn [node | rest] ->
        [Map.put(node, :owner_repo, "not_a_repo") | rest]
      end)

    assert {:error, failures} = DistributedTopology.validate_topology(bad_topology)
    assert failure_code?(failures, "unknown_owner_repo")
  end

  test "rejects duplicate node ids" do
    assert {:ok, topology} = DistributedTopology.topology_by_profile(:control_3_node)
    [first, second | rest] = topology.nodes

    bad_topology = %{topology | nodes: [first, %{second | id: first.id} | rest]}

    assert {:error, failures} = DistributedTopology.validate_topology(bad_topology)
    assert failure_code?(failures, "duplicate_node_ids")
  end

  test "rejects missing required domains" do
    assert {:ok, topology} = DistributedTopology.topology_by_profile(:context_6_node)

    bad_topology = %{
      topology
      | nodes: Enum.reject(topology.nodes, &(&1.profile == :citadel_authority))
    }

    assert {:error, failures} = DistributedTopology.validate_topology(bad_topology)
    assert failure_code?(failures, "missing_required_profiles")
  end

  test "rejects node counts above the topology cap" do
    assert {:ok, topology} = DistributedTopology.topology_by_profile(:control_3_node)

    bad_topology = %{
      topology
      | node_cap: 2
    }

    assert {:error, failures} = DistributedTopology.validate_topology(bad_topology)
    assert failure_code?(failures, "node_count_above_cap")
  end

  test "uses owner-defined discovery groups instead of StackLab groups" do
    owner_group_modules =
      DistributedTopology.owner_groups()
      |> Map.values()
      |> Enum.map(fn {module, _name} -> module end)

    refute StackLab in owner_group_modules
    refute Enum.any?(owner_group_modules, &(Module.split(&1) |> List.first() == "StackLab"))
  end

  test "writes a topology freeze receipt" do
    path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_topology_freeze_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, receipt} = DistributedTopology.validate_canonical()
    assert DistributedTopology.write_receipt!(receipt, path) == path

    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["receipt_ref"] == DistributedTopology.receipt_ref()
  end

  defp failure_code?(failures, code) do
    Enum.any?(failures, &(&1.code == code))
  end
end
