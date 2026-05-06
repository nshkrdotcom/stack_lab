defmodule StackLab.GuardrailRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_guardrail_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_tree],
      name: "StackLab Guardrail Roundtrip",
      description: "Prompt and guardrail proof roundtrip"
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
      {:outer_brain_prompt_fabric, path: "../../../outer_brain/core/prompt_fabric"},
      {:outer_brain_guardrail_engine, path: "../../../outer_brain/core/guardrail_engine"},
      {:app_kit_prompt_surface, path: "../../../app_kit/core/prompt_surface"},
      {:app_kit_guardrail_surface, path: "../../../app_kit/core/guardrail_surface"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
