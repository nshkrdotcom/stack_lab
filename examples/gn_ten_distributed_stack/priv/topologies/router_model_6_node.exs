%{
  topology_ref: "topology://stack_lab/gn-ten/router-model-6-node/v1",
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
    },
    %{
      profile: :outer_brain_context,
      instances: 1,
      required_apps: [],
      owner_groups: [{OuterBrain.RemoteFacade.Context, :context}],
      env: %{persistence_profile: :mickey_mouse},
      vm_args: ["+S", "1"]
    },
    %{
      profile: :jido_model_runtime,
      instances: 1,
      required_apps: [],
      owner_groups: [{JidoIntegration.RemoteFacade.ModelRuntime, :model_runtime}],
      env: %{inference_profile: :fixture},
      vm_args: ["+S", "1"]
    },
    %{
      profile: :aitrace_evidence,
      instances: 1,
      required_apps: [],
      owner_groups: [{AITrace.RemoteFacade.Evidence, :evidence}],
      env: %{persistence_profile: :mickey_mouse},
      vm_args: ["+S", "1"]
    }
  ],
  proof: %{
    scenario_ref: "scenario://stack_lab/gn-ten/router-model-6-node/v1",
    monolith_baseline_required?: true,
    execution_plane_required?: false
  }
}
