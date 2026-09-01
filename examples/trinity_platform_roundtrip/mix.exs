if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule StackLab.TRINITYPlatformRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_trinity_platform_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_direct],
      name: "StackLab TRINITY Platform Roundtrip",
      description: "Deterministic governed TRINITY coordination proof"
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
      workspace_dep({:trinity_framework, "~> 0.1.0"}),
      workspace_dep({:trinity_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:crucible_policy, "~> 0.1.0", override: true}),
      workspace_dep({:crucible_signal, "~> 0.1.0", override: true}),
      workspace_dep({:crucible_signal_trace, "~> 0.1.0", override: true}),
      workspace_dep({:crucible_tap, "~> 0.1.0", override: true}),
      workspace_dep({:app_kit_coordination_surface, "~> 0.1.0"}),
      {:stack_lab_coordination_fabric_scanner, path: "../../support/coordination_fabric_scanner"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "deps.get",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "dialyzer --format short",
        "docs"
      ]
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
