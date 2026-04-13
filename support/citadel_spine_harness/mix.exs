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
      {:citadel, path: "../../../citadel/dist/hex/citadel"},
      {:jido_domain, path: "../../../jido_domain"},
      {:app_kit_chat_surface, path: "../../../app_kit/core/chat_surface"},
      {:app_kit_domain_surface, path: "../../../app_kit/core/domain_surface"},
      {:app_kit_scope_objects, path: "../../../app_kit/core/scope_objects"},
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
