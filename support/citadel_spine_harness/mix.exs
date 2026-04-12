defmodule StackLab.CitadelSpineHarness.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_citadel_spine_harness,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "StackLab Citadel Spine Harness",
      description: "Harness-only assembly package for Citadel and Jido Integration proofs"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:stack_lab_lab_core, path: "../lab_core"},
      {:citadel_core, path: "../../../citadel/core/citadel_core"},
      {:citadel_runtime, path: "../../../citadel/core/citadel_runtime"},
      {:citadel_authority_contract, path: "../../../citadel/core/authority_contract"},
      {:citadel_execution_governance_contract,
       path: "../../../citadel/core/execution_governance_contract"},
      {:citadel_invocation_bridge, path: "../../../citadel/bridges/invocation_bridge"},
      {:citadel_jido_integration_bridge,
       path: "../../../citadel/bridges/jido_integration_bridge"},
      {:jido_integration_v2_contracts,
       path: "../../../jido_integration/core/contracts", override: true},
      {:jido_integration_v2_brain_ingress, path: "../../../jido_integration/core/brain_ingress"},
      {:jido_integration_v2_store_local, path: "../../../jido_integration/core/store_local"},
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
