repo_root = Path.expand("..", __DIR__)
siblings_root = Path.expand("..", repo_root)

dep = fn repository, subdir, hex ->
  %{
    path: Path.join(siblings_root, "#{repository}/#{subdir}"),
    github: %{repo: "nshkrdotcom/#{repository}", branch: "main", subdir: subdir},
    hex: hex,
    default_order: [:path, :github, :hex],
    publish_order: [:hex]
  }
end

root_dep = fn repository, hex ->
  %{
    path: Path.join(siblings_root, repository),
    github: %{repo: "nshkrdotcom/#{repository}", branch: "main"},
    hex: hex,
    default_order: [:path, :github, :hex],
    publish_order: [:hex]
  }
end

%{
  deps: %{
    agent_session_manager: root_dep.("agent_session_manager", "~> 0.12.0"),
    ai_trace_replay_contracts: dep.("AITrace", "core/replay_contracts", "~> 0.1.0"),
    ai_trace_replay_engine: dep.("AITrace", "core/replay_engine", "~> 0.1.0"),
    aitrace: root_dep.("AITrace", "~> 0.1.0"),
    app_kit_adaptive_control_surface:
      dep.("app_kit", "core/adaptive_control_surface", "~> 0.1.0"),
    app_kit_app_config: dep.("app_kit", "core/app_config", "~> 0.1.0"),
    app_kit_budget_surface: dep.("app_kit", "core/budget_surface", "~> 0.1.0"),
    app_kit_chat_surface: dep.("app_kit", "core/chat_surface", "~> 0.1.0"),
    app_kit_context_surface: dep.("app_kit", "core/context_surface", "~> 0.1.0"),
    app_kit_coordination_surface: dep.("app_kit", "core/coordination_surface", "~> 0.1.0"),
    app_kit_core: dep.("app_kit", "core/app_kit_core", "~> 0.1.0"),
    app_kit_cost_surface: dep.("app_kit", "core/cost_surface", "~> 0.1.0"),
    app_kit_domain_surface: dep.("app_kit", "core/domain_surface", "~> 0.1.0"),
    app_kit_eval_surface: dep.("app_kit", "core/eval_surface", "~> 0.1.0"),
    app_kit_guardrail_surface: dep.("app_kit", "core/guardrail_surface", "~> 0.1.0"),
    app_kit_hive_surface: dep.("app_kit", "core/hive_surface", "~> 0.1.0"),
    app_kit_installation_surface: dep.("app_kit", "core/installation_surface", "~> 0.1.0"),
    app_kit_mezzanine_bridge: dep.("app_kit", "bridges/mezzanine_bridge", "~> 0.1.0"),
    app_kit_operator_surface: dep.("app_kit", "core/operator_surface", "~> 0.1.0"),
    app_kit_optimization_surface: dep.("app_kit", "core/optimization_surface", "~> 0.1.0"),
    app_kit_prompt_surface: dep.("app_kit", "core/prompt_surface", "~> 0.1.0"),
    app_kit_replay_surface: dep.("app_kit", "core/replay_surface", "~> 0.1.0"),
    app_kit_review_surface: dep.("app_kit", "core/review_surface", "~> 0.1.0"),
    app_kit_run_governance: dep.("app_kit", "core/run_governance", "~> 0.1.0"),
    app_kit_runtime_gateway: dep.("app_kit", "core/runtime_gateway", "~> 0.1.0"),
    app_kit_scope_objects: dep.("app_kit", "core/scope_objects", "~> 0.1.0"),
    app_kit_skill_surface: dep.("app_kit", "core/skill_surface", "~> 0.1.0"),
    app_kit_work_control: dep.("app_kit", "core/work_control", "~> 0.1.0"),
    app_kit_work_surface: dep.("app_kit", "core/work_surface", "~> 0.1.0"),
    chassis_evolution_conformance:
      dep.("chassis", "proof/chassis_evolution_conformance", "~> 0.1.0"),
    chassis_model_asset_conformance:
      dep.("chassis", "proof/chassis_model_asset_conformance", "~> 0.1.0"),
    chassis_stacklab_bridge: dep.("chassis", "proof/chassis_stacklab_bridge", "~> 0.1.0"),
    citadel_authority_contract: dep.("citadel", "core/authority_contract", "~> 0.1.0"),
    citadel_connector_binding: dep.("citadel", "core/connector_binding", "~> 0.1.0"),
    citadel_context_authority_contract:
      dep.("citadel", "core/context_authority_contract", "~> 0.1.0"),
    citadel_domain_surface: dep.("citadel", "surfaces/citadel_domain_surface", "~> 0.1.0"),
    citadel_execution_governance_contract:
      dep.("citadel", "core/execution_governance_contract", "~> 0.1.0"),
    citadel_governance: dep.("citadel", "core/citadel_governance", "~> 0.1.0"),
    citadel_host_ingress_bridge: dep.("citadel", "bridges/host_ingress_bridge", "~> 0.1.0"),
    citadel_invocation_bridge: dep.("citadel", "bridges/invocation_bridge", "~> 0.1.0"),
    citadel_jido_integration_bridge:
      dep.("citadel", "bridges/jido_integration_bridge", "~> 0.1.0"),
    citadel_kernel: dep.("citadel", "core/citadel_kernel", "~> 0.1.0"),
    citadel_trace_bridge: dep.("citadel", "bridges/trace_bridge", "~> 0.1.0"),
    cli_subprocess_core: root_dep.("cli_subprocess_core", "~> 0.4.0"),
    execution_plane: dep.("execution_plane", "core/execution_plane", "~> 0.2.0"),
    execution_plane_http: dep.("execution_plane", "protocols/execution_plane_http", "~> 0.1.0"),
    execution_plane_node: dep.("execution_plane", "runtimes/execution_plane_node", "~> 0.1.0"),
    execution_plane_process:
      dep.("execution_plane", "runtimes/execution_plane_process", "~> 0.1.0"),
    gepa_framework: root_dep.("gepa_framework", "~> 0.1.0"),
    ground_plane_contracts: dep.("ground_plane", "core/ground_plane_contracts", "~> 0.1.0"),
    ground_plane_persistence_policy: dep.("ground_plane", "core/persistence_policy", "~> 0.1.0"),
    jido_hive_agent_coordinator: dep.("jido_hive", "core/agent_coordinator", "~> 0.1.0"),
    jido_hive_coordination_patterns: dep.("jido_hive", "core/coordination_patterns", "~> 0.1.0"),
    jido_hive_inter_agent_messaging: dep.("jido_hive", "core/inter_agent_messaging", "~> 0.1.0"),
    jido_hive_shared_memory_facade: dep.("jido_hive", "core/shared_memory_facade", "~> 0.1.0"),
    jido_inference_runtime: dep.("jido_integration", "core/inference_runtime", "~> 0.1.0"),
    jido_integration_agent_interop_contracts:
      dep.("jido_integration", "core/agent_interop_contracts", "~> 0.1.0"),
    jido_integration_connector_admission_engine:
      dep.("jido_integration", "core/connector_admission_engine", "~> 0.1.0"),
    jido_integration_contracts: dep.("jido_integration", "core/contracts", "~> 0.1.0"),
    jido_integration_provider_classification:
      dep.("jido_integration", "core/provider_classification", "~> 0.1.0"),
    jido_integration_v2: dep.("jido_integration", "core/platform", "~> 0.1.0"),
    jido_integration_v2_brain_ingress: dep.("jido_integration", "core/brain_ingress", "~> 0.1.0"),
    jido_integration_v2_connector_registry:
      dep.("jido_integration", "core/connector_registry", "~> 0.1.0"),
    jido_integration_v2_control_plane: dep.("jido_integration", "core/control_plane", "~> 0.1.0"),
    jido_integration_v2_direct_runtime:
      dep.("jido_integration", "core/direct_runtime", "~> 0.1.0"),
    jido_integration_v2_runtime_router:
      dep.("jido_integration", "core/runtime_router", "~> 0.1.0"),
    jido_integration_v2_store_local: dep.("jido_integration", "core/store_local", "~> 0.1.0"),
    jido_integration_v2_store_postgres:
      dep.("jido_integration", "core/store_postgres", "~> 0.1.0"),
    jido_integration_v2_tool_contracts:
      dep.("jido_integration", "core/tool_contracts", "~> 0.1.0"),
    jido_model_invocation_contracts:
      dep.("jido_integration", "core/model_invocation_contracts", "~> 0.1.0"),
    mezzanine_agent_turn_engine: dep.("mezzanine", "core/agent_turn_engine", "~> 0.1.0"),
    mezzanine_ai_execution_engine: dep.("mezzanine", "core/ai_execution_engine", "~> 0.1.0"),
    mezzanine_archival_engine: dep.("mezzanine", "core/archival_engine", "~> 0.1.0"),
    mezzanine_audit_engine: dep.("mezzanine", "core/audit_engine", "~> 0.1.0"),
    mezzanine_barriers: dep.("mezzanine", "core/barriers", "~> 0.1.0"),
    mezzanine_budget_enforcement_engine:
      dep.("mezzanine", "core/budget_enforcement_engine", "~> 0.1.0"),
    mezzanine_citadel_bridge: dep.("mezzanine", "bridges/citadel_bridge", "~> 0.1.0"),
    mezzanine_config_registry: dep.("mezzanine", "core/config_registry", "~> 0.1.0"),
    mezzanine_context_packet_engine: dep.("mezzanine", "core/context_packet_engine", "~> 0.1.0"),
    mezzanine_core: dep.("mezzanine", "core/mezzanine_core", "~> 0.1.0"),
    mezzanine_cost_attribution_engine:
      dep.("mezzanine", "core/cost_attribution_engine", "~> 0.1.0"),
    mezzanine_decision_engine: dep.("mezzanine", "core/decision_engine", "~> 0.1.0"),
    mezzanine_eval_engine: dep.("mezzanine", "core/eval_engine", "~> 0.1.0"),
    mezzanine_evidence_engine: dep.("mezzanine", "core/evidence_engine", "~> 0.1.0"),
    mezzanine_execution_engine: dep.("mezzanine", "core/execution_engine", "~> 0.1.0"),
    mezzanine_governed_effects: dep.("mezzanine", "core/governed_effects", "~> 0.1.0"),
    mezzanine_integration_bridge: dep.("mezzanine", "bridges/integration_bridge", "~> 0.1.0"),
    mezzanine_leasing: dep.("mezzanine", "core/leasing", "~> 0.1.0"),
    mezzanine_lifecycle_engine: dep.("mezzanine", "core/lifecycle_engine", "~> 0.1.0"),
    mezzanine_m1_m2_runtime: dep.("mezzanine", "core/m1_m2_runtime", "~> 0.1.0"),
    mezzanine_object_engine: dep.("mezzanine", "core/object_engine", "~> 0.1.0"),
    mezzanine_operator_engine: dep.("mezzanine", "core/operator_engine", "~> 0.1.0"),
    mezzanine_optimization_engine: dep.("mezzanine", "core/optimization_engine", "~> 0.1.0"),
    mezzanine_pack_compiler: dep.("mezzanine", "core/pack_compiler", "~> 0.1.0"),
    mezzanine_pack_model: dep.("mezzanine", "core/pack_model", "~> 0.1.0"),
    mezzanine_projection_engine: dep.("mezzanine", "core/projection_engine", "~> 0.1.0"),
    mezzanine_runtime_profile: dep.("mezzanine", "core/runtime_profile", "~> 0.1.0"),
    mezzanine_runtime_scheduler: dep.("mezzanine", "core/runtime_scheduler", "~> 0.1.0"),
    mezzanine_source_engine: dep.("mezzanine", "core/source_engine", "~> 0.1.0"),
    mezzanine_substrate_model: dep.("mezzanine", "core/substrate_model", "~> 0.1.0"),
    mezzanine_workflow_runtime: dep.("mezzanine", "core/workflow_runtime", "~> 0.1.0"),
    outer_brain_context_abi: dep.("outer_brain", "core/context_abi", "~> 0.1.0"),
    outer_brain_contracts: dep.("outer_brain", "core/outer_brain_contracts", "~> 0.1.0"),
    outer_brain_domain_bridge: dep.("outer_brain", "bridges/domain_bridge", "~> 0.1.0"),
    outer_brain_guardrail_engine: dep.("outer_brain", "core/guardrail_engine", "~> 0.1.0"),
    outer_brain_journal: dep.("outer_brain", "core/outer_brain_journal", "~> 0.1.0"),
    outer_brain_memory_contracts: dep.("outer_brain", "core/memory_contracts", "~> 0.1.0"),
    outer_brain_persistence: dep.("outer_brain", "core/outer_brain_persistence", "~> 0.1.0"),
    outer_brain_prompt_fabric: dep.("outer_brain", "core/prompt_fabric", "~> 0.1.0"),
    outer_brain_prompting: dep.("outer_brain", "core/outer_brain_prompting", "~> 0.1.0"),
    outer_brain_restart_authority:
      dep.("outer_brain", "core/outer_brain_restart_authority", "~> 0.1.0"),
    outer_brain_runtime: dep.("outer_brain", "core/outer_brain_runtime", "~> 0.1.0"),
    outer_brain_token_meter: dep.("outer_brain", "core/token_meter", "~> 0.1.0"),
    prismatic: dep.("prismatic", "apps/prismatic_runtime", "~> 0.2.0"),
    pristine: dep.("pristine", "apps/pristine_runtime", "~> 0.2.0"),
    self_hosted_inference_core: root_dep.("self_hosted_inference_core", "~> 0.2.0"),
    synapse_core: dep.("synapse", "apps/synapse_core", "~> 0.1.0"),
    trinity_contracts: dep.("trinity_framework", "core/trinity_contracts", "~> 0.1.0"),
    trinity_coordinator_core:
      dep.("trinity_framework", "core/trinity_coordinator_core", "~> 0.1.0"),
    trinity_framework: root_dep.("trinity_framework", "~> 0.1.0"),
    blitz: %{hex: "~> 0.3.0", default_order: [:hex], publish_order: [:hex]},
    weld: %{hex: "~> 0.8.2", default_order: [:hex], publish_order: [:hex]}
  }
}
