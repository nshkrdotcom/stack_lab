defmodule StackLabLabCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :stack_lab_lab_core,
      version: "0.1.0",
      build_path: "_build",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      erlc_paths: ["components/support/lab_core/src"],
      deps: deps(),
      description: "Support package projected from the StackLab workspace",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def elixirc_paths(:test) do
    base = ["config", "components/support/lab_core/lib"]

    if File.dir?("test/support") do
      base ++ ["test/support"]
    else
      base
    end
  end

  def elixirc_paths(_env), do: ["config", "components/support/lab_core/lib"]

  defp deps do
    [
      {:ex_doc, "~> 0.40", [only: :dev, runtime: false]}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: [],
      links: %{"Source" => "https://github.com/nshkrdotcom/stack_lab"},
      files: [
        ".formatter.exs",
        "CHANGELOG.md",
        "LICENSE",
        "README.md",
        "components/support/lab_core",
        "config",
        "docs/development.md",
        "docs/layout.md",
        "docs/overview.md",
        "docs/runbooks/faults.md",
        "docs/runbooks/up_multi.md",
        "docs/runbooks/up_single.md",
        "mix.exs",
        "projection.lock.json"
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "docs/development.md",
        "docs/layout.md",
        "docs/overview.md",
        "docs/runbooks/faults.md",
        "docs/runbooks/up_multi.md",
        "docs/runbooks/up_single.md"
      ]
    ]
  end
end
