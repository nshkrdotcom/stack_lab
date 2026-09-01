if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

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
      # The AppKit/Mezzanine bridge starts Jido Integration transitively. Start
      # its configured persistence owner first so auth/control-plane cold boot
      # never depends on a later test helper or on dependency compile env.
      workspace_dep({:jido_integration_v2_store_local, "~> 0.1.0"}),
      workspace_dep({:citadel_authority_contract, "~> 0.1.0"}),
      workspace_dep({:citadel_governance, "~> 0.1.0"}),
      workspace_dep({:citadel_kernel, "~> 0.1.0"}),
      workspace_dep({:citadel_host_ingress_bridge, "~> 0.1.0"}),
      workspace_dep({:citadel_invocation_bridge, "~> 0.1.0"}),
      workspace_dep({:citadel_jido_integration_bridge, "~> 0.1.0"}),
      workspace_dep({:citadel_trace_bridge, "~> 0.1.0"}),
      workspace_dep({:citadel_domain_surface, "~> 0.1.0", override: true}),
      workspace_dep({:app_kit_app_config, "~> 0.1.0"}),
      workspace_dep({:app_kit_chat_surface, "~> 0.1.0"}),
      workspace_dep({:app_kit_domain_surface, "~> 0.1.0"}),
      workspace_dep({:app_kit_installation_surface, "~> 0.1.0"}),
      workspace_dep({:app_kit_mezzanine_bridge, "~> 0.1.0"}),
      workspace_dep({:app_kit_operator_surface, "~> 0.1.0"}),
      workspace_dep({:app_kit_review_surface, "~> 0.1.0"}),
      workspace_dep({:app_kit_run_governance, "~> 0.1.0"}),
      workspace_dep({:app_kit_scope_objects, "~> 0.1.0"}),
      workspace_dep({:app_kit_work_control, "~> 0.1.0"}),
      workspace_dep({:app_kit_work_surface, "~> 0.1.0"}),
      workspace_dep({:mezzanine_core, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_runtime_profile, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_audit_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_config_registry, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_decision_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_evidence_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_archival_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_barriers, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_lifecycle_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_object_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_execution_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_operator_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_pack_compiler, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_pack_model, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_projection_engine, "~> 0.1.0", override: true}),
      workspace_dep({:mezzanine_m1_m2_runtime, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_runtime_scheduler, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_source_engine, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_substrate_model, "~> 0.1.0", override: true}),
      workspace_dep({:mezzanine_workflow_runtime, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_citadel_bridge, "~> 0.1.0", override: true}),
      workspace_dep({:mezzanine_integration_bridge, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:mezzanine_leasing, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep({:jido_integration_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:jido_integration_v2_control_plane, "~> 0.1.0", runtime: false}),
      workspace_dep({:jido_integration_v2, "~> 0.1.0", runtime: false}),
      workspace_dep({:jido_integration_v2_brain_ingress, "~> 0.1.0"}),
      workspace_dep({:jido_integration_v2_runtime_router, "~> 0.1.0", runtime: false}),
      workspace_dep({:jido_integration_v2_store_postgres, "~> 0.1.0", runtime: false}),
      workspace_dep({:ground_plane_contracts, "~> 0.1.0", runtime: false, override: true}),
      workspace_dep(
        {:ground_plane_persistence_policy, "~> 0.1.0", runtime: false, override: true}
      ),
      workspace_dep({:execution_plane, "~> 0.2.0", override: true}),
      workspace_dep({:execution_plane_node, "~> 0.1.0", override: true}),
      workspace_dep({:execution_plane_process, "~> 0.1.0", override: true}),
      workspace_dep({:execution_plane_http, "~> 0.1.0", override: true}),
      workspace_dep({:agent_session_manager, "~> 0.12.0", override: true}),
      workspace_dep({:cli_subprocess_core, "~> 0.4.0"}),
      workspace_dep({:pristine, "~> 0.2.0", override: true}),
      workspace_dep({:prismatic, "~> 0.2.0", override: true}),
      workspace_dep({:self_hosted_inference_core, "~> 0.2.0"}),
      workspace_dep({:crucible_provider_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:crucible_signal, "~> 0.1.0", override: true}),
      workspace_dep({:crucible_signal_trace, "~> 0.1.0", override: true}),
      workspace_dep({:crucible_tap, "~> 0.1.0", override: true}),
      workspace_dep({:outer_brain_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:outer_brain_domain_bridge, "~> 0.1.0", override: true}),
      workspace_dep({:outer_brain_journal, "~> 0.1.0"}),
      workspace_dep({:outer_brain_memory_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:outer_brain_prompting, "~> 0.1.0", override: true}),
      workspace_dep({:outer_brain_persistence, "~> 0.1.0"}),
      workspace_dep({:outer_brain_restart_authority, "~> 0.1.0"}),
      workspace_dep({:outer_brain_runtime, "~> 0.1.0"}),
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

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
