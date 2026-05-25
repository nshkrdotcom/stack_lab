%{
  topology_ref: "topology://stack_lab/gn-ten/fixture-single-node/v1",
  cookie_mode: :ephemeral,
  name_domain: :shortnames,
  dist_port_range: 43_000..43_100,
  profiles: [
    %{
      profile: :fixture_profile,
      instances: 1,
      required_apps: [:logger],
      owner_groups: [GnTenNodeLabFixture.RemoteFacade.owner_group()],
      env: %{persistence_profile: :mickey_mouse},
      vm_args: ["+S", "1"]
    }
  ],
  proof: %{
    scenario_ref: "scenario://stack_lab/gn-ten/fixture-single-node/v1",
    monolith_baseline_required?: false
  }
}
