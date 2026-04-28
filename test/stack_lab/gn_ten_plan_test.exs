defmodule StackLab.GnTen.PlanTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.Plan

  test "unknown repo returns a controlled error" do
    assert {:error, {:unknown_repo, "missing_repo"}} = Plan.for_repo("missing_repo")
  end

  test "execution_plane plan includes the bounded repo-local starting point" do
    assert {:ok, text} = Plan.for_repo("execution_plane")

    assert text =~ "repo: execution_plane"
    assert text =~ "layer: execution_substrate"
    assert text =~ "role: lower_runtime_packets_and_lanes"
    assert text =~ "path: /home/home/p/g/n/execution_plane"
    assert text =~ "default_branch: main"
    assert text =~ "ci: mix ci"
    assert text =~ "produces:"
    assert text =~ "  - execution_plane"
    assert text =~ "consumes:"
    assert text =~ "  - ground_plane_contracts"
    assert text =~ "proof_owner: stack_lab"
    assert text =~ "proof_matrix: docs/gn_ten_proof_matrix.md"

    assert text =~
             "repo_agent_draft: /home/home/p/g/j/jido_brainstorm/nshkrdotcom/docs/20260428/gn-ten_cleanup/repo_agent_instructions/execution_plane.md"

    assert text =~ "next:"
    assert text =~ "  - confirm repo is on main and clean"
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
