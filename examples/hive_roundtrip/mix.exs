defmodule StackLab.HiveRoundtrip.MixProject do
  use Mix.Project

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
      {:jido_hive_agent_coordinator, path: "../../../jido_hive/core/agent_coordinator"},
      {:jido_hive_inter_agent_messaging, path: "../../../jido_hive/core/inter_agent_messaging"},
      {:jido_hive_shared_memory_facade, path: "../../../jido_hive/core/shared_memory_facade"},
      {:jido_hive_coordination_patterns, path: "../../../jido_hive/core/coordination_patterns"},
      {:app_kit_hive_surface, path: "../../../app_kit/core/hive_surface"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
