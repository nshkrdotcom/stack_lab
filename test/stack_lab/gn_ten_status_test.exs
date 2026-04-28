defmodule StackLab.GnTen.StatusTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.Status

  test "repo_status accepts a clean repo on main" do
    repo_path = temp_git_repo!()

    status = Status.repo_status(entry(repo_path, "main"))

    assert status.actual_branch == "main"
    assert status.dirty? == false
    assert is_binary(status.head_sha)
    assert status.failures == []
  end

  test "repo_status reports branch mismatch and dirty worktree" do
    repo_path = temp_git_repo!()
    File.write!(Path.join(repo_path, "dirty.txt"), "dirty\n")

    status = Status.repo_status(entry(repo_path, "trunk"))
    codes = Enum.map(status.failures, & &1.code)

    assert "branch_mismatch" in codes
    assert "dirty_worktree" in codes
  end

  test "repo_status reports a missing repo path" do
    repo_path =
      Path.join(System.tmp_dir!(), "missing_gn_ten_repo_#{System.unique_integer([:positive])}")

    status = Status.repo_status(entry(repo_path, "main"))
    codes = Enum.map(status.failures, & &1.code)

    assert "missing_repo_path" in codes
    assert "branch_mismatch" in codes
    assert "missing_head_sha" in codes
  end

  defp entry(path, default_branch) do
    %{
      name: "example",
      repo_ref: "repo://nshkrdotcom/example",
      path: path,
      default_branch: default_branch,
      ci: "mix ci"
    }
  end

  defp temp_git_repo! do
    root =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_gn_ten_status_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)

    git!(root, ["init", "-b", "main"])
    File.write!(Path.join(root, "README.md"), "# temp\n")
    git!(root, ["add", "README.md"])

    git!(root, [
      "-c",
      "user.name=StackLab",
      "-c",
      "user.email=stack_lab@example.invalid",
      "commit",
      "-m",
      "initial"
    ])

    root
  end

  defp git!(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed with #{status}: #{output}")
    end
  end
end
