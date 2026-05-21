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
      {:app_kit_core, path: "../../../app_kit/core/app_kit_core"},
      {:mezzanine_agent_turn_engine, path: "../../../mezzanine/core/agent_turn_engine"},
      {:citadel_execution_governance_contract,
       path: "../../../citadel/core/execution_governance_contract"},
      {:jido_integration_agent_interop_contracts,
       path: "../../../jido_integration/core/agent_interop_contracts", override: true},
      {:jido_integration_v2_tool_contracts,
       path: "../../../jido_integration/core/tool_contracts", override: true},
      {:jido_integration_connector_admission_engine,
       path: "../../../jido_integration/core/connector_admission_engine"},
      {:execution_plane, path: "../../../execution_plane/core/execution_plane"},
      {:ai_trace_replay_contracts, path: "../../../AITrace/core/replay_contracts"},
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
end
