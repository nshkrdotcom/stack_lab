defmodule StackLab.GnTenDistributedStack.MixProject do
  use Mix.Project

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
      {:ground_plane_contracts,
       path: "../../../ground_plane/core/ground_plane_contracts", runtime: false},
      {:app_kit_mezzanine_bridge,
       path: "../../../app_kit/bridges/mezzanine_bridge", runtime: false},
      {:mezzanine_execution_engine,
       path: "../../../mezzanine/core/execution_engine", runtime: false},
      {:citadel_context_authority_contract,
       path: "../../../citadel/core/context_authority_contract", runtime: false},
      {:outer_brain_context_abi,
       path: "../../../outer_brain/core/context_abi", override: true, runtime: false},
      {:jido_inference_runtime,
       path: "../../../jido_integration/core/inference_runtime", runtime: false},
      {:execution_plane,
       path: "../../../execution_plane/core/execution_plane", override: true, runtime: false},
      {:aitrace, path: "../../../AITrace", override: true, runtime: false},
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
