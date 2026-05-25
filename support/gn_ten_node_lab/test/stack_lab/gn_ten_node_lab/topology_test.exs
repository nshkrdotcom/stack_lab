defmodule StackLab.GnTenNodeLab.TopologyTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTenNodeLab.Topology

  test "validates a minimal topology spec" do
    assert {:ok, topology} = Topology.validate(valid_spec())
    assert topology.topology_ref == "topology://stack_lab/gn-ten/context-6-node/v1"
    assert Topology.node_count(topology) == 3
    assert [first | _rest] = Topology.instance_specs(topology)
    assert first.node_id == "app_kit_surface_0"
  end

  test "loads committed topology fixtures" do
    path = Path.expand("../../../priv/topologies/control_3_node.exs", __DIR__)

    assert {:ok, topology} = Topology.load_file(path)
    assert topology.topology_ref == "topology://stack_lab/gn-ten/control-3-node/v1"
    assert Topology.node_count(topology) == 3
  end

  test "rejects node counts above the default cap" do
    spec =
      valid_spec(%{
        profiles: [
          %{
            profile: :app_kit_surface,
            instances: 33,
            owner_groups: [{AppKit.RemoteFacade.ProductSurface, :product_surface}]
          }
        ]
      })

    assert {:error, failures} = Topology.validate(spec)
    assert failure?(failures, "node_count_above_cap")
  end

  test "allows the reviewed 49-node stress cap only for scale-49 refs" do
    spec =
      valid_spec(%{
        topology_ref: "topology://stack_lab/gn-ten/scale-49-node/v1",
        profiles: [
          %{
            profile: :app_kit_surface,
            instances: 49,
            owner_groups: [{AppKit.RemoteFacade.ProductSurface, :product_surface}]
          }
        ]
      })

    assert {:ok, topology} = Topology.validate(spec)
    assert Topology.node_count(topology) == 49
  end

  test "rejects StackLab-owned owner groups" do
    spec =
      valid_spec(%{
        profiles: [
          %{
            profile: :mezzanine_workflow,
            instances: 1,
            owner_groups: [{StackLab, :mezzanine_workflow}]
          }
        ]
      })

    assert {:error, failures} = Topology.validate(spec)
    assert failure?(failures, "stack_lab_owner_group_forbidden")
  end

  test "rejects duplicate explicit node ids" do
    spec =
      valid_spec(%{
        profiles: [
          %{
            profile: :app_kit_surface,
            instances: 1,
            node_ids: ["duplicate_0"],
            owner_groups: [{AppKit.RemoteFacade.ProductSurface, :product_surface}]
          },
          %{
            profile: :mezzanine_workflow,
            instances: 1,
            node_ids: ["duplicate_0"],
            owner_groups: [{Mezzanine.RemoteFacade.Workflow, :workflow}]
          }
        ]
      })

    assert {:error, failures} = Topology.validate(spec)
    assert failure?(failures, "duplicate_profile_instance_id")
  end

  defp valid_spec(overrides \\ %{}) do
    Map.merge(
      %{
        topology_ref: "topology://stack_lab/gn-ten/context-6-node/v1",
        cookie_mode: :ephemeral,
        name_domain: :shortnames,
        dist_port_range: 43_000..43_100,
        profiles: [
          %{
            profile: :app_kit_surface,
            instances: 1,
            owner_groups: [{AppKit.RemoteFacade.ProductSurface, :product_surface}]
          },
          %{
            profile: :mezzanine_workflow,
            instances: 1,
            owner_groups: [{Mezzanine.RemoteFacade.Workflow, :workflow}]
          },
          %{
            profile: :citadel_authority,
            instances: 1,
            owner_groups: [{Citadel.RemoteFacade.Authority, :authority}]
          }
        ],
        proof: %{scenario_ref: "scenario://stack_lab/gn-ten/context/v1"}
      },
      overrides
    )
  end

  defp failure?(failures, code), do: Enum.any?(failures, &(&1.code == code))
end
