unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.NSHKRRouterFabricRoundtrip.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :stack_lab_nshkr_router_fabric_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct, plt_add_apps: [:mix]],
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
      DependencySources.dep(:app_kit_context_surface, @dependency_sources_root),
      DependencySources.dep(:app_kit_eval_surface, @dependency_sources_root),
      DependencySources.dep(:outer_brain_context_abi, @dependency_sources_root, override: true),
      DependencySources.dep(:outer_brain_prompting, @dependency_sources_root, override: true),
      DependencySources.dep(:citadel_context_authority_contract, @dependency_sources_root),
      DependencySources.dep(:mezzanine_context_packet_engine, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:mezzanine_ai_execution_engine, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:mezzanine_eval_engine, @dependency_sources_root),
      DependencySources.dep(:jido_model_invocation_contracts, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:jido_inference_runtime, @dependency_sources_root),
      DependencySources.dep(:aitrace, @dependency_sources_root),
      DependencySources.dep(:trinity_coordinator_core, @dependency_sources_root),
      DependencySources.dep(:trinity_contracts, @dependency_sources_root, override: true),
      {:stack_lab_context_abi_scanner, path: "../../support/context_abi_scanner"},
      {:stack_lab_router_fabric_scanner, path: "../../support/router_fabric_scanner"},
      {:stack_lab_coordination_fabric_scanner, path: "../../support/coordination_fabric_scanner"},
      {:stack_lab_model_inference_scanner, path: "../../support/model_inference_scanner"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
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
