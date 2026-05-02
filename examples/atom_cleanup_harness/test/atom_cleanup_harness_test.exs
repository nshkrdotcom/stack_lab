defmodule StackLab.Examples.AtomCleanupHarnessTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.AtomCleanupHarness
  alias StackLab.Examples.AtomCleanupHarness.Finding
  alias StackLab.GnTenControlPlane
  alias StackLab.SpecCell

  test "scan_text records known dynamic atom patterns without source excerpts" do
    findings =
      AtomCleanupHarness.scan_text(
        "lib/example.ex",
        "String.to_atom(provider_name)\n:ok\nbinary_to_existing_atom(mode)",
        owner_repo: "extravaganza"
      )

    assert [
             %Finding{
               owner_repo: "extravaganza",
               path: "lib/example.ex",
               line: 1,
               pattern: :string_to_atom
             },
             %Finding{
               owner_repo: "extravaganza",
               path: "lib/example.ex",
               line: 3,
               pattern: :binary_to_existing_atom
             }
           ] = findings
  end

  test "classification is bounded and unknown classes are rejected" do
    [finding] = AtomCleanupHarness.scan_text("lib/example.ex", "String.to_atom(value)")

    assert {:ok, %Finding{classification: :runtime_bounded}} =
             AtomCleanupHarness.classify(finding, :runtime_bounded)

    assert {:error, :unknown_classification} =
             AtomCleanupHarness.classify(finding, :provider_named_atom)
  end

  test "unresolved runtime external input blocks release" do
    [finding] = AtomCleanupHarness.scan_text("lib/example.ex", "String.to_atom(value)")

    assert AtomCleanupHarness.release_blocking?(finding)

    assert {:ok, classified} = AtomCleanupHarness.classify(finding, :runtime_bounded)
    refute AtomCleanupHarness.release_blocking?(classified)
  end

  test "creates SpecCell and gn-ten receipt records for atom phases" do
    cell =
      AtomCleanupHarness.spec_cell("extravaganza",
        requirement_id: "ATOM-01",
        acceptance_fixture: "UAA-027",
        target_code_paths: ["/home/home/p/g/n/extravaganza"],
        proof_command: "mix test test/extravaganza/product_pack_atom_test.exs"
      )

    assert %SpecCell{} = cell
    refute SpecCell.complete?(cell)

    receipt = AtomCleanupHarness.receipt(cell, requirement_id: "ATOM-01", state: "missing")

    assert %GnTenControlPlane{} = receipt
    assert GnTenControlPlane.release_blocking?(receipt)
  end
end
