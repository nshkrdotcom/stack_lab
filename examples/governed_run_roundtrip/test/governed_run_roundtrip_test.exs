defmodule StackLab.Examples.GovernedRunRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.GovernedRunRoundtrip

  test "governed-run scenario exposes the non-extravaganza proof case" do
    scenario = GovernedRunRoundtrip.scenario()

    assert scenario.name == :governed_run_roundtrip
    assert scenario.cases == %{expense_capture_acceptance: %{kind: :expense_capture_acceptance}}
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "expense approval pack roundtrip proves neutral substrate genericity" do
    assert {:ok, result} = GovernedRunRoundtrip.exercise(:expense_capture_acceptance)

    assert result.case == :expense_capture_acceptance
    assert result.pack.pack_slug == "expense_approval"
    assert result.pack.subject_kind == "expense_request"
    assert result.pack.compiled_pack_revision == 2

    assert result.dispatch.recipe_ref == "expense_capture"
    assert result.dispatch.classification == :accepted
    assert result.dispatch.outbox_status == :completed
    assert result.dispatch.submission_ref_status == "accepted"

    assert result.transitions.on_execution_requested == "processing"
    assert result.transitions.on_execution_completed == "paid"
  end
end
