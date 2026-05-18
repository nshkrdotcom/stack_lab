defmodule StackLab.SessionLineageDrill.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_session_lineage_drill,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "StackLab Session Lineage Drill",
      description: "Session-lineage proving example for StackLab"
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "docs/receipts/agent_turn_runtime_patterns.md"]
    ]
  end
end
