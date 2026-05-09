defmodule StackLab.CitadelSpineHarness.ProviderSmokeCheckTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness.ProviderSmokeCheck

  test "typed smoke spec defaults to the approved GitHub write target and rejects static selectors" do
    assert {:ok, spec} =
             ProviderSmokeCheck.parse_args([
               "--linear-api-key-stdin",
               "--run-label",
               "m12-test"
             ])

    assert spec.linear_api_key_source == :stdin
    assert spec.github_repo == "nshkrdotcom/test"
    assert spec.run_label == "m12-test"
    assert spec.temporal_mode == :check

    refute Map.has_key?(spec, :github_issue_number)
    refute Map.has_key?(spec, :github_pr_number)
    refute Map.has_key?(spec, :linear_issue_id)
    refute Map.has_key?(spec, :codex_session_id)

    for flag <- [
          "--github-issue-number",
          "--github-pr-number",
          "--linear-issue-id",
          "--linear-comment-id",
          "--codex-session-id",
          "--temporal-workflow-id"
        ] do
      assert {:error, {:static_provider_selector, ^flag}} =
               ProviderSmokeCheck.parse_args(["--linear-api-key-stdin", flag, "static"])
    end

    assert {:error, {:invalid_temporal_mode, "up"}} =
             ProviderSmokeCheck.parse_args([
               "--linear-api-key-stdin",
               "--temporal-mode",
               "up"
             ])
  end

  test "dry run plan carries dynamic provider identity lifecycle without running commands" do
    assert {:ok, spec} =
             ProviderSmokeCheck.parse_args([
               "--linear-api-key-file",
               "/operator/linear-token",
               "--github-repo",
               "nshkrdotcom/test",
               "--codex-cwd",
               "/tmp/codex-proof"
             ])

    plan = ProviderSmokeCheck.plan(spec)

    assert plan.steps == [
             :temporal_status,
             :linear_terminal_publication,
             :github_disposable_pr,
             :codex_session_turn,
             :receipt_write
           ]

    assert plan.identity_lifecycle.linear ==
             :discover_issue_create_update_terminal_comment_from_provider_outputs

    assert plan.identity_lifecycle.github ==
             :fetch_repo_create_branch_commit_pr_review_close_delete_from_provider_outputs

    assert plan.identity_lifecycle.codex == :session_turn_runtime_refs_from_lower_receipts
    assert plan.static_provider_selector_acceptance? == false
  end

  test "run writes a receipt from command outputs using injectable command runner" do
    command_runner = fn command, args, opts ->
      assert Keyword.has_key?(opts, :cd)

      if command == "just" do
        assert args == ["dev-status"]
      end

      {:ok, "proof ok"}
    end

    secret_reader = fn :stdin -> {:ok, "linear-secret"} end

    receipt_writer = fn path, receipt ->
      send(self(), {:receipt_written, path, receipt})
      {:ok, path}
    end

    progress = fn subject, event ->
      send(self(), {:progress, progress_subject(subject), event})
      :ok
    end

    assert {:ok, receipt} =
             ProviderSmokeCheck.run(
               [
                 "--linear-api-key-stdin",
                 "--run-label",
                 "m12-test",
                 "--receipt-file",
                 "/tmp/m12-receipt.json"
               ],
               command_runner: command_runner,
               secret_reader: secret_reader,
               receipt_writer: receipt_writer,
               progress: progress
             )

    assert receipt.run_label == "m12-test"
    assert receipt.github.repo == "nshkrdotcom/test"
    assert receipt.linear.terminal_comment_preserved? == true
    assert receipt.temporal.mode == :check
    assert receipt.schema_name == "provider_smoke_receipt_v1.json"
    assert receipt.proof_class == "provider_smoke_only"
    assert receipt.status == :smoke_test_only
    assert receipt.provider_smoke_result == :passed
    assert receipt.command == "mix stack_lab.provider_smoke_check"
    assert receipt.provider_smoke_steps == receipt.plan.steps
    assert "authority decision" in receipt.not_proven
    assert "product readback path" in receipt.not_proven

    assert_receive {:receipt_written, "/tmp/m12-receipt.json", ^receipt}
    assert_receive {:progress, :run, :started}
    assert_receive {:progress, :temporal, :started}
    assert_receive {:progress, :temporal, :passed}
    assert_receive {:progress, :linear, :started}
    assert_receive {:progress, :linear, :passed}
    assert_receive {:progress, :github, :started}
    assert_receive {:progress, :github, :passed}
    assert_receive {:progress, :codex, :started}
    assert_receive {:progress, :codex, :passed}
    assert_receive {:progress, :run, :receipt_written}
  end

  defp progress_subject(%{run_label: _run_label}), do: :run
  defp progress_subject(subject), do: subject
end
