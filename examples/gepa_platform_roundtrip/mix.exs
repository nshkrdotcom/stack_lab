unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("../../build_support/dependency_sources.exs", __DIR__)
end

defmodule StackLab.GEPAPlatformRoundtrip.MixProject do
  use Mix.Project

  @dependency_sources_root Path.expand("../..", __DIR__)

  def project do
    [
      app: :stack_lab_gepa_platform_roundtrip,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [main: "readme", extras: ["README.md"]],
      name: "StackLab GEPA Platform Roundtrip",
      description: "Deterministic governed GEPA optimization proof"
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
      DependencySources.dep(:gepa_framework, @dependency_sources_root),
      DependencySources.dep(:mezzanine_optimization_engine, @dependency_sources_root),
      DependencySources.dep(:mezzanine_ai_execution_engine, @dependency_sources_root,
        override: true
      ),
      DependencySources.dep(:outer_brain_context_abi, @dependency_sources_root, override: true),
      DependencySources.dep(:app_kit_optimization_surface, @dependency_sources_root),
      {:stack_lab_model_inference_scanner, path: "../../support/model_inference_scanner"},
      {:stack_lab_optimization_fabric_scanner, path: "../../support/optimization_fabric_scanner"},
      {:stack_lab_ai_run_lineage_scanner, path: "../../support/ai_run_lineage_scanner"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
