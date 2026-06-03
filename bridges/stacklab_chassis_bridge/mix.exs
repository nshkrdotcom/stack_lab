defmodule StackLab.ChassisBridge.MixProject do
  use Mix.Project

  def project do
    [
      app: :stacklab_chassis_bridge,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps: deps(),
      description: "StackLab proof catalog bridge for Chassis"
    ]
  end

  def application, do: [extra_applications: [:logger]]

  def cli do
    [preferred_envs: [ci: :test]]
  end

  defp deps do
    [
      {:chassis_evolution_conformance,
       path: "../../../chassis/proof/chassis_evolution_conformance"},
      {:chassis_stacklab_bridge, path: "../../../chassis/proof/chassis_stacklab_bridge"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end
end
