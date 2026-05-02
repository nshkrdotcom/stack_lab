defmodule StackLab.GnTenControlPlaneTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTenControlPlane
  alias StackLab.SpecCell

  test "accepts bounded receipt states" do
    assert GnTenControlPlane.states() == [
             "passed",
             "failed",
             "skipped",
             "missing",
             "not_applicable"
           ]
  end

  test "creates a valid passed receipt" do
    assert {:ok, receipt} =
             GnTenControlPlane.new(
               receipt_id: "gn-ten:UAA-028:phase-1",
               requirement_id: "UAA-028",
               owner_repo: "stack_lab",
               state: "passed",
               proof_command: "mix test",
               receipt_path: "docs/receipts/gn_ten/uaa_028.json",
               spec_cell: spec_cell(:green)
             )

    refute GnTenControlPlane.release_blocking?(receipt)
  end

  test "marks failed and missing receipts as release blocking" do
    for state <- ["failed", "missing"] do
      assert {:ok, receipt} =
               GnTenControlPlane.new(
                 receipt_id: "gn-ten:UAA-028:#{state}",
                 requirement_id: "UAA-028",
                 owner_repo: "stack_lab",
                 state: state,
                 proof_command: "mix test",
                 receipt_path: "docs/receipts/gn_ten/uaa_028.json",
                 spec_cell: spec_cell(:open_defect)
               )

      assert GnTenControlPlane.release_blocking?(receipt)
    end
  end

  test "rejects unknown receipt states without creating atoms" do
    assert {:error, [:state]} =
             GnTenControlPlane.new(
               receipt_id: "gn-ten:UAA-028:bad",
               requirement_id: "UAA-028",
               owner_repo: "stack_lab",
               state: "complete",
               proof_command: "mix test",
               receipt_path: "docs/receipts/gn_ten/uaa_028.json",
               spec_cell: spec_cell(:green)
             )
  end

  test "returns missing receipt keys as validation errors" do
    assert {:error, errors} = GnTenControlPlane.new(owner_repo: "stack_lab")

    assert :receipt_id in errors
    assert :state in errors
    assert :spec_cell in errors
  end

  test "raises from bang constructor with validation errors" do
    assert_raise ArgumentError, fn ->
      GnTenControlPlane.new!(owner_repo: "stack_lab")
    end
  end

  defp spec_cell(closeout_state) do
    SpecCell.new!(
      requirement_id: "UAA-028",
      owner_repo: "stack_lab",
      source_docs: ["implementation_docset/38_additional_feature_phase_integration.md"],
      target_code_paths: ["support/gn_ten_control_plane"],
      proof_command: "mix test",
      acceptance_fixture: "UAA-028",
      scanner_refs: ["gn_ten.receipt"],
      closeout_state: closeout_state,
      release_claim: "gn-ten receipts gate every ADDL phase"
    )
  end
end
