Code.require_file("build_support/workspace_contract.exs", __DIR__)

defmodule StackLab.Workspace.MixProject do
  use Mix.Project

  alias StackLab.Build.WorkspaceContract

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/stack_lab"

  def project do
    [
      app: :stack_lab_workspace,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      blitz_workspace: blitz_workspace(),
      dialyzer: dialyzer(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @source_url,
      name: "StackLab Workspace",
      description: "Tooling root for the StackLab non-umbrella monorepo"
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
        "monorepo.test": :test,
        "monorepo.credo": :test,
        "monorepo.docs": :dev
      ]
    ]
  end

  defp deps do
    [
      {:blitz, "~> 0.2.0", runtime: false},
      {:weld, "~> 0.7.0", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    monorepo_aliases = [
      "monorepo.deps.get": ["blitz.workspace deps_get"],
      "monorepo.format": ["blitz.workspace format"],
      "monorepo.compile": ["blitz.workspace compile"],
      "monorepo.test": ["blitz.workspace test"],
      "monorepo.credo": ["blitz.workspace credo"],
      "monorepo.docs": ["blitz.workspace docs"]
    ]

    [
      "weld.inspect": ["weld.inspect build_support/weld.exs --artifact stack_lab_support"],
      "weld.graph": ["weld.graph build_support/weld.exs --artifact stack_lab_support"],
      "weld.project": ["weld.project build_support/weld.exs --artifact stack_lab_support"],
      "weld.verify": ["weld.verify build_support/weld.exs --artifact stack_lab_support"],
      "weld.release.prepare": [
        "weld.release.prepare build_support/weld.exs --artifact stack_lab_support"
      ],
      "weld.release.track": [
        "weld.release.track build_support/weld.exs --artifact stack_lab_support"
      ],
      "weld.release.archive": [
        "weld.release.archive build_support/weld.exs --artifact stack_lab_support"
      ],
      "release.prepare": ["weld.release.prepare"],
      "release.track": ["weld.release.track"],
      "release.archive": ["weld.release.archive"],
      ci: [
        "deps.get",
        "monorepo.deps.get",
        "monorepo.format --check-formatted",
        "monorepo.compile",
        "monorepo.test",
        "monorepo.credo --strict",
        "monorepo.docs",
        "weld.verify"
      ],
      "docs.root": ["docs"]
    ] ++ monorepo_aliases
  end

  defp dialyzer do
    [
      plt_add_deps: :apps_direct,
      plt_add_apps: [:mix, :blitz, :weld]
    ]
  end

  defp blitz_workspace do
    [
      root: __DIR__,
      projects: WorkspaceContract.active_project_globs(),
      isolation: [
        deps_path: true,
        build_path: true,
        lockfile: true,
        hex_home: "_build/hex"
      ],
      parallelism: [
        env: "STACK_LAB_MONOREPO_MAX_CONCURRENCY",
        multiplier: :auto,
        base: [
          deps_get: 3,
          format: 4,
          compile: 2,
          test: 2,
          credo: 2,
          docs: 1
        ],
        overrides: []
      ],
      tasks: [
        deps_get: [args: ["deps.get"], preflight?: false],
        format: [args: ["format"]],
        compile: [args: ["compile", "--warnings-as-errors"]],
        test: [args: ["test"], mix_env: "test", color: true],
        credo: [args: ["credo"]],
        docs: [args: ["docs"]]
      ]
    ]
  end

  defp docs do
    [
      main: "workspace_readme",
      name: "StackLab Workspace",
      logo: "assets/stack_lab.svg",
      assets: %{"assets" => "assets"},
      source_ref: "main",
      source_url: @source_url,
      homepage_url: @source_url,
      extras: [
        {"README.md", filename: "workspace_readme"},
        "docs/overview.md",
        "docs/development.md",
        "docs/layout.md",
        "docs/runbooks/up_single.md",
        "docs/runbooks/up_multi.md",
        "docs/runbooks/faults.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Overview: ["README.md", "docs/overview.md"],
        Development: ["docs/development.md", "docs/layout.md"],
        Runbooks: [
          "docs/runbooks/up_single.md",
          "docs/runbooks/up_multi.md",
          "docs/runbooks/faults.md"
        ],
        Project: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end
end
