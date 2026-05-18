defmodule StackLab.GnTen.RefactoringDeletionBacklogTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTen.RefactoringDeletionBacklog

  test "refactoring deletion backlog report validates" do
    report = RefactoringDeletionBacklog.report()

    assert :ok = RefactoringDeletionBacklog.validate_report(report)
    assert report.schema_version == "gn_ten_refactoring_deletion_backlog_v1"
    assert report.proof_id == "refactoring_deletion_backlog"
    assert report.profile == "local_quick"
    assert report.inventory.active_delete_candidates == []
    assert length(report.deletion_campaigns) == 4
    assert length(report.retention_receipts) == 4
  end

  test "inventory covers the ten target repos" do
    report = RefactoringDeletionBacklog.report()

    assert report.target_repos == [
             "app_kit",
             "extravaganza",
             "mezzanine",
             "outer_brain",
             "citadel",
             "jido_integration",
             "execution_plane",
             "ground_plane",
             "stack_lab",
             "AITrace"
           ]

    assert Enum.map(report.inventory.repo_file_counts, & &1.repo) == report.target_repos
  end

  test "deletion campaigns link to batch receipts and evidence refs" do
    report = RefactoringDeletionBacklog.report()

    assert Enum.all?(report.deletion_campaigns, fn campaign ->
             is_binary(campaign.id) and
               campaign.batch_receipt ==
                 "docs/receipts/gn_ten_batches/20260518_refactoring-deletion-backlog.json" and
               campaign.evidence_refs != []
           end)
  end

  test "retained duplicates include owner, reason, review date, and scanner posture" do
    report = RefactoringDeletionBacklog.report()

    assert Enum.all?(report.retention_receipts, fn receipt ->
             is_binary(receipt.owner_repo) and is_binary(receipt.reason) and
               receipt.review_date == "2026-06-18" and is_binary(receipt.scanner_posture)
           end)
  end

  test "validator rejects active delete candidates" do
    report =
      RefactoringDeletionBacklog.report()
      |> put_in([:inventory, :active_delete_candidates], ["unreviewed_duplicate"])

    assert {:error, failures} = RefactoringDeletionBacklog.validate_report(report)
    assert failure_code?(failures, "refactor_active_candidates_not_empty")
  end

  test "validator rejects missing retention review date" do
    report =
      RefactoringDeletionBacklog.report()
      |> put_in([:retention_receipts, Access.at(0), :review_date], nil)

    assert {:error, failures} = RefactoringDeletionBacklog.validate_report(report)
    assert failure_code?(failures, "refactor_retention_missing_review_date")
  end

  test "validator rejects generic duplicate dispatch retention" do
    report =
      RefactoringDeletionBacklog.report()
      |> put_in([:scanner_posture, :retained_generic_duplicate_dispatch_allowed?], true)

    assert {:error, failures} = RefactoringDeletionBacklog.validate_report(report)
    assert failure_code?(failures, "refactor_generic_duplicates_allowed")
  end

  defp failure_code?(failures, code) do
    Enum.any?(failures, &(&1.code == code))
  end
end
