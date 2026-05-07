defmodule StackLab.PersistenceModeRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_persistence_mode_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct],
      name: "StackLab Persistence Mode Roundtrip",
      description: "Deterministic persistence profile matrix proof"
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
      {:ground_plane_persistence_policy, path: "../../../ground_plane/core/persistence_policy"},
      {:stack_lab_persistence_matrix_scanner, path: "../../support/persistence_matrix_scanner"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]
  end
end
