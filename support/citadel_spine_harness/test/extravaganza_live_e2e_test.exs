defmodule StackLab.CitadelSpineHarness.ExtravaganzaLiveE2ETest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness.ExtravaganzaLiveE2E

  test "typed live spec defaults to the approved GitHub write target and rejects static selectors" do
    assert {:ok, spec} =
             ExtravaganzaLiveE2E.parse_args([
               "--linear-api-key-stdin",
               "--run-label",
               "m12-test"
             ])

    assert spec.linear_api_key_source == :stdin
    assert spec.github_repo == "nshkrdotcom/test"
    assert spec.run_label == "m12-test"
    assert spec.temporal_mode == :up

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
               ExtravaganzaLiveE2E.parse_args(["--linear-api-key-stdin", flag, "static"])
    end
  end

  test "dry run plan carries dynamic provider identity lifecycle without running live commands" do
    assert {:ok, spec} =
             ExtravaganzaLiveE2E.parse_args([
               "--linear-api-key-file",
               "/operator/linear-token",
               "--github-repo",
               "nshkrdotcom/test",
               "--codex-cwd",
               "/tmp/codex-proof"
             ])

    plan = ExtravaganzaLiveE2E.plan(spec)

    assert plan.steps == [
             :internal_appkit_projection,
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
    command_runner = fn _command, _args, opts ->
      assert Keyword.has_key?(opts, :cd)
      {:ok, "proof ok"}
    end

    secret_reader = fn :stdin -> {:ok, "linear-secret"} end

    receipt_writer = fn path, receipt ->
      send(self(), {:receipt_written, path, receipt})
      {:ok, path}
    end

    assert {:ok, receipt} =
             ExtravaganzaLiveE2E.run(
               [
                 "--linear-api-key-stdin",
                 "--run-label",
                 "m12-test",
                 "--receipt-file",
                 "/tmp/m12-receipt.json"
               ],
               command_runner: command_runner,
               secret_reader: secret_reader,
               receipt_writer: receipt_writer
             )

    assert receipt.run_label == "m12-test"
    assert receipt.github.repo == "nshkrdotcom/test"
    assert receipt.linear.terminal_comment_preserved? == true
    assert receipt.temporal.mode == :up
    assert receipt.internal_projection.case == :deterministic_full_lane
    assert receipt.status == :passed

    assert_receive {:receipt_written, "/tmp/m12-receipt.json", ^receipt}
  end
end
