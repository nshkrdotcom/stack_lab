defmodule StackLab.GnTen.BatchRunnerTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.BatchRunner
  alias StackLab.GnTen.Manifest

  @date ~D[2026-04-28]

  test "aborts before receipt creation when a repo is dirty" do
    workspace = temp_workspace!()
    File.write!(Path.join(repo_path(workspace, "execution_plane"), "dirty.txt"), "dirty\n")

    assert {:error, result} =
             BatchRunner.run("dirty-abort",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date
             )

    assert result.code == "workspace_not_clean_main"
    assert Enum.any?(result.failures, &(&1.code == "dirty_worktree"))
    refute File.exists?(receipt_path(workspace, "dirty-abort", "json"))
  end

  test "aborts before receipt creation when a repo is off main" do
    workspace = temp_workspace!()
    git!(repo_path(workspace, "citadel"), ["checkout", "-b", "topic"])

    assert {:error, result} =
             BatchRunner.run("off-main-abort",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date
             )

    assert result.code == "workspace_not_clean_main"
    assert Enum.any?(result.failures, &(&1.code == "branch_mismatch"))
    refute File.exists?(receipt_path(workspace, "off-main-abort", "json"))
  end

  test "dry-run creates a receipt and records planned repo-local commands" do
    workspace = temp_workspace!()

    assert {:ok, result} =
             BatchRunner.run("dry-run-smoke",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date,
               dry_run?: true
             )

    receipt = read_receipt!(workspace, "dry-run-smoke")

    assert result.status == :dry_run
    assert receipt["run_status"] == "dry_run"
    assert length(receipt["commands"]) == 10
    assert Enum.all?(receipt["commands"], &(&1["status"] == "dry_run"))

    assert Enum.map(receipt["commands"], & &1["repo"]) == [
             "ground_plane",
             "execution_plane",
             "citadel",
             "jido_integration",
             "mezzanine",
             "outer_brain",
             "app_kit",
             "extravaganza",
             "AITrace",
             "stack_lab"
           ]
  end

  test "failed repo stops the run and records a resume point" do
    workspace = temp_workspace!()
    calls = Agent.start_link(fn -> [] end) |> elem(1)

    runner = fn repo, _command ->
      Agent.update(calls, &[repo.name | &1])

      if repo.name == "execution_plane" do
        {:error, 42, "VERY_SECRET_STDOUT"}
      else
        {:ok, 0, "ordinary output"}
      end
    end

    assert {:error, result} =
             BatchRunner.run("failed-run",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date,
               command_runner: runner
             )

    receipt = read_receipt!(workspace, "failed-run")
    trace = read_trace!(workspace, "failed-run")
    called = calls |> Agent.get(&Enum.reverse/1)

    assert result.code == "batch_repo_failed"
    assert called == ["ground_plane", "execution_plane"]
    assert receipt["run_status"] == "failed"
    assert receipt["resume"]["first_failed_repo"] == "execution_plane"
    assert String.contains?(receipt["resume"]["command"], "--resume --confirm")
    assert Enum.any?(trace["spans"], &(&1["repo_ref"] == "repo://nshkrdotcom/execution_plane"))
    refute String.contains?(Jason.encode!(trace), "VERY_SECRET_STDOUT")
  end

  test "successful run emits per-repo spans without raw command output" do
    workspace = temp_workspace!()

    runner = fn _repo, _command ->
      {:ok, 0, "RAW_STDOUT_THAT_MUST_NOT_LEAK"}
    end

    assert {:ok, result} =
             BatchRunner.run("successful-run",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date,
               command_runner: runner
             )

    trace = read_trace!(workspace, "successful-run")

    assert result.status == :ok
    assert length(trace["spans"]) == 10
    assert Enum.all?(trace["spans"], &Map.has_key?(&1, "repo_ref"))
    assert Enum.all?(trace["spans"], &Map.has_key?(&1, "status"))
    assert Enum.all?(trace["spans"], &Map.has_key?(&1, "evidence_ref"))
    refute String.contains?(Jason.encode!(trace), "RAW_STDOUT_THAT_MUST_NOT_LEAK")
  end

  test "fails if a non-stack_lab repo becomes dirty during the run" do
    workspace = temp_workspace!()

    runner = fn repo, _command ->
      if repo.name == "execution_plane" do
        File.write!(Path.join(repo.path, "generated.txt"), "unexpected\n")
      end

      {:ok, 0, "output"}
    end

    assert {:error, result} =
             BatchRunner.run("mutation-run",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date,
               command_runner: runner
             )

    assert result.code == "workspace_mutated"
    assert Enum.any?(result.failures, &(&1.repo == "execution_plane"))
  end

  test "allows repo-owned projection lock refreshes and records them" do
    workspace = temp_workspace!()

    citadel_lock =
      Path.join(repo_path(workspace, "citadel"), "dist/hex/citadel/projection.lock.json")

    File.mkdir_p!(Path.dirname(citadel_lock))
    File.write!(citadel_lock, ~s({"git_revision":"before"}\n))
    git!(repo_path(workspace, "citadel"), ["add", "dist/hex/citadel/projection.lock.json"])

    git!(repo_path(workspace, "citadel"), [
      "-c",
      "user.name=StackLab",
      "-c",
      "user.email=stack_lab@example.invalid",
      "commit",
      "-m",
      "add projection lock"
    ])

    runner = fn repo, _command ->
      if repo.name == "citadel" do
        File.write!(citadel_lock, ~s({"git_revision":"after"}\n))
      end

      {:ok, 0, "output"}
    end

    assert {:ok, result} =
             BatchRunner.run("projection-lock-run",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date,
               command_runner: runner
             )

    receipt = read_receipt!(workspace, "projection-lock-run")

    assert result.status == :ok

    assert [
             %{
               "repo" => "citadel",
               "path" => "dist/hex/citadel/projection.lock.json",
               "status" => "M"
             }
           ] = receipt["post_run_mutations"]
  end

  test "resume requires explicit confirmation" do
    workspace = temp_workspace!()

    assert {:error, result} =
             BatchRunner.run("resume-run",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date,
               resume?: true
             )

    assert result.code == "resume_requires_confirm"
  end

  test "confirmed resume starts from the first failed repo" do
    workspace = temp_workspace!()
    calls = Agent.start_link(fn -> [] end) |> elem(1)

    first_runner = fn repo, _command ->
      if repo.name == "citadel" do
        {:error, 1, "fail"}
      else
        {:ok, 0, "ok"}
      end
    end

    assert {:error, _result} =
             BatchRunner.run("resume-from-failed",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date,
               command_runner: first_runner
             )

    resume_runner = fn repo, _command ->
      Agent.update(calls, &[repo.name | &1])
      {:ok, 0, "ok"}
    end

    assert {:ok, result} =
             BatchRunner.run("resume-from-failed",
               manifest: workspace.manifest,
               out_dir: workspace.receipts,
               trace_dir: workspace.traces,
               date: @date,
               resume?: true,
               confirm?: true,
               command_runner: resume_runner
             )

    assert result.status == :ok

    assert calls |> Agent.get(&Enum.reverse/1) == [
             "citadel",
             "jido_integration",
             "mezzanine",
             "outer_brain",
             "app_kit",
             "extravaganza",
             "AITrace",
             "stack_lab"
           ]
  end

  defp temp_workspace! do
    root =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_gn_ten_batch_runner_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)

    repo_entries =
      Enum.map(Manifest.expected_repos(), fn repo ->
        path = Path.join(root, repo)
        temp_git_repo!(path)

        %{
          name: repo,
          repo_ref: "repo://nshkrdotcom/#{repo}",
          path: path,
          default_branch: "main",
          ci: "echo #{repo}"
        }
      end)

    %{
      root: root,
      receipts: Path.join(root, "receipts"),
      traces: Path.join(root, "traces"),
      manifest: %{
        schema_version: "gn_ten_manifest_v1",
        workspace_ref: "workspace://nshkrdotcom/gn-ten",
        branch_policy: "main_only",
        repos: Manifest.expected_repos(),
        repo_entries: repo_entries
      }
    }
  end

  defp temp_git_repo!(path) do
    File.mkdir_p!(path)
    git!(path, ["init", "-b", "main"])
    File.write!(Path.join(path, "README.md"), "# temp\n")
    git!(path, ["add", "README.md"])

    git!(path, [
      "-c",
      "user.name=StackLab",
      "-c",
      "user.email=stack_lab@example.invalid",
      "commit",
      "-m",
      "initial"
    ])
  end

  defp repo_path(workspace, repo), do: Path.join(workspace.root, repo)

  defp receipt_path(workspace, slug, extension) do
    Path.join(workspace.receipts, "20260428_#{slug}.#{extension}")
  end

  defp read_receipt!(workspace, slug) do
    workspace
    |> receipt_path(slug, "json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp read_trace!(workspace, slug) do
    workspace
    |> trace_path(slug)
    |> File.read!()
    |> Jason.decode!()
  end

  defp trace_path(workspace, slug) do
    Path.join(workspace.traces, "#{slug}.json")
  end

  defp git!(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed with #{status}: #{output}")
    end
  end
end
