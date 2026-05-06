defmodule StackLab.CostBudgetScannerTest do
  use ExUnit.Case, async: true

  alias StackLab.CostBudgetScanner

  test "passes complete adaptive cost and budget facts" do
    assert {:ok, receipt} =
             CostBudgetScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/optimization_engine",
               cost_budget_facts: [complete_fact()]
             })

    assert receipt.status == :pass
    assert receipt.fixture_refs == ["AOC-031"]
    assert receipt.findings == []
  end

  test "requires every governed cost dimension and exhaustion projection ref" do
    assert {:ok, receipt} =
             CostBudgetScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/optimization_engine",
               cost_budget_facts: [%{}]
             })

    assert receipt.status == :open_defect

    assert Enum.map(receipt.findings, & &1.rule) == [
             :token_cost_refs,
             :model_request_cost_refs,
             :self_hosted_gpu_minute_cost_refs,
             :endpoint_startup_cost_refs,
             :eval_batch_cost_refs,
             :replay_cost_refs,
             :optimization_search_cost_refs,
             :provider_pool_turn_cost_refs,
             :role_budget_refs,
             :promotion_cost_refs,
             :failed_retry_cost_refs,
             :exhaustion_decision_ref,
             :appkit_projection_refs,
             :aitrace_span_refs,
             :receipt_refs
           ]
  end

  test "rejects raw payload fields and unredacted receipts" do
    fact =
      complete_fact()
      |> Map.put(:trace_redaction, :raw)
      |> Map.put(:provider_payload, %{body: "not allowed"})

    assert {:ok, receipt} =
             CostBudgetScanner.scan(%{
               owner_repo: "mezzanine",
               package_path: "core/optimization_engine",
               cost_budget_facts: [fact]
             })

    assert has_finding?(receipt, :aitrace_span_refs, :trace_refs_not_redacted)
    assert has_finding?(receipt, :raw_payload, {:forbidden_raw_field, :provider_payload})
  end

  defp has_finding?(receipt, rule, reason) do
    Enum.any?(receipt.findings, fn finding ->
      finding.rule == rule and finding.reason == reason
    end)
  end

  defp complete_fact do
    %{
      token_cost_refs: ["cost://tokens"],
      model_request_cost_refs: ["cost://model-request"],
      self_hosted_gpu_minute_cost_refs: ["cost://gpu-minute"],
      endpoint_startup_cost_refs: ["cost://endpoint-startup"],
      eval_batch_cost_refs: ["cost://eval-batch"],
      replay_cost_refs: ["cost://replay"],
      optimization_search_cost_refs: ["cost://optimization-search"],
      provider_pool_turn_cost_refs: ["cost://provider-pool-turn"],
      role_budget_refs: ["budget://role-worker"],
      promotion_cost_refs: ["cost://promotion"],
      failed_retry_cost_refs: ["cost://retry"],
      exhaustion_decision_ref: "budget-exhaustion://none",
      appkit_projection_refs: ["appkit://budget/projection"],
      aitrace_span_refs: ["aitrace-span://cost"],
      receipt_refs: ["stack-lab-receipt://cost-budget"],
      trace_redaction: :redacted
    }
  end
end
