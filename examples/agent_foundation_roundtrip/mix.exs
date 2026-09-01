if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule StackLab.AgentFoundationRoundtrip.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_agent_foundation_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: [main: "readme", extras: ["README.md"]],
      dialyzer: [plt_add_deps: :apps_tree, plt_add_apps: [:mix]],
      name: "StackLab Agent Foundation Roundtrip",
      description: "Deterministic native agent foundation acceptance proof"
    ]
  end

  def application do
    [extra_applications: [:logger, :crypto]]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp deps do
    [
      workspace_dep({:app_kit_core, "~> 0.1.0"}),
      workspace_dep({:mezzanine_agent_turn_engine, "~> 0.1.0"}),
      workspace_dep({:citadel_execution_governance_contract, "~> 0.1.0"}),
      workspace_dep({:jido_integration_agent_interop_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:jido_integration_v2_tool_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:jido_integration_connector_admission_engine, "~> 0.1.0"}),
      workspace_dep({:execution_plane, "~> 0.2.0"}),
      workspace_dep({:ai_trace_replay_contracts, "~> 0.1.0"}),
      {:stack_lab_no_bypass_scanner, path: "../../support/no_bypass_scanner"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
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
        "credo --strict",
        "dialyzer --force-check",
        "docs --warnings-as-errors"
      ]
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
