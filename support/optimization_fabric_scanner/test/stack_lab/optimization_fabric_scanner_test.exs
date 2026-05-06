defmodule StackLab.OptimizationFabricScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.OptimizationFabricScanner

  test "passes complete governed optimization fabric facts" do
    assert {:ok, receipt} =
             OptimizationFabricScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/optimization_engine",
               optimization_facts: [complete_fact()]
             })

    assert receipt.status == :pass
    assert receipt.fixture_refs == ["AOC-018", "AOC-019", "AOC-042"]
    assert receipt.findings == []
  end

  test "requires candidate lineage, eval, proposer, promotion, budget, and trace refs" do
    assert {:ok, receipt} =
             OptimizationFabricScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/optimization_engine",
               optimization_facts: [%{}]
             })

    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.rule) == [
             :candidate_lineage_refs,
             :eval_dataset_refs,
             :proposer_model_ref,
             :promotion_gate_refs,
             :budget_refs,
             :trace_refs,
             :promotion_refs,
             :rollback_refs,
             :provenance_refs
           ]
  end

  test "rejects unredacted trace facts" do
    fact =
      complete_fact()
      |> Map.put(:trace_refs, ["trace://candidate/eval"])
      |> Map.put(:trace_redaction, :raw)

    assert {:ok, receipt} =
             OptimizationFabricScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/optimization_engine",
               optimization_facts: [fact]
             })

    assert [%{rule: :trace_refs, reason: :trace_refs_not_redacted}] = receipt.findings
  end

  defp complete_fact do
    %{
      candidate_lineage_refs: ["lineage://candidate"],
      eval_dataset_refs: ["dataset://eval"],
      proposer_model_ref: "model-profile://mock/proposer",
      promotion_gate_refs: [
        "gate://eval",
        "gate://replay",
        "gate://guardrail",
        "gate://cost",
        "gate://shadow",
        "gate://canary",
        "gate://human-approval"
      ],
      budget_refs: ["budget://optimization"],
      trace_refs: ["trace://candidate/eval"],
      trace_redaction: :redacted,
      promotion_refs: ["promotion://candidate"],
      rollback_refs: ["rollback://candidate"],
      provenance_refs: ["provenance://candidate"]
    }
  end
end
