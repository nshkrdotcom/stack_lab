defmodule StackLab.GnTen.RepoAgentInstructionsTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.RepoAgentInstructions

  @draft """
  # sample Agent Instructions Draft

  ## Owns

  - A bounded contract.
  """

  test "reports missing repo-agent section" do
    %{drafts: drafts, repo_root: repo_root} = fixture!()
    write_draft!(drafts, "sample", @draft)
    File.write!(Path.join(repo_root, "AGENTS.md"), "# Existing instructions\n")

    assert {:error, report} =
             RepoAgentInstructions.validate_entries([repo("sample", repo_root)],
               drafts_root: drafts
             )

    assert failure_code?(report, "repo_agent_missing_section")
  end

  test "reports drifted repo-agent section" do
    %{drafts: drafts, repo_root: repo_root} = fixture!()
    write_draft!(drafts, "sample", @draft)

    write_agents!(
      repo_root,
      "sample",
      """
      # sample Agent Instructions Draft

      ## Owns

      - A changed contract.
      """
    )

    assert {:error, report} =
             RepoAgentInstructions.validate_entries([repo("sample", repo_root)],
               drafts_root: drafts
             )

    assert failure_code?(report, "repo_agent_drift")
  end

  test "reports wrong repo marker" do
    %{drafts: drafts, repo_root: repo_root} = fixture!()
    write_draft!(drafts, "sample", @draft)
    write_agents!(repo_root, "other_repo", @draft)

    assert {:error, report} =
             RepoAgentInstructions.validate_entries([repo("sample", repo_root)],
               drafts_root: drafts
             )

    assert failure_code?(report, "repo_agent_wrong_repo_marker")
  end

  test "validates a clean repo-agent section" do
    %{drafts: drafts, repo_root: repo_root} = fixture!()
    write_draft!(drafts, "sample", @draft)
    write_agents!(repo_root, "sample", @draft)

    assert {:ok, report} =
             RepoAgentInstructions.validate_entries([repo("sample", repo_root)],
               drafts_root: drafts
             )

    assert report.repo_count == 1
    assert report.failure_count == 0
  end

  defp failure_code?(report, code) do
    Enum.any?(report.failures, &(&1.code == code))
  end

  defp fixture! do
    root =
      Path.join(System.tmp_dir!(), "stack_lab_repo_agents_#{System.unique_integer([:positive])}")

    File.rm_rf!(root)
    drafts = Path.join(root, "drafts")
    repo_root = Path.join(root, "repo")
    File.mkdir_p!(drafts)
    File.mkdir_p!(repo_root)
    %{drafts: drafts, repo_root: repo_root}
  end

  defp repo(name, path), do: %{name: name, path: path}

  defp write_draft!(drafts, repo, body) do
    File.write!(Path.join(drafts, "#{repo}.md"), body)
  end

  defp write_agents!(repo_root, marker_repo, body) do
    File.write!(
      Path.join(repo_root, "AGENTS.md"),
      """
      # Existing instructions

      <!-- gn-ten:repo-agent:start repo=#{marker_repo} source_sha=abc123 -->
      #{String.trim(body)}
      <!-- gn-ten:repo-agent:end -->
      """
    )
  end
end
