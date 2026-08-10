unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.HiveRoundtrip.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :stack_lab_hive_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_tree],
      name: "StackLab Hive Roundtrip",
      description: "Multi-agent coordination proof roundtrip"
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
      DependencySources.dep(:jido_hive_agent_coordinator, @dependency_sources_root),
      DependencySources.dep(:jido_hive_inter_agent_messaging, @dependency_sources_root),
      DependencySources.dep(:jido_hive_shared_memory_facade, @dependency_sources_root),
      DependencySources.dep(:jido_hive_coordination_patterns, @dependency_sources_root),
      DependencySources.dep(:app_kit_hive_surface, @dependency_sources_root),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
