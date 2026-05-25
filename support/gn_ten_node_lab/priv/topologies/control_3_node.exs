%{
  topology_ref: "topology://stack_lab/gn-ten/control-3-node/v1",
  cookie_mode: :ephemeral,
  name_domain: :shortnames,
  dist_port_range: 43_000..43_100,
  profiles: [
    %{
      profile: :app_kit_surface,
      instances: 1,
      required_apps: [],
      owner_groups: [{AppKit.RemoteFacade.ProductSurface, :product_surface}],
      env: %{persistence_profile: :mickey_mouse},
      vm_args: ["+S", "1"]
    },
    %{
      profile: :mezzanine_workflow,
      instances: 1,
      required_apps: [],
      owner_groups: [{Mezzanine.RemoteFacade.Workflow, :workflow}],
      env: %{persistence_profile: :mickey_mouse},
      vm_args: ["+S", "1"]
    },
    %{
      profile: :citadel_authority,
      instances: 1,
      required_apps: [],
      owner_groups: [{Citadel.RemoteFacade.Authority, :authority}],
      env: %{persistence_profile: :mickey_mouse},
      vm_args: ["+S", "1"]
    }
  ],
  proof: %{
    scenario_ref: "scenario://stack_lab/gn-ten/control-3-node/v1",
    monolith_baseline_required?: true
  }
}
