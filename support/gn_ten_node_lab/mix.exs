defmodule StackLab.GnTenNodeLab.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_gn_ten_node_lab,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct],
      name: "StackLab Gn-Ten Node Lab",
      description: "Local BEAM node orchestration support for StackLab gn-ten proofs"
    ]
  end

  def application do
    [extra_applications: [:crypto, :logger]]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp deps do
    [
      {:stack_lab_lab_core, path: "../lab_core"},
      {:stack_lab_spec_cell, path: "../spec_cell"},
      {:stack_lab_gn_ten_control_plane, path: "../gn_ten_control_plane"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
