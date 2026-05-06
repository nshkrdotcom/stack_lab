defmodule StackLab.AIRunLineageScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.AIRunLineageScanner

  test "passes complete AI run lineage facts" do
    assert {:ok, receipt} =
             AIRunLineageScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/ai_run_model",
               run_facts: [complete_fact()]
             })

    assert receipt.status == :pass
    assert receipt.findings == []
  end

  test "requires parent graph, idempotency, persistence, and trace refs" do
    assert {:ok, receipt} =
             AIRunLineageScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/ai_run_model",
               run_facts: [%{}]
             })

    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.rule) == [
             :ai_run_ref,
             :tenant_ref,
             :authority_ref,
             :parent_run_ref,
             :idempotency_ref,
             :persistence_profile_ref,
             :optimization_refs,
             :trace_refs
           ]
  end

  defp complete_fact do
    %{
      ai_run_ref: "ai-run://optimization/child",
      tenant_ref: "tenant://phase-8",
      authority_ref: "authority://optimization",
      parent_run_ref: "ai-run://optimization/root",
      idempotency_ref: "idempotency://optimization/child",
      persistence_profile_ref: "persistence://memory-minimal",
      optimization_refs: ["optimization-run://phase-8"],
      trace_refs: ["trace://optimization/child"]
    }
  end
end
