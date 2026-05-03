Code.require_file("workspace_contract.exs", __DIR__)

defmodule StackLab.Build.WeldContract do
  @moduledoc false

  @proof_projects [
    "support/spec_cell",
    "support/gn_ten_control_plane",
    "examples/single_node_roundtrip",
    "examples/outer_brain_restart_durability",
    "examples/multi_node_roundtrip",
    "examples/restart_authority_drill",
    "examples/governed_run_roundtrip",
    "examples/atom_cleanup_harness",
    "examples/env_remediation_harness",
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
    "docs/runbooks/faults.md",
    "docs/runbooks/extravaganza_non_ui_lane.md"
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
