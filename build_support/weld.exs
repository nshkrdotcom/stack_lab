Code.require_file("workspace_contract.exs", __DIR__)

defmodule StackLab.Build.WeldContract do
  @moduledoc false

  @proof_projects [
    "examples/single_node_roundtrip",
    "examples/multi_node_roundtrip",
    "examples/restart_authority_drill",
    "examples/governed_run_roundtrip",
    "examples/session_lineage_drill",
    "examples/pressure_failover_drill"
  ]

  @artifact_docs [
    "README.md",
    "docs/overview.md",
    "docs/development.md",
    "docs/layout.md",
    "docs/runbooks/up_single.md",
    "docs/runbooks/up_multi.md",
    "docs/runbooks/faults.md"
  ]

  def manifest do
    [
      workspace: [
        root: "..",
        project_globs: StackLab.Build.WorkspaceContract.active_project_globs()
      ],
      classify: [
        tooling: ["."],
        proofs: @proof_projects
      ],
      publication: [
        internal_only: ["."] ++ @proof_projects
      ],
      artifacts: [
        stack_lab_support: artifact()
      ]
    ]
  end

  def artifact do
    [
      roots: ["support/lab_core"],
      package: [
        name: "stack_lab_lab_core",
        otp_app: :stack_lab_lab_core,
        version: "0.1.0",
        description: "Support package projected from the StackLab workspace"
      ],
      output: [
        docs: @artifact_docs,
        assets: ["CHANGELOG.md", "LICENSE"]
      ],
      verify: [
        artifact_tests: ["packaging/weld/stack_lab_support/test"],
        hex_build: false,
        hex_publish: false
      ]
    ]
  end
end

StackLab.Build.WeldContract.manifest()
