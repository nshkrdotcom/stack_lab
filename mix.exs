defmodule StackLab.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/stack_lab"
  @description "Starter harness for local distributed development, fault drills, and end-to-end examples across the nshkr infrastructure stack."

  def project do
    [
      app: :stack_lab,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: @description,
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "StackLab"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {StackLab.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test
      ]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      ci: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test"
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["nshkrdotcom"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(.formatter.exs CHANGELOG.md LICENSE README.md assets docs lib mix.exs test)
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "StackLab",
      logo: "assets/stack_lab.svg",
      assets: %{"assets" => "assets"},
      source_ref: "main",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: [
        "README.md",
        "docs/overview.md",
        "docs/development.md",
        "docs/layout.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Overview: ["README.md", "docs/overview.md"],
        Development: ["docs/development.md", "docs/layout.md"],
        Project: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end
end
