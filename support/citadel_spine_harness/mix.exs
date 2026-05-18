defmodule StackLab.CitadelSpineHarness.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_citadel_spine_harness,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      xref: xref(),
      dialyzer: dialyzer(),
      docs: docs(),
      name: "StackLab Citadel Spine Harness",
      description: "Harness-only assembly package for Citadel and Jido Integration proofs"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {StackLab.CitadelSpineHarness.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        docs: :dev
      ]
    ]
  end

  defp aliases do
    [
      ci: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "dialyzer --force-check",
        "docs --warnings-as-errors"
      ]
    ]
  end

  defp deps do
    [
      {:stack_lab_lab_core, path: "../lab_core"},
      {:ecto_sql, "~> 3.13"},
      {:citadel_authority_contract, path: "../../../citadel/core/authority_contract"},
      {:citadel_governance, path: "../../../citadel/core/citadel_governance"},
      {:citadel_kernel, path: "../../../citadel/core/citadel_kernel"},
      {:citadel_host_ingress_bridge, path: "../../../citadel/bridges/host_ingress_bridge"},
      {:citadel_invocation_bridge, path: "../../../citadel/bridges/invocation_bridge"},
      {:citadel_jido_integration_bridge,
       path: "../../../citadel/bridges/jido_integration_bridge"},
      {:citadel_trace_bridge, path: "../../../citadel/bridges/trace_bridge"},
      {:citadel_domain_surface, path: "../../../citadel/surfaces/citadel_domain_surface"},
      {:app_kit_app_config, path: "../../../app_kit/core/app_config"},
      {:app_kit_chat_surface, path: "../../../app_kit/core/chat_surface"},
      {:app_kit_domain_surface, path: "../../../app_kit/core/domain_surface"},
      {:app_kit_installation_surface, path: "../../../app_kit/core/installation_surface"},
      {:app_kit_mezzanine_bridge, path: "../../../app_kit/bridges/mezzanine_bridge"},
      {:app_kit_operator_surface, path: "../../../app_kit/core/operator_surface"},
      {:app_kit_review_surface, path: "../../../app_kit/core/review_surface"},
      {:app_kit_run_governance, path: "../../../app_kit/core/run_governance"},
      {:app_kit_scope_objects, path: "../../../app_kit/core/scope_objects"},
      {:app_kit_work_control, path: "../../../app_kit/core/work_control"},
      {:app_kit_work_surface, path: "../../../app_kit/core/work_surface"},
      {:mezzanine_core, path: "../../../mezzanine/core/mezzanine_core", runtime: false},
      {:mezzanine_audit_engine, path: "../../../mezzanine/core/audit_engine", runtime: false},
      {:mezzanine_config_registry,
       path: "../../../mezzanine/core/config_registry", runtime: false},
      {:mezzanine_decision_engine,
       path: "../../../mezzanine/core/decision_engine", runtime: false},
      {:mezzanine_evidence_engine,
       path: "../../../mezzanine/core/evidence_engine", runtime: false},
      {:mezzanine_archival_engine,
       path: "../../../mezzanine/core/archival_engine", runtime: false},
      {:mezzanine_barriers, path: "../../../mezzanine/core/barriers", runtime: false},
      {:mezzanine_lifecycle_engine,
       path: "../../../mezzanine/core/lifecycle_engine", runtime: false},
      {:mezzanine_object_engine, path: "../../../mezzanine/core/object_engine", runtime: false},
      {:mezzanine_execution_engine,
       path: "../../../mezzanine/core/execution_engine", runtime: false},
      {:mezzanine_operator_engine,
       path: "../../../mezzanine/core/operator_engine", runtime: false},
      {:mezzanine_pack_compiler, path: "../../../mezzanine/core/pack_compiler", runtime: false},
      {:mezzanine_pack_model, path: "../../../mezzanine/core/pack_model", runtime: false},
      {:mezzanine_projection_engine, path: "../../../mezzanine/core/projection_engine"},
      {:mezzanine_runtime_scheduler,
       path: "../../../mezzanine/core/runtime_scheduler", runtime: false},
      {:mezzanine_substrate_model, path: "../../../mezzanine/core/substrate_model"},
      {:mezzanine_workflow_runtime,
       path: "../../../mezzanine/core/workflow_runtime", runtime: false},
      {:mezzanine_citadel_bridge, path: "../../../mezzanine/bridges/citadel_bridge"},
      {:mezzanine_integration_bridge,
       path: "../../../mezzanine/bridges/integration_bridge", runtime: false},
      {:mezzanine_leasing, path: "../../../mezzanine/core/leasing", runtime: false},
      {:jido_integration_contracts,
       path: "../../../jido_integration/core/contracts", override: true},
      {:jido_integration_v2_control_plane,
       path: "../../../jido_integration/core/control_plane", runtime: false},
      {:jido_integration_v2, path: "../../../jido_integration/core/platform"},
      {:jido_integration_v2_brain_ingress, path: "../../../jido_integration/core/brain_ingress"},
      {:jido_integration_v2_runtime_router,
       path: "../../../jido_integration/core/runtime_router", runtime: false},
      {:jido_integration_v2_store_postgres,
       path: "../../../jido_integration/core/store_postgres", runtime: false},
      {:jido_integration_v2_store_local, path: "../../../jido_integration/core/store_local"},
      {:ground_plane_contracts,
       path: "../../../ground_plane/core/ground_plane_contracts", runtime: false},
      {:execution_plane, path: "../../../execution_plane/core/execution_plane", override: true},
      {:execution_plane_node,
       path: "../../../execution_plane/runtimes/execution_plane_node", override: true},
      {:execution_plane_process,
       path: "../../../execution_plane/runtimes/execution_plane_process", override: true},
      {:execution_plane_http,
       path: "../../../execution_plane/protocols/execution_plane_http", override: true},
      {:agent_session_manager, path: "../../../agent_session_manager", override: true},
      {:cli_subprocess_core, path: "../../../cli_subprocess_core"},
      {:pristine, path: "../../../pristine/apps/pristine_runtime"},
      {:prismatic, path: "../../../prismatic/apps/prismatic_runtime"},
      {:self_hosted_inference_core, path: "../../../self_hosted_inference_core"},
      {:outer_brain_contracts, path: "../../../outer_brain/core/outer_brain_contracts"},
      {:outer_brain_journal, path: "../../../outer_brain/core/outer_brain_journal"},
      {:outer_brain_prompting, path: "../../../outer_brain/core/outer_brain_prompting"},
      {:outer_brain_persistence, path: "../../../outer_brain/core/outer_brain_persistence"},
      {:outer_brain_restart_authority,
       path: "../../../outer_brain/core/outer_brain_restart_authority"},
      {:outer_brain_runtime, path: "../../../outer_brain/core/outer_brain_runtime"},
      {:jason, "~> 1.4", runtime: false},
      {:jsv, "~> 0.18", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp xref do
    [exclude: []]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  defp dialyzer do
    [
      # The harness boots these packages manually under test, so they stay
      # compile-only at app startup but still need PLT coverage for direct calls.
      plt_add_apps: [
        :ground_plane_contracts,
        :jido_integration_v2_control_plane,
        :jido_integration_v2_store_postgres,
        :mezzanine_archival_engine,
        :mezzanine_barriers,
        :mezzanine_lifecycle_engine,
        :mezzanine_leasing,
        :mezzanine_operator_engine,
        :mezzanine_pack_model,
        :mezzanine_projection_engine,
        :mezzanine_runtime_scheduler,
        :mezzanine_substrate_model,
        :mezzanine_workflow_runtime
      ]
    ]
  end
end
