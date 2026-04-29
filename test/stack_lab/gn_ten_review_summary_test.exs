defmodule StackLab.GnTen.ReviewSummaryTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.GnTen.Review.Summary
  alias StackLab.GnTen.ReviewSummary

  @date "20260428"
  @slug "phase-l-review-smoke"

  test "summarizes a complete receipt and safe trace posture" do
    root = temp_dir!()
    receipt_dir = Path.join(root, "docs/receipts/gn_ten_batches")
    write_batch!(root, receipt_dir)

    assert {:ok, report} =
             ReviewSummary.summarize(@slug, root: root, receipt_dir: receipt_dir)

    assert report.batch_id == "#{@date}-#{@slug}"
    assert report.command_count == 1
    assert report.closeout_count == 1
    assert report.trace_count == 1
  end

  test "fails when receipt is missing a required field" do
    root = temp_dir!()
    receipt_dir = Path.join(root, "docs/receipts/gn_ten_batches")
    %{receipt_path: receipt_path} = write_batch!(root, receipt_dir)

    receipt =
      receipt_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.delete("git_closeout")

    File.write!(receipt_path, Jason.encode!(receipt, pretty: true))

    assert {:error, report} =
             ReviewSummary.summarize(@slug, root: root, receipt_dir: receipt_dir)

    assert Enum.any?(report.failures, &(&1.code == "review_missing_required_field"))
  end

  test "fails when trace posture claims production deployment proof" do
    root = temp_dir!()
    receipt_dir = Path.join(root, "docs/receipts/gn_ten_batches")
    %{trace_path: trace_path} = write_batch!(root, receipt_dir)

    trace =
      trace_path
      |> File.read!()
      |> Jason.decode!()
      |> put_in(["proof_posture", "production_deployment_proven?"], true)

    File.write!(trace_path, Jason.encode!(trace, pretty: true))

    assert {:error, report} =
             ReviewSummary.summarize(@slug, root: root, receipt_dir: receipt_dir)

    assert Enum.any?(report.failures, &(&1.code == "review_trace_bad_posture"))
  end

  test "mix task requires --batch" do
    assert_raise Mix.Error, ~r/expected --batch <slug>/, fn ->
      Summary.run([])
    end
  end

  defp write_batch!(root, receipt_dir) do
    File.mkdir_p!(receipt_dir)
    trace_path = Path.join(root, "tmp/gn_ten_traces/#{@slug}.json")
    receipt_path = Path.join(receipt_dir, "#{@date}_#{@slug}.json")
    File.mkdir_p!(Path.dirname(trace_path))

    File.write!(trace_path, Jason.encode!(trace(), pretty: true))
    File.write!(receipt_path, Jason.encode!(receipt(), pretty: true))

    %{receipt_path: receipt_path, trace_path: trace_path}
  end

  defp receipt do
    %{
      "schema_version" => "gn_ten_batch_receipt_v1",
      "batch_id" => "#{@date}-#{@slug}",
      "branch_policy" => "main_only",
      "primary_owner_repo" => "stack_lab",
      "contract_producer_repo" => nil,
      "consumer_repos" => [],
      "commands" => [
        %{
          "repo" => "stack_lab",
          "repo_ref" => "repo://nshkrdotcom/stack_lab",
          "command" => "mix ci",
          "status" => "ok",
          "exit_status" => 0,
          "evidence_ref" => "repo-local-ci-status"
        }
      ],
      "proof" => %{
        "scenario" => "phase-l review smoke",
        "does_not_prove" => [
          "production_deployment",
          "authoritative_audit_truth"
        ]
      },
      "trace_evidence" => ["tmp/gn_ten_traces/#{@slug}.json"],
      "git_closeout" => [
        %{
          "repo" => "stack_lab",
          "branch" => "main",
          "sha" => "9df8652d80c5a1713e63c247a7b0511dba3db1d0",
          "pushed" => true,
          "clean" => true
        }
      ]
    }
  end

  defp trace do
    %{
      "schema_version" => "gn_ten_batch_trace_v1",
      "batch_id" => "#{@date}-#{@slug}",
      "trace_id" => "trace://stack_lab/gn-ten-batch/#{@date}-#{@slug}",
      "proof_posture" => %{
        "authoritative_audit?" => false,
        "production_deployment_proven?" => false,
        "safe_action" => "use_as_batch_ci_evidence"
      },
      "spans" => []
    }
  end

  defp temp_dir! do
    dir = Path.join(System.tmp_dir!(), "stack_lab_review_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
