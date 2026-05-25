defmodule StackLab.GnTenNodeLab.BootPlanTest do
  use ExUnit.Case, async: false

  alias StackLab.GnTenNodeLab.{BootPlan, Peer, Topology}

  test "boots required apps, starts facade hosts, and reports readiness" do
    assert {:ok, result} =
             Peer.with_peer(fn peer ->
               assert :ok = Peer.sync_code_paths(peer)
               instance = fixture_instance()

               assert {:ok, receipt} = BootPlan.boot_instance(peer, instance)
               assert receipt["node_id"] == "fixture_profile_0"
               assert receipt["profile"] == "fixture_profile"
               assert receipt["ready?"] == true
               assert [%{"app" => "logger"}] = receipt["started_apps"]
               assert [%{"member_count" => 1}] = receipt["owner_group_membership"]

               receipt
             end)

    assert result["facade_hosts"] != []
  end

  test "reports missing apps as structured failures" do
    assert {:ok, result} =
             Peer.with_peer(fn peer ->
               assert :ok = Peer.sync_code_paths(peer)

               instance =
                 fixture_instance(%{
                   required_apps: [:stack_lab_missing_app_for_node_lab_test],
                   owner_groups: []
                 })

               assert {:error, failure} = BootPlan.boot_instance(peer, instance)
               failure
             end)

    assert result.code == "app_start_failed"
    assert result.app == "stack_lab_missing_app_for_node_lab_test"
  end

  test "reports missing owner group registration" do
    assert {:ok, result} =
             Peer.with_peer(fn peer ->
               assert :ok = Peer.sync_code_paths(peer)

               assert {:error, failure} =
                        BootPlan.boot_instance(peer, fixture_instance(),
                          start_facade_hosts?: false
                        )

               failure
             end)

    assert result.code == "owner_group_not_registered"
  end

  test "expands topology profiles into concrete instances" do
    assert {:ok, topology} =
             Topology.validate(%{
               topology_ref: "topology://stack_lab/gn-ten/test/v1",
               cookie_mode: :ephemeral,
               name_domain: :shortnames,
               dist_port_range: 43_000..43_100,
               profiles: [
                 %{
                   profile: :fixture_profile,
                   instances: 2,
                   required_apps: [:logger],
                   owner_groups: [GnTenNodeLabFixture.RemoteFacade.owner_group()]
                 }
               ]
             })

    assert [
             %{node_id: "fixture_profile_0", instance_index: 0},
             %{node_id: "fixture_profile_1", instance_index: 1}
           ] = BootPlan.instances(topology)
  end

  defp fixture_instance(overrides \\ %{}) do
    Map.merge(
      %{
        node_id: "fixture_profile_0",
        profile: :fixture_profile,
        required_apps: [:logger],
        owner_groups: [GnTenNodeLabFixture.RemoteFacade.owner_group()],
        env: %{},
        vm_args: []
      },
      overrides
    )
  end
end
