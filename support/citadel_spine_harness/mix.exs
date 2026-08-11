unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.CitadelSpineHarness.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

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
      # The AppKit/Mezzanine bridge starts Jido Integration transitively. Start
      # its configured persistence owner first so auth/control-plane cold boot
      # never depends on a later test helper or on dependency compile env.
      DependencySources.dep(:jido_integration_v2_store_local, @dependency_sources_root),
      DependencySources.dep(:citadel_authority_contract, @dependency_sources_root),
      DependencySources.dep(:citadel_governance, @dependency_sources_root),
      DependencySources.dep(:citadel_kernel, @dependency_sources_root),
      DependencySources.dep(:citadel_host_ingress_bridge, @dependency_sources_root),
      DependencySources.dep(:citadel_invocation_bridge, @dependency_sources_root),
      DependencySources.dep(:citadel_jido_integration_bridge, @dependency_sources_root),
      DependencySources.dep(:citadel_trace_bridge, @dependency_sources_root),
      DependencySources.dep(:citadel_domain_surface, @dependency_sources_root, override: true),
      DependencySources.dep(:app_kit_app_config, @dependency_sources_root),
      DependencySources.dep(:app_kit_chat_surface, @dependency_sources_root),
      DependencySources.dep(:app_kit_domain_surface, @dependency_sources_root),
      DependencySources.dep(:app_kit_installation_surface, @dependency_sources_root),
      DependencySources.dep(:app_kit_mezzanine_bridge, @dependency_sources_root),
      DependencySources.dep(:app_kit_operator_surface, @dependency_sources_root),
      DependencySources.dep(:app_kit_review_surface, @dependency_sources_root),
      DependencySources.dep(:app_kit_run_governance, @dependency_sources_root),
      DependencySources.dep(:app_kit_scope_objects, @dependency_sources_root),
      DependencySources.dep(:app_kit_work_control, @dependency_sources_root),
      DependencySources.dep(:app_kit_work_surface, @dependency_sources_root),
      DependencySources.dep(:mezzanine_core, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_runtime_profile, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_audit_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_config_registry, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_decision_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_evidence_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_archival_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_barriers, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_lifecycle_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_object_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_execution_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_operator_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_pack_compiler, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_pack_model, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_projection_engine, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:mezzanine_m1_m2_runtime, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_runtime_scheduler, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_source_engine, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_substrate_model, @dependency_sources_root, override: true),
      DependencySources.dep(:mezzanine_workflow_runtime, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_citadel_bridge, @dependency_sources_root, override: true),
      DependencySources.dep(:mezzanine_integration_bridge, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:mezzanine_leasing, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:jido_integration_contracts, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:jido_integration_v2_control_plane, @dependency_sources_root,
        runtime: false
      ),
      DependencySources.dep(:jido_integration_v2, @dependency_sources_root, runtime: false),
      DependencySources.dep(:jido_integration_v2_brain_ingress, @dependency_sources_root),
      DependencySources.dep(:jido_integration_v2_runtime_router, @dependency_sources_root,
        runtime: false
      ),
      DependencySources.dep(:jido_integration_v2_store_postgres, @dependency_sources_root,
        runtime: false
      ),
      DependencySources.dep(:ground_plane_contracts, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:ground_plane_persistence_policy, @dependency_sources_root,
        runtime: false,
        override: true
      ),
      DependencySources.dep(:execution_plane, @dependency_sources_root, override: true),
      DependencySources.dep(:execution_plane_node, @dependency_sources_root, override: true),
      DependencySources.dep(:execution_plane_process, @dependency_sources_root, override: true),
      DependencySources.dep(:execution_plane_http, @dependency_sources_root, override: true),
      DependencySources.dep(:agent_session_manager, @dependency_sources_root, override: true),
      DependencySources.dep(:cli_subprocess_core, @dependency_sources_root),
      DependencySources.dep(:pristine, @dependency_sources_root, override: true),
      DependencySources.dep(:prismatic, @dependency_sources_root, override: true),
      DependencySources.dep(:self_hosted_inference_core, @dependency_sources_root),
      DependencySources.dep(:crucible_provider_contracts, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:crucible_signal, @dependency_sources_root, override: true),
      DependencySources.dep(:crucible_signal_trace, @dependency_sources_root, override: true),
      DependencySources.dep(:crucible_tap, @dependency_sources_root, override: true),
      DependencySources.dep(:outer_brain_contracts, @dependency_sources_root, override: true),
      DependencySources.dep(:outer_brain_domain_bridge, @dependency_sources_root, override: true),
      DependencySources.dep(:outer_brain_journal, @dependency_sources_root),
      DependencySources.dep(:outer_brain_memory_contracts, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:outer_brain_prompting, @dependency_sources_root, override: true),
      DependencySources.dep(:outer_brain_persistence, @dependency_sources_root),
      DependencySources.dep(:outer_brain_restart_authority, @dependency_sources_root),
      DependencySources.dep(:outer_brain_runtime, @dependency_sources_root),
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
