defmodule StackLab.ToyDocumentReview.MixProject do
  use Mix.Project

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
        "execution.setup": :test
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
      {:mezzanine_pack_model, path: "#{@repo_root}/mezzanine/core/pack_model"},
      {:mezzanine_pack_compiler, path: "#{@repo_root}/mezzanine/core/pack_compiler"},
      {:mezzanine_config_registry, path: "#{@repo_root}/mezzanine/core/config_registry"},
      {:mezzanine_substrate_model, path: "#{@repo_root}/mezzanine/core/substrate_model"},
      {:mezzanine_projection_engine, path: "#{@repo_root}/mezzanine/core/projection_engine"},
      {:mezzanine_workflow_runtime, path: "#{@repo_root}/mezzanine/core/workflow_runtime"},
      {:jido_integration_contracts,
       path: "#{@repo_root}/jido_integration/core/contracts", override: true},
      {:jido_integration_v2_connector_registry,
       path: "#{@repo_root}/jido_integration/core/connector_registry"},
      {:execution_plane,
       path: "#{@repo_root}/execution_plane/core/execution_plane", override: true},
      {:citadel_governance, path: "#{@repo_root}/citadel/core/citadel_governance"},
      {:citadel_connector_binding, path: "#{@repo_root}/citadel/core/connector_binding"},
      {:aitrace, path: "#{@repo_root}/AITrace", override: true},
      {:ai_trace_replay_contracts, path: "#{@repo_root}/AITrace/core/replay_contracts"},
      {:ai_trace_replay_engine, path: "#{@repo_root}/AITrace/core/replay_engine"},
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
