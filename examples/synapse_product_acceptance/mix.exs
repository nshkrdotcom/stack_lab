defmodule StackLab.SynapseProductAcceptance.MixProject do
  use Mix.Project

  @repo_root "/home/home/p/g/n"

  def project do
    [
      app: :stack_lab_synapse_product_acceptance,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      name: "StackLab Synapse Product Acceptance",
      description: "External product acceptance proof for the Synapse AppKit-only rewrite"
    ]
  end

  def application do
    [
      applications: [:logger, :synapse_core, :stack_lab_no_bypass_scanner]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        "stack_lab.proof_app.synapse.acceptance": :test,
        "stack_lab.proof_app.synapse.live_slice": :test
      ]
    ]
  end

  defp deps do
    [
      {:synapse_core, path: "#{@repo_root}/synapse/apps/synapse_core"},
      {:execution_plane,
       path: "#{@repo_root}/execution_plane/core/execution_plane", override: true},
      {:ground_plane_contracts,
       path: "#{@repo_root}/ground_plane/core/ground_plane_contracts", override: true},
      {:ground_plane_persistence_policy,
       path: "#{@repo_root}/ground_plane/core/persistence_policy", override: true},
      {:app_kit_mezzanine_bridge, path: "#{@repo_root}/app_kit/bridges/mezzanine_bridge"},
      {:mezzanine_workflow_runtime, path: "#{@repo_root}/mezzanine/core/workflow_runtime"},
      {:stack_lab_no_bypass_scanner, path: "../../support/no_bypass_scanner"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "stack_lab.proof_app.synapse.acceptance --json",
        "stack_lab.proof_app.synapse.live_slice --json",
        "credo --strict"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
