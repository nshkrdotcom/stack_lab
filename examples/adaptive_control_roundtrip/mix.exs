defmodule StackLab.AdaptiveControlRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_adaptive_control_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct],
      name: "StackLab Adaptive Control Roundtrip",
      description: "Deterministic closed-loop adaptive-control proof"
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
      {:app_kit_adaptive_control_surface, path: "../../../app_kit/core/adaptive_control_surface"},
      {:stack_lab_adaptive_control_scanner, path: "../../support/adaptive_control_scanner"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]
  end
end
