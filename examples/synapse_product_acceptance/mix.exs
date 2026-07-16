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
      applications: applications(Mix.env())
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        "stack_lab.proof_app.synapse.acceptance": :test,
        "stack_lab.proof_app.synapse.live_slice": :test,
        "stack_lab.proof_app.synapse.staged_live.v1": :test
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
      {:mezzanine_governed_effects,
       path: "#{@repo_root}/mezzanine/core/governed_effects", override: true},
      {:citadel_authority_contract,
       path: "#{@repo_root}/citadel/core/authority_contract", override: true},
      {:jido_integration_v2_direct_runtime,
       path: "#{@repo_root}/jido_integration/core/direct_runtime", override: true},
      {:aitrace, path: "#{@repo_root}/AITrace", override: true},
      {:stack_lab_no_bypass_scanner, path: "../../support/no_bypass_scanner"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false}
    ]
  end

  defp applications(:dev),
    do: applications(:test) ++ [:makeup, :makeup_elixir, :makeup_erlang, :ex_doc]

  defp applications(_env) do
    [
      :logger,
      :synapse_core,
      :stack_lab_no_bypass_scanner,
      :ground_plane_contracts,
      :execution_plane,
      :mezzanine_governed_effects,
      :citadel_authority_contract,
      :jido_integration_v2_direct_runtime,
      :aitrace
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "cmd env MIX_ENV=test mix credo --strict",
        "stack_lab.proof_app.synapse.acceptance --json",
        "stack_lab.proof_app.synapse.live_slice --json",
        "stack_lab.proof_app.synapse.staged_live.v1 --json"
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
