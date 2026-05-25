unless Code.ensure_loaded?(DependencySources) do
  Code.require_file("build_support/dependency_sources.exs", __DIR__)
end

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
      {:blitz, "~> 0.3.0", runtime: false},
      {:weld, "~> 0.8.2", only: [:dev, :test], runtime: false},
      {:jason, "~> 1.4", runtime: false},
      {:stack_lab_lab_core, path: "support/lab_core"},
      {:stack_lab_gn_ten_node_lab, path: "support/gn_ten_node_lab"},
      DependencySources.dep(:ground_plane_contracts, __DIR__),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.1", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    monorepo_aliases = [
      "monorepo.deps.get": ["blitz.workspace.impact deps_get --"],
      "monorepo.format": ["blitz.workspace.impact format --"],
      "monorepo.compile": ["blitz.workspace.impact compile --"],
      "monorepo.test": ["blitz.workspace.impact test --"],
      "monorepo.credo": ["blitz.workspace.impact credo --"],
      "monorepo.docs": ["blitz.workspace.impact docs --"]
    ]

    [
      ci: [
        "deps.get",
        "monorepo.deps.get",
        "monorepo.format --check-formatted",
        "gn_ten.validate",
        "gn_ten.artifacts.validate",
        "gn_ten.proofs.validate",
        "gn_ten.repo_agents.validate",
        "gn_ten.refactoring_deletion.scenarios",
        "gn_ten.tenant.scan --all-repos",
        "gn_ten.tenant.scenarios",
        "gn_ten.restart_fencing.scenarios",
        "gn_ten.connector.scan --all-repos",
        "gn_ten.connector.scenarios",
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
        max_concurrency: nil,
        multiplier: 1,
        base: [
          deps_get: 4,
          format: 4,
          compile: 4,
          test: 3,
          credo: 2,
          docs: 4
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
        "docs/gn_ten_main_only.md",
        "guides/context_abi.md",
        "guides/router_fabric.md",
        "guides/stacklab_acceptance.md",
        "guides/generalized_stack.md",
        "guides/qc_and_operations.md",
        "guides/code_smell_remediation.md",
        "docs/gn_ten_proof_matrix.md",
        "docs/review/gn_ten_batch_review.md",
        "docs/review/shared_library_governed_adapter_review.md",
        "docs/runbooks/up_single.md",
        "docs/runbooks/up_multi.md",
        "docs/runbooks/faults.md",
        "docs/runbooks/tre_lane_acceptance.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Overview: ["README.md", "docs/overview.md"],
        Development: [
          "docs/development.md",
          "docs/layout.md",
          "docs/gn_ten_main_only.md",
          "guides/context_abi.md",
          "guides/router_fabric.md",
          "guides/stacklab_acceptance.md",
          "guides/generalized_stack.md",
          "guides/qc_and_operations.md",
          "guides/code_smell_remediation.md",
          "docs/gn_ten_proof_matrix.md",
          "docs/review/gn_ten_batch_review.md",
          "docs/review/shared_library_governed_adapter_review.md"
        ],
        Runbooks: [
          "docs/runbooks/up_single.md",
          "docs/runbooks/up_multi.md",
          "docs/runbooks/faults.md",
          "docs/runbooks/tre_lane_acceptance.md"
        ],
        Project: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end
end
