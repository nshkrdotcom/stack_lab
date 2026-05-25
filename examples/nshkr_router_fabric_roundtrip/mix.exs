defmodule StackLab.NSHKRRouterFabricRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_nshkr_router_fabric_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct],
      name: "StackLab NSHKR Router Fabric Roundtrip",
      description: "Deterministic provider-free NSHKR router fabric proof"
    ]
  end

  def application do
    [extra_applications: [:crypto, :logger]]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp deps do
    [
      {:app_kit_context_surface, path: "../../../app_kit/core/context_surface"},
      {:app_kit_eval_surface, path: "../../../app_kit/core/eval_surface"},
      {:outer_brain_context_abi, path: "../../../outer_brain/core/context_abi", override: true},
      {:outer_brain_prompting,
       path: "../../../outer_brain/core/outer_brain_prompting", override: true},
      {:citadel_context_authority_contract,
       path: "../../../citadel/core/context_authority_contract"},
      {:mezzanine_context_packet_engine,
       path: "../../../mezzanine/core/context_packet_engine", override: true},
      {:mezzanine_ai_execution_engine,
       path: "../../../mezzanine/core/ai_execution_engine", override: true},
      {:mezzanine_eval_engine, path: "../../../mezzanine/core/eval_engine"},
      {:jido_model_invocation_contracts,
       path: "../../../jido_integration/core/model_invocation_contracts", override: true},
      {:jido_inference_runtime, path: "../../../jido_integration/core/inference_runtime"},
      {:aitrace, path: "../../../AITrace"},
      {:trinity_coordinator_core,
       path: "../../../trinity_framework/core/trinity_coordinator_core"},
      {:trinity_contracts,
       path: "../../../trinity_framework/core/trinity_contracts", override: true},
      {:stack_lab_context_abi_scanner, path: "../../support/context_abi_scanner"},
      {:stack_lab_router_fabric_scanner, path: "../../support/router_fabric_scanner"},
      {:stack_lab_coordination_fabric_scanner, path: "../../support/coordination_fabric_scanner"},
      {:stack_lab_model_inference_scanner, path: "../../support/model_inference_scanner"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "dialyzer --format short",
        "docs"
      ]
    ]
  end
end
