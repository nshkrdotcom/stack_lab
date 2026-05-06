defmodule StackLab.CostRoundtripTest do
  use ExUnit.Case, async: true

  alias AppKit.{BudgetSurface, CostSurface}
  alias StackLab.CostRoundtrip

  test "runs the Phase D cost and budget proof roundtrip" do
    assert {:ok, receipt} = CostRoundtrip.run()

    assert "COST-001" in receipt.fixture_refs
    assert "COST-013" in receipt.fixture_refs
    assert receipt.production_cost_class == :production
    assert receipt.replay_cost_class == :replay
    assert receipt.eval_cost_class == :eval
    assert %CostSurface.CostBreakdownProjection{} = receipt.cost_projection
    assert %BudgetSurface.BudgetViewProjection{} = receipt.budget_view
    assert %BudgetSurface.BudgetExhaustionRecord{} = receipt.budget_exhaustion
    assert receipt.trace_event_name == "cost.attribute"
    assert receipt.budget_event_name == "budget.exhaust"
  end
end
