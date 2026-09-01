if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule StackLab.ToyDocumentReview.MixProject do
  use Mix.Project

  @mezzanine_root Path.expand("../../../mezzanine", __DIR__)

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
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.migrate -r Mezzanine.ConfigRegistry.Repo --migrations-path #{@mezzanine_root}/core/config_registry/priv/repo/migrations"
      ],
      "execution.setup": [
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.create -r Mezzanine.Execution.Repo --quiet",
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.migrate -r Mezzanine.Execution.Repo --migrations-path #{@mezzanine_root}/core/leasing/priv/repo/migrations",
        "cmd env MIX_ENV=test STACK_LAB_TOY_SCHEMA_SETUP=1 mix ecto.migrate -r Mezzanine.Execution.Repo --migrations-path #{@mezzanine_root}/core/execution_engine/priv/repo/migrations"
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
      workspace_dep({:app_kit_core, "~> 0.1.0"}),
      workspace_dep({:app_kit_runtime_gateway, "~> 0.1.0"}),
      workspace_dep({:mezzanine_pack_model, "~> 0.1.0"}),
      workspace_dep({:mezzanine_pack_compiler, "~> 0.1.0"}),
      workspace_dep({:mezzanine_config_registry, "~> 0.1.0"}),
      workspace_dep({:mezzanine_substrate_model, "~> 0.1.0"}),
      workspace_dep({:mezzanine_projection_engine, "~> 0.1.0"}),
      workspace_dep({:mezzanine_workflow_runtime, "~> 0.1.0"}),
      workspace_dep({:jido_integration_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:jido_integration_v2_connector_registry, "~> 0.1.0"}),
      workspace_dep({:execution_plane, "~> 0.2.0", override: true}),
      workspace_dep({:ground_plane_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:citadel_governance, "~> 0.1.0"}),
      workspace_dep({:citadel_connector_binding, "~> 0.1.0"}),
      workspace_dep({:aitrace, "~> 0.1.0", override: true}),
      workspace_dep({:ai_trace_replay_contracts, "~> 0.1.0", override: true}),
      workspace_dep({:ai_trace_replay_engine, "~> 0.1.0"}),
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

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end
end
