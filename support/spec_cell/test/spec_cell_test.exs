defmodule StackLab.SpecCellTest do
  use ExUnit.Case, async: true

  alias StackLab.SpecCell

  test "creates a valid executable requirement cell" do
    assert {:ok, %SpecCell{} = cell} =
             SpecCell.new(
               requirement_id: "UAA-027",
               owner_repo: "stack_lab",
               source_docs: ["implementation_docset/38_additional_feature_phase_integration.md"],
               target_code_paths: ["support/spec_cell"],
               proof_command: "mix test",
               acceptance_fixture: "UAA-027",
               scanner_refs: ["spec_cell.audit"],
               closeout_state: :green,
               release_claim: "SpecCell gate blocks checklist-only closeout"
             )

    assert SpecCell.complete?(cell)
  end

  test "rejects checklist-only cells without evidence paths" do
    assert {:error, errors} =
             SpecCell.new(
               requirement_id: "UAA-027",
               owner_repo: "stack_lab",
               source_docs: [],
               target_code_paths: [],
               proof_command: "",
               acceptance_fixture: "UAA-027",
               scanner_refs: [],
               closeout_state: :green,
               release_claim: "SpecCell gate blocks checklist-only closeout"
             )

    assert :source_docs in errors
    assert :target_code_paths in errors
    assert :proof_command in errors
  end

  test "returns missing required keys as validation errors" do
    assert {:error, errors} = SpecCell.new(owner_repo: "stack_lab")

    assert :requirement_id in errors
    assert :source_docs in errors
    assert :target_code_paths in errors
  end

  test "keeps open defects out of complete release claims" do
    cell =
      SpecCell.new!(
        requirement_id: "UAA-027",
        owner_repo: "stack_lab",
        source_docs: ["implementation_docset/38_additional_feature_phase_integration.md"],
        target_code_paths: ["support/spec_cell"],
        proof_command: "mix test",
        acceptance_fixture: "UAA-027",
        scanner_refs: ["spec_cell.audit"],
        closeout_state: :open_defect,
        release_claim: "SpecCell gate blocks checklist-only closeout"
      )

    refute SpecCell.complete?(cell)
  end
end
