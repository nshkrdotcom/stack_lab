defmodule StackLab.GEPAPlatformRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_gepa_platform_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      name: "StackLab GEPA Platform Roundtrip",
      description: "Deterministic governed GEPA optimization proof"
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
      {:gepa_framework, path: "../../../gepa_framework"},
      {:gepa_buildout, path: "../../../gepa_buildout"},
      {:stack_lab_model_inference_scanner, path: "../../support/model_inference_scanner"},
      {:stack_lab_optimization_fabric_scanner, path: "../../support/optimization_fabric_scanner"},
      {:stack_lab_ai_run_lineage_scanner, path: "../../support/ai_run_lineage_scanner"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
