defmodule StackLab.TRINITYPlatformRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_trinity_platform_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct],
      name: "StackLab TRINITY Platform Roundtrip",
      description: "Deterministic governed TRINITY coordination proof"
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
      {:trinity_framework, path: "../../../trinity_framework"},
      {:trinity_contracts,
       path: "../../../trinity_framework/core/trinity_contracts", override: true},
      {:app_kit_coordination_surface, path: "../../../app_kit/core/coordination_surface"},
      {:stack_lab_coordination_fabric_scanner, path: "../../support/coordination_fabric_scanner"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
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
        "dialyzer --format short",
        "docs"
      ]
    ]
  end
end
