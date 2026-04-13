defmodule StackLab.SemanticHostRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_semantic_host_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "StackLab Semantic Host Roundtrip",
      description: "Semantic host proving example for AppKit and OuterBrain"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:stack_lab_lab_core, path: "../../support/lab_core"},
      {:stack_lab_citadel_spine_harness,
       path: "../../support/citadel_spine_harness", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
