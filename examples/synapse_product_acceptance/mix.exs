unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.SynapseProductAcceptance.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

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
      DependencySources.dep(:synapse_core, @dependency_sources_root),
      DependencySources.dep(:execution_plane, @dependency_sources_root, override: true),
      DependencySources.dep(:ground_plane_contracts, @dependency_sources_root, override: true),
      DependencySources.dep(:ground_plane_persistence_policy, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:app_kit_mezzanine_bridge, @dependency_sources_root),
      DependencySources.dep(:mezzanine_workflow_runtime, @dependency_sources_root),
      DependencySources.dep(:mezzanine_governed_effects, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:citadel_authority_contract, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:jido_integration_v2_direct_runtime, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:aitrace, @dependency_sources_root, override: true),
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
