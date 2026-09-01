if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

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
      workspace_dep({:aitrace, "~> 0.1.0", override: true}),
      workspace_dep({:ai_trace_replay_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:ai_trace_replay_engine, "~> 0.1.0"}),
      workspace_dep({:app_kit_replay_surface, "~> 0.1.0"}),
      {:stack_lab_drift_detector, path: "../../support/drift_detector"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
