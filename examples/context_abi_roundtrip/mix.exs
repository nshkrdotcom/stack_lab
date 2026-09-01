if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule StackLab.ContextABIRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_context_abi_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct],
      name: "StackLab Context ABI Roundtrip",
      description: "Deterministic provider-free Context ABI platform proof"
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
      workspace_dep({:app_kit_context_surface, "~> 0.1.0"}),
      workspace_dep({:outer_brain_context_abi, "~> 0.1.0", override: true}),
      workspace_dep({:outer_brain_prompting, "~> 0.1.0", override: true}),
      workspace_dep({:citadel_context_authority_contract, "~> 0.1.0"}),
      workspace_dep({:mezzanine_context_packet_engine, "~> 0.1.0", override: true}),
      workspace_dep({:mezzanine_ai_execution_engine, "~> 0.1.0"}),
      workspace_dep({:ground_plane_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:jido_model_invocation_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:jido_inference_runtime, "~> 0.1.0"}),
      workspace_dep({:aitrace, "~> 0.1.0"}),
      {:stack_lab_context_abi_scanner, path: "../../support/context_abi_scanner"},
      {:stack_lab_model_inference_scanner, path: "../../support/model_inference_scanner"},
      {:stack_lab_cost_budget_scanner, path: "../../support/cost_budget_scanner"},
      {:stack_lab_ai_run_lineage_scanner, path: "../../support/ai_run_lineage_scanner"},
      {:stack_lab_tenant_isolation_scanner, path: "../../support/tenant_isolation_scanner"},
      {:stack_lab_memory_fabric_scanner, path: "../../support/memory_fabric_scanner"},
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

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
