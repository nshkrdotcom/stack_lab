if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

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
      workspace_dep({:ground_plane_contracts, "~> 0.1.0", override: true, runtime: false}),
      workspace_dep({:crucible_policy, "~> 0.1.0", override: true, runtime: false}),
      workspace_dep({:crucible_signal, "~> 0.1.0", override: true, runtime: false}),
      workspace_dep({:crucible_signal_trace, "~> 0.1.0", override: true, runtime: false}),
      workspace_dep({:crucible_tap, "~> 0.1.0", override: true, runtime: false}),
      workspace_dep({:app_kit_mezzanine_bridge, "~> 0.1.0", runtime: false}),
      workspace_dep({:mezzanine_execution_engine, "~> 0.1.0", runtime: false}),
      workspace_dep({:citadel_context_authority_contract, "~> 0.1.0", runtime: false}),
      workspace_dep({:outer_brain_context_abi, "~> 0.1.0", override: true, runtime: false}),
      workspace_dep({:jido_inference_runtime, "~> 0.1.0", runtime: false}),
      workspace_dep({:execution_plane, "~> 0.2.0", override: true, runtime: false}),
      workspace_dep({:aitrace, "~> 0.1.0", override: true, runtime: false}),
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

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
