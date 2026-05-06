defmodule StackLab.SkillRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_skill_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_tree],
      name: "StackLab Skill Roundtrip",
      description: "Skill admission and invocation proof roundtrip"
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
      {:jido_hive_skill_contracts, path: "../../../jido_hive/core/skill_contracts"},
      {:jido_hive_skill_engine, path: "../../../jido_hive/core/skill_engine"},
      {:jido_hive_skill_conformance_contracts,
       path: "../../../jido_hive/conformance_contracts/skill_conformance_contracts",
       only: [:dev, :test],
       runtime: false},
      {:app_kit_skill_surface, path: "../../../app_kit/core/skill_surface"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
