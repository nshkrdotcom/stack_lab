defmodule StackLab.ReplayRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_replay_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_tree],
      name: "StackLab Replay Roundtrip",
      description: "Replay, divergence, and drift proof roundtrip"
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
      {:aitrace, path: "../../../AITrace"},
      {:ai_trace_replay_contracts,
       path: "../../../AITrace/core/replay_contracts", override: true},
      {:ai_trace_replay_engine, path: "../../../AITrace/core/replay_engine"},
      {:app_kit_replay_surface, path: "../../../app_kit/core/replay_surface"},
      {:stack_lab_drift_detector, path: "../../support/drift_detector"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
