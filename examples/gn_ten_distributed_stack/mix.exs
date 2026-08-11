unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.GnTenDistributedStack.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :stack_lab_gn_ten_distributed_stack,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct],
      name: "StackLab Gn-Ten Distributed Stack",
      description: "Local distributed gn-ten StackLab proof app"
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
      {:stack_lab_gn_ten_node_lab, path: "../../support/gn_ten_node_lab", runtime: false},
      {:stack_lab_context_abi_roundtrip, path: "../context_abi_roundtrip", runtime: false},
      {:stack_lab_nshkr_router_fabric_roundtrip,
       path: "../nshkr_router_fabric_roundtrip", runtime: false},
      {:stack_lab_persistence_mode_roundtrip,
       path: "../persistence_mode_roundtrip", runtime: false},
      DependencySources.dep(:ground_plane_contracts, @dependency_sources_root,
        override: true,
        runtime: false
      ),
      DependencySources.dep(:crucible_policy, @dependency_sources_root,
        override: true,
        runtime: false
      ),
      DependencySources.dep(:crucible_signal, @dependency_sources_root,
        override: true,
        runtime: false
      ),
      DependencySources.dep(:crucible_signal_trace, @dependency_sources_root,
        override: true,
        runtime: false
      ),
      DependencySources.dep(:crucible_tap, @dependency_sources_root,
        override: true,
        runtime: false
      ),
      DependencySources.dep(:app_kit_mezzanine_bridge, @dependency_sources_root, runtime: false),
      DependencySources.dep(:mezzanine_execution_engine, @dependency_sources_root,
        runtime: false
      ),
      DependencySources.dep(:citadel_context_authority_contract, @dependency_sources_root,
        runtime: false
      ),
      DependencySources.dep(:outer_brain_context_abi, @dependency_sources_root,
        override: true,
        runtime: false
      ),
      DependencySources.dep(:jido_inference_runtime, @dependency_sources_root, runtime: false),
      DependencySources.dep(:execution_plane, @dependency_sources_root,
        override: true,
        runtime: false
      ),
      DependencySources.dep(:aitrace, @dependency_sources_root, override: true, runtime: false),
      {:jason, "~> 1.4", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
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
        "docs"
      ]
    ]
  end
end
