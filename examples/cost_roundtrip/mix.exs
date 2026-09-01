if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule StackLab.CostRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_cost_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_tree],
      name: "StackLab Cost Roundtrip",
      description: "Cost attribution and budget enforcement proof roundtrip"
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp deps do
    [
      workspace_dep({:aitrace, "~> 0.1.0"}),
      workspace_dep({:outer_brain_token_meter, "~> 0.1.0"}),
      workspace_dep({:mezzanine_cost_attribution_engine, "~> 0.1.0"}),
      workspace_dep({:mezzanine_budget_enforcement_engine, "~> 0.1.0"}),
      workspace_dep({:app_kit_cost_surface, "~> 0.1.0"}),
      workspace_dep({:app_kit_budget_surface, "~> 0.1.0"}),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
