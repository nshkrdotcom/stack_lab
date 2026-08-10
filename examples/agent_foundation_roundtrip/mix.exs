unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.AgentFoundationRoundtrip.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

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
      DependencySources.dep(:app_kit_core, @dependency_sources_root),
      DependencySources.dep(:mezzanine_agent_turn_engine, @dependency_sources_root),
      DependencySources.dep(:citadel_execution_governance_contract, @dependency_sources_root),
      DependencySources.dep(:jido_integration_agent_interop_contracts, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:jido_integration_v2_tool_contracts, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(
        :jido_integration_connector_admission_engine,
        @dependency_sources_root
      ),
      DependencySources.dep(:execution_plane, @dependency_sources_root),
      DependencySources.dep(:ai_trace_replay_contracts, @dependency_sources_root),
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
