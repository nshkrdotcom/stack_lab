unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.CostRoundtrip.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

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
      DependencySources.dep(:aitrace, @dependency_sources_root),
      DependencySources.dep(:outer_brain_token_meter, @dependency_sources_root),
      DependencySources.dep(:mezzanine_cost_attribution_engine, @dependency_sources_root),
      DependencySources.dep(:mezzanine_budget_enforcement_engine, @dependency_sources_root),
      DependencySources.dep(:app_kit_cost_surface, @dependency_sources_root),
      DependencySources.dep(:app_kit_budget_surface, @dependency_sources_root),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
