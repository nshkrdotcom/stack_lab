defmodule StackLab.CitadelSpineHarness.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_citadel_spine_harness,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "StackLab Citadel Spine Harness",
      description: "Harness-only assembly package for Citadel and Jido Integration proofs"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:stack_lab_lab_core, path: "../lab_core"},
      {:ecto_sql, "~> 3.13"},
      {:citadel_authority_contract, path: "../../../citadel/core/authority_contract"},
      {:citadel_core, path: "../../../citadel/core/citadel_core"},
      {:citadel_runtime, path: "../../../citadel/core/citadel_runtime"},
      {:citadel_host_ingress_bridge, path: "../../../citadel/bridges/host_ingress_bridge"},
      {:citadel_invocation_bridge, path: "../../../citadel/bridges/invocation_bridge"},
      {:citadel_jido_integration_bridge,
       path: "../../../citadel/bridges/jido_integration_bridge"},
      {:citadel_domain_surface, path: "../../../citadel/surfaces/citadel_domain_surface"},
      {:app_kit_app_config, path: "../../../app_kit/core/app_config"},
      {:app_kit_chat_surface, path: "../../../app_kit/core/chat_surface"},
      {:app_kit_domain_surface, path: "../../../app_kit/core/domain_surface"},
      {:app_kit_installation_surface, path: "../../../app_kit/core/installation_surface"},
      {:app_kit_mezzanine_bridge, path: "../../../app_kit/bridges/mezzanine_bridge"},
      {:app_kit_operator_surface, path: "../../../app_kit/core/operator_surface"},
      {:app_kit_review_surface, path: "../../../app_kit/core/review_surface"},
      {:app_kit_scope_objects, path: "../../../app_kit/core/scope_objects"},
      {:app_kit_work_control, path: "../../../app_kit/core/work_control"},
      {:app_kit_work_surface, path: "../../../app_kit/core/work_surface"},
      {:mezzanine_ops_model, path: "../../../mezzanine/core/ops_model", runtime: false},
      {:mezzanine_audit_engine, path: "../../../mezzanine/core/audit_engine", runtime: false},
      {:mezzanine_config_registry,
       path: "../../../mezzanine/core/config_registry", runtime: false},
      {:mezzanine_decision_engine,
       path: "../../../mezzanine/core/decision_engine", runtime: false},
      {:mezzanine_evidence_engine,
       path: "../../../mezzanine/core/evidence_engine", runtime: false},
      {:mezzanine_object_engine, path: "../../../mezzanine/core/object_engine", runtime: false},
      {:mezzanine_execution_engine,
       path: "../../../mezzanine/core/execution_engine", runtime: false},
      {:mezzanine_ops_assurance, path: "../../../mezzanine/core/ops_assurance", runtime: false},
      {:mezzanine_ops_audit, path: "../../../mezzanine/core/ops_audit", runtime: false},
      {:mezzanine_ops_control, path: "../../../mezzanine/core/ops_control", runtime: false},
      {:mezzanine_ops_domain, path: "../../../mezzanine/core/ops_domain", runtime: false},
      {:mezzanine_pack_compiler, path: "../../../mezzanine/core/pack_compiler", runtime: false},
      {:mezzanine_runtime_scheduler,
       path: "../../../mezzanine/core/runtime_scheduler", runtime: false},
      {:mezzanine_app_kit_bridge,
       path: "../../../mezzanine/bridges/app_kit_bridge", runtime: false},
      {:mezzanine_citadel_bridge, path: "../../../mezzanine/bridges/citadel_bridge"},
      {:mezzanine_integration_bridge,
       path: "../../../mezzanine/bridges/integration_bridge", runtime: false},
      {:jido_integration_v2_contracts,
       path: "../../../jido_integration/core/contracts", override: true},
      {:jido_integration_v2, path: "../../../jido_integration/core/platform"},
      {:jido_integration_v2_brain_ingress, path: "../../../jido_integration/core/brain_ingress"},
      {:jido_integration_v2_store_local, path: "../../../jido_integration/core/store_local"},
      {:outer_brain_journal, path: "../../../outer_brain/core/outer_brain_journal"},
      {:outer_brain_persistence, path: "../../../outer_brain/core/outer_brain_persistence"},
      {:outer_brain_restart_authority,
       path: "../../../outer_brain/core/outer_brain_restart_authority"},
      {:outer_brain_runtime, path: "../../../outer_brain/core/outer_brain_runtime"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
