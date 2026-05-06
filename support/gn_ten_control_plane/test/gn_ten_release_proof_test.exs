defmodule StackLab.GnTenReleaseProofTest do
  use ExUnit.Case, async: true

  alias StackLab.GnTenControlPlane
  alias StackLab.GnTenReleaseProof
  alias StackLab.SpecCell

  @aoc_fixture_ids Enum.map(1..48, &("AOC-" <> String.pad_leading(Integer.to_string(&1), 3, "0")))
  @persist_fixture_ids Enum.map(
                         1..8,
                         &("PERSIST-AOC-" <>
                             String.pad_leading(Integer.to_string(&1), 3, "0"))
                       )
  @required_fixture_ids @aoc_fixture_ids ++ @persist_fixture_ids

  test "keeps inherited open defects out of complete release claims" do
    receipts = Enum.map(@required_fixture_ids, &receipt/1)

    assert {:ok, proof} =
             GnTenReleaseProof.build(
               release_id: "adaptive-release-20260505",
               release_name: "Nshkr adaptive optimization coordination",
               required_fixture_ids: @required_fixture_ids,
               claims: [
                 %{
                   claim_id: "claim://adaptive/full-release-proof",
                   fixture_ids: @required_fixture_ids,
                   spec_cell_refs: ["spec-cell://adaptive/aoc-001-048"],
                   scanner_refs: ["scanner://stack-lab/adaptive-release-proof"],
                   docs_refs: ["implementation_docset/release/phase_16_release_20260505.md"],
                   qc_refs: ["qc://stack-lab/mix-ci"],
                   receipt_refs: Enum.map(receipts, & &1.receipt_path),
                   status: "mapped"
                 }
               ],
               receipts: receipts,
               open_defects: ["open_defect_missing_remote_gepa_framework"]
             )

    assert proof.status == "open_defect"
    refute proof.complete?
    assert proof.missing_fixture_ids == []
    assert proof.covered_fixture_ids == @required_fixture_ids
  end

  test "rejects public release claims without executable evidence refs" do
    assert {:error, errors} =
             GnTenReleaseProof.build(
               release_id: "adaptive-release-20260505",
               release_name: "Nshkr adaptive optimization coordination",
               required_fixture_ids: ["AOC-048"],
               claims: [
                 %{
                   claim_id: "claim://adaptive/unsupported",
                   fixture_ids: ["AOC-048"],
                   spec_cell_refs: [],
                   scanner_refs: [],
                   docs_refs: [],
                   qc_refs: [],
                   receipt_refs: [],
                   status: "mapped"
                 }
               ],
               receipts: [],
               open_defects: []
             )

    assert :claim_spec_cell_refs in errors
    assert :claim_scanner_refs in errors
    assert :claim_docs_refs in errors
    assert :claim_qc_refs in errors
    assert :claim_receipt_refs in errors
    assert :missing_fixture_ids in errors
  end

  defp receipt(fixture_id) do
    GnTenControlPlane.new!(
      receipt_id: "gn-ten:#{fixture_id}:phase-16",
      requirement_id: fixture_id,
      owner_repo: owner_repo(fixture_id),
      state: "passed",
      proof_command: "mix test",
      receipt_path: "docs/receipts/adaptive/#{fixture_id}.json",
      spec_cell: spec_cell(fixture_id)
    )
  end

  defp spec_cell(fixture_id) do
    SpecCell.new!(
      requirement_id: fixture_id,
      owner_repo: owner_repo(fixture_id),
      source_docs: ["implementation_docset/10_acceptance_fixtures.md"],
      target_code_paths: ["support/gn_ten_control_plane"],
      proof_command: "mix test",
      acceptance_fixture: fixture_id,
      scanner_refs: ["release_proof.audit"],
      closeout_state: :green,
      release_claim: "Adaptive fixture #{fixture_id} maps to release proof"
    )
  end

  defp owner_repo("AOC-048"), do: "stack_lab"
  defp owner_repo("PERSIST-AOC-" <> _suffix), do: "adaptive_platform"
  defp owner_repo(_fixture_id), do: "adaptive_platform"
end
