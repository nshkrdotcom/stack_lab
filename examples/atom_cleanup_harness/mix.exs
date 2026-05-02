defmodule StackLab.AtomCleanupHarness.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_atom_cleanup_harness,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "StackLab Atom Cleanup Harness",
      description: "Dynamic atom cleanup proof harness for StackLab"
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
      {:stack_lab_spec_cell, path: "../../support/spec_cell"},
      {:stack_lab_gn_ten_control_plane, path: "../../support/gn_ten_control_plane"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
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
