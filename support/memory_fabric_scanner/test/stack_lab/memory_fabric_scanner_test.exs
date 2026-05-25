defmodule StackLab.MemoryFabricScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.MemoryFabricScanner

  test "runtime facts require tenant, authority, installation, idempotency, and trace refs" do
    assert {:ok, receipt} =
             MemoryFabricScanner.scan(%{
               owner_repo: "outer_brain",
               runtime_facts: [runtime_fact()]
             })

    assert receipt.status == :pass

    assert {:ok, receipt} =
             MemoryFabricScanner.scan(%{
               owner_repo: "outer_brain",
               runtime_facts: [Map.delete(runtime_fact(), :trace_ref)]
             })

    assert receipt.status == :open_defect
    assert [%{reason: :missing_required_memory_refs}] = receipt.findings
  end

  test "runtime facts reject silent memory candidate mutation" do
    assert {:ok, receipt} =
             MemoryFabricScanner.scan(%{
               owner_repo: "outer_brain",
               runtime_facts: [promotion_fact()]
             })

    assert receipt.status == :pass

    assert {:ok, receipt} =
             MemoryFabricScanner.scan(%{
               owner_repo: "outer_brain",
               runtime_facts: [
                 promotion_fact()
                 |> Map.delete(:eval_evidence_refs)
                 |> Map.delete(:citadel_authority_ref)
               ]
             })

    assert receipt.status == :open_defect
    assert [%{reason: :silent_memory_candidate_mutation}] = receipt.findings
  end

  test "static scanner catches direct adapter references outside memory engine owner path" do
    path = Path.expand("../fixtures/direct_adapter_reference.source", __DIR__)

    assert {:ok, receipt} =
             MemoryFabricScanner.scan(%{
               owner_repo: "app_kit",
               source_paths: [path]
             })

    assert receipt.status == :open_defect
    assert [%{reason: :direct_memory_adapter_reference}] = receipt.findings
  end

  test "owner path may reference memory engine store modules" do
    path =
      Path.expand(
        "../fixtures/outer_brain/core/memory_engine/lib/owner_memory_reference.source",
        __DIR__
      )

    assert {:ok, receipt} =
             MemoryFabricScanner.scan(%{
               owner_repo: "outer_brain",
               source_paths: [path],
               runtime_facts: [runtime_fact()]
             })

    assert receipt.status == :pass
  end

  defp runtime_fact do
    %{
      tenant_ref: "tenant://a",
      authority_ref: "authority://a",
      installation_ref: "installation://a",
      idempotency_key: "idem",
      trace_ref: "trace://a"
    }
  end

  defp promotion_fact do
    runtime_fact()
    |> Map.merge(%{
      candidate_ref: "memory-candidate://tenant-a/a",
      promotion_ref: "memory-promotion://tenant-a/a",
      rollback_ref: "memory-rollback://tenant-a/a",
      eval_evidence_refs: ["eval://memory/a"],
      citadel_authority_ref: "authority://citadel/promotion/a",
      appkit_projection_ref: "appkit://memory/promotion/a"
    })
  end
end
