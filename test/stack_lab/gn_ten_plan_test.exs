defmodule StackLab.GnTen.PlanTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.Plan

  test "unknown repo returns a controlled error" do
    assert {:error, {:unknown_repo, "missing_repo"}} = Plan.for_repo("missing_repo")
  end

  test "execution_plane plan includes the bounded repo-local starting point" do
    assert {:ok, text} = Plan.for_repo("execution_plane")

    assert String.contains?(text, "repo: execution_plane")
    assert String.contains?(text, "layer: execution_substrate")
    assert String.contains?(text, "role: lower_runtime_packets_and_lanes")
    assert String.contains?(text, "path: /home/home/p/g/n/execution_plane")
    assert String.contains?(text, "default_branch: main")
    assert String.contains?(text, "ci: mix ci")
    assert String.contains?(text, "produces:")
    assert String.contains?(text, "  - execution_plane")
    assert String.contains?(text, "consumes:")
    assert String.contains?(text, "  - ground_plane_contracts")
    assert String.contains?(text, "proof_owner: stack_lab")
    assert String.contains?(text, "proof_matrix: docs/gn_ten_proof_matrix.md")

    assert String.contains?(
             text,
             "repo_agent_draft: /home/home/p/g/j/jido_brainstorm/nshkrdotcom/docs/20260428/gn-ten_cleanup/repo_agent_instructions/execution_plane.md"
           )

    assert String.contains?(text, "next:")
    assert String.contains?(text, "  - confirm repo is on main and clean")
  end

  test "json output is agent-readable and omits raw manifest text" do
    assert {:ok, plan} = Plan.for_repo("execution_plane", json?: true)

    assert plan.repo == "execution_plane"
    assert plan.layer == "execution_substrate"
    assert plan.role == "lower_runtime_packets_and_lanes"
    assert plan.produces == ["execution_plane"]
    assert plan.consumes == ["ground_plane_contracts"]
    refute Map.has_key?(plan, :content)
    refute Map.has_key?(plan, :raw_yaml)
    refute Map.has_key?(plan, :manifest_text)
  end
end
