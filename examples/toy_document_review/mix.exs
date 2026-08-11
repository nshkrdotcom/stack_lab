unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.ToyDocumentReview.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

  @repo_root "/home/home/p/g/n"

  def project do
    [
      app: :stack_lab_toy_document_review,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      name: "StackLab Toy Document Review",
      description: "Deterministic generic substrate proof app for StackLab"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        setup: :test,
        "registry.setup": :test,
        "execution.setup": :test,
        "stack_lab.proof_app.toy_document_review.acceptance": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp aliases do
    [
      "registry.setup": [
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.create -r Mezzanine.ConfigRegistry.Repo --quiet",
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.migrate -r Mezzanine.ConfigRegistry.Repo --migrations-path #{@repo_root}/mezzanine/core/config_registry/priv/repo/migrations"
      ],
      "execution.setup": [
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.create -r Mezzanine.Execution.Repo --quiet",
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.migrate -r Mezzanine.Execution.Repo --migrations-path #{@repo_root}/mezzanine/core/leasing/priv/repo/migrations",
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.migrate -r Mezzanine.Execution.Repo --migrations-path #{@repo_root}/mezzanine/core/execution_engine/priv/repo/migrations"
      ],
      setup: ["registry.setup", "execution.setup"],
      test: ["setup", "test"],
      ci: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict",
        "cmd env MIX_ENV=dev mix docs --warnings-as-errors"
      ]
    ]
  end

  defp deps do
    [
      DependencySources.dep(:app_kit_core, @dependency_sources_root),
      DependencySources.dep(:app_kit_runtime_gateway, @dependency_sources_root),
      DependencySources.dep(:mezzanine_pack_model, @dependency_sources_root),
      DependencySources.dep(:mezzanine_pack_compiler, @dependency_sources_root),
      DependencySources.dep(:mezzanine_config_registry, @dependency_sources_root),
      DependencySources.dep(:mezzanine_substrate_model, @dependency_sources_root),
      DependencySources.dep(:mezzanine_projection_engine, @dependency_sources_root),
      DependencySources.dep(:mezzanine_workflow_runtime, @dependency_sources_root),
      DependencySources.dep(:jido_integration_contracts, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:jido_integration_v2_connector_registry, @dependency_sources_root),
      DependencySources.dep(:execution_plane, @dependency_sources_root, override: true),
      DependencySources.dep(:ground_plane_contracts, @dependency_sources_root, override: true),
      DependencySources.dep(:citadel_governance, @dependency_sources_root),
      DependencySources.dep(:citadel_connector_binding, @dependency_sources_root),
      DependencySources.dep(:aitrace, @dependency_sources_root, override: true),
      DependencySources.dep(:ai_trace_replay_contracts, @dependency_sources_root, override: true),
      DependencySources.dep(:ai_trace_replay_engine, @dependency_sources_root),
      {:ecto_sql, "~> 3.13"},
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
