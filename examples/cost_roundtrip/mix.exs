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
      {:aitrace, path: "../../../AITrace"},
      {:outer_brain_token_meter, path: "../../../outer_brain/core/token_meter"},
      {:mezzanine_cost_attribution_engine,
       path: "../../../mezzanine/core/cost_attribution_engine"},
      {:mezzanine_budget_enforcement_engine,
       path: "../../../mezzanine/core/budget_enforcement_engine"},
      {:app_kit_cost_surface, path: "../../../app_kit/core/cost_surface"},
      {:app_kit_budget_surface, path: "../../../app_kit/core/budget_surface"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
