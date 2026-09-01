if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule StackLab.GovernedProviderRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_governed_provider_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      name: "StackLab Governed Provider Roundtrip",
      description: "Governed provider proof example for StackLab Phase 15"
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
      {:stack_lab_citadel_spine_harness,
       path: "../../support/citadel_spine_harness", runtime: false},
      {:stack_lab_memsim_harness, path: "../../support/memsim_harness", runtime: false},
      workspace_dep({:jido_integration_provider_classification, "~> 0.1.0"}),
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

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
