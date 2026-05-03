defmodule StackLab.GnTen.BatchReceiptTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.GnTen.Batch.New
  alias StackLab.GnTen.BatchReceipt

  @date ~D[2026-04-28]

  test "task requires --name" do
    error =
      assert_raise Mix.Error, fn ->
        New.run([])
      end

    assert Exception.message(error) =~ "expected --name <slug>"
  end

  test "rejects unsafe slugs" do
    assert {:error, {:unsafe_slug, "Bad Slug"}} = BatchReceipt.new("Bad Slug")
  end

  test "creates markdown receipt with required sections" do
    out_dir = temp_dir!()

    assert {:ok, receipt} =
             BatchReceipt.new("phase-a-command-surface-smoke",
               date: @date,
               out_dir: out_dir,
               repo: "stack_lab"
             )

    assert receipt.md_path == Path.join(out_dir, "20260428_phase-a-command-surface-smoke.md")
    markdown = File.read!(receipt.md_path)

    assert markdown =~ "# gn-ten Batch Receipt: phase-a-command-surface-smoke"
    assert markdown =~ "Date: 2026-04-28"
    assert markdown =~ "Batch ID: 20260428-phase-a-command-surface-smoke"
    assert markdown =~ "Branch policy: main_only"
    assert markdown =~ "Primary owner repo: stack_lab"
    assert markdown =~ "Contract producer repo:"
    assert markdown =~ "Consumer repos:"
    assert markdown =~ "## Scope"
    assert markdown =~ "## Commands"
    assert markdown =~ "## Proof"
    assert markdown =~ "## Git Closeout"
    assert markdown =~ "## Notes"
  end

  test "creates json receipt with schema and main-only branch policy" do
    out_dir = temp_dir!()

    assert {:ok, receipt} =
             BatchReceipt.new("phase-a-command-surface-smoke",
               date: @date,
               out_dir: out_dir,
               repo: "stack_lab"
             )

    json = receipt.json_path |> File.read!() |> Jason.decode!()

    assert json["schema_version"] == "gn_ten_batch_receipt_v1"
    assert json["batch_id"] == "20260428-phase-a-command-surface-smoke"
    assert json["branch_policy"] == "main_only"
    assert json["primary_owner_repo"] == "stack_lab"
    assert json["contract_producer_repo"] == nil
    assert json["consumer_repos"] == []
    assert json["commands"] == []
    assert json["proof"]["does_not_prove"] == []
    assert json["git_closeout"] == []
  end

  defp temp_dir! do
    dir = Path.join(System.tmp_dir!(), "stack_lab_batch_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
