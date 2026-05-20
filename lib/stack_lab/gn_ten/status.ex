defmodule StackLab.GnTen.Status do
  @moduledoc """
  Read-only status checks for the main-only `gn-ten` workspace.

  The status check never creates, checks out, resets, rebases, or deletes
  branches. It reports whether each local repo matches the manifest's `main`
  branch contract and whether there are uncommitted changes.
  """

  alias StackLab.CommandRunner
  alias StackLab.GnTen.Manifest

  @schema_version "gn_ten_status_v1"

  @type repo_status :: %{
          name: String.t(),
          repo_ref: String.t(),
          path: String.t(),
          expected_branch: String.t(),
          actual_branch: String.t() | nil,
          head_sha: String.t() | nil,
          dirty?: boolean(),
          ahead: non_neg_integer() | nil,
          behind: non_neg_integer() | nil,
          failures: [map()]
        }

  @type result :: %{
          schema_version: String.t(),
          workspace_ref: String.t(),
          branch_policy: String.t(),
          clean?: boolean(),
          repos: [repo_status()],
          failures: [map()]
        }

  @spec check(String.t()) :: {:ok, result()} | {:error, result() | [term()]}
  def check(manifest_path \\ Manifest.default_path()) do
    case Manifest.validate_file(manifest_path) do
      {:ok, manifest} ->
        repos = Enum.map(manifest.repo_entries, &repo_status/1)
        failures = Enum.flat_map(repos, & &1.failures)
        result = result(manifest, repos, failures)

        if failures == [] do
          {:ok, result}
        else
          {:error, result}
        end

      {:error, failures} ->
        {:error, failures}
    end
  end

  @doc false
  @spec repo_status(map()) :: repo_status()
  def repo_status(entry) do
    branch = git(entry.path, ["branch", "--show-current"])
    head_sha = git(entry.path, ["rev-parse", "HEAD"])
    dirty? = dirty?(entry.path)
    {ahead, behind} = ahead_behind(entry.path, entry.default_branch)

    failures =
      []
      |> require_path(entry)
      |> require_branch(entry, branch)
      |> require_head(entry, head_sha)
      |> require_clean(entry, dirty?)

    %{
      name: entry.name,
      repo_ref: entry.repo_ref,
      path: entry.path,
      expected_branch: entry.default_branch,
      actual_branch: branch,
      head_sha: head_sha,
      dirty?: dirty?,
      ahead: ahead,
      behind: behind,
      failures: Enum.reverse(failures)
    }
  end

  defp result(manifest, repos, failures) do
    %{
      schema_version: @schema_version,
      workspace_ref: manifest.workspace_ref,
      branch_policy: manifest.branch_policy,
      clean?: failures == [],
      repos: repos,
      failures: failures
    }
  end

  defp require_path(failures, entry) do
    if File.dir?(entry.path) do
      failures
    else
      [failure(entry, "missing_repo_path", expected: "directory", actual: nil) | failures]
    end
  end

  defp require_branch(failures, entry, branch) do
    if branch == entry.default_branch do
      failures
    else
      [
        failure(entry, "branch_mismatch", expected: entry.default_branch, actual: branch)
        | failures
      ]
    end
  end

  defp require_head(failures, entry, head_sha) do
    if present?(head_sha) do
      failures
    else
      [failure(entry, "missing_head_sha", expected: "git_head", actual: nil) | failures]
    end
  end

  defp require_clean(failures, _entry, false), do: failures

  defp require_clean(failures, entry, true) do
    [failure(entry, "dirty_worktree", expected: "clean", actual: "dirty") | failures]
  end

  defp failure(entry, code, fields) do
    fields
    |> Map.new()
    |> Map.merge(%{
      code: code,
      repo: entry.name,
      path: entry.path
    })
  end

  defp dirty?(path) do
    case git(path, ["status", "--short", "--untracked-files=all"]) do
      nil -> false
      "" -> false
      _status -> true
    end
  end

  defp ahead_behind(path, branch) do
    with remote_ref when is_binary(remote_ref) <-
           git(path, ["rev-parse", "--abbrev-ref", "#{branch}@{upstream}"]),
         counts when is_binary(counts) <-
           git(path, ["rev-list", "--left-right", "--count", "#{branch}...#{remote_ref}"]),
         [ahead, behind] <- String.split(counts),
         {ahead_int, ""} <- Integer.parse(ahead),
         {behind_int, ""} <- Integer.parse(behind) do
      {ahead_int, behind_int}
    else
      _ -> {nil, nil}
    end
  end

  defp git(path, args) do
    if File.dir?(path) do
      case CommandRunner.system_cmd("git", args, cd: path, stderr_to_stdout: true) do
        {output, 0} -> String.trim(output)
        {_output, _status} -> nil
      end
    end
  end

  defp present?(value), do: is_binary(value) and value != ""
end
