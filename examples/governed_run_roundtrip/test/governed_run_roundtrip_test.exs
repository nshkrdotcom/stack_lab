defmodule StackLab.Examples.GovernedRunRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.GovernedRunRoundtrip

  test "governed-run scenario exposes the non-extravaganza proof case" do
    scenario = GovernedRunRoundtrip.scenario()

    assert scenario.name == :governed_run_roundtrip

    assert scenario.cases == %{
             expense_capture_acceptance: %{kind: :expense_capture_acceptance},
             multi_pack_installation_routing: %{kind: :multi_pack_installation_routing}
           }

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
    assert result.dispatch.tenant_id == "tenant-expense"
    assert result.dispatch.classification == :accepted
    assert result.dispatch.job_status == :completed
    assert result.dispatch.submission_ref_status == "accepted"

    assert result.transitions.on_execution_requested == "processing"
    assert result.transitions.on_execution_completed == "paid"
  end

  test "same tenant can run two packs concurrently with installation-scoped routing" do
    assert {:ok, result} = GovernedRunRoundtrip.exercise(:multi_pack_installation_routing)

    assert result.case == :multi_pack_installation_routing
    assert result.routing.tenant_id == "tenant-multi-pack"
    assert result.routing.environment == "stage3"
    assert result.routing.shared_source_ref == "shared:external:event-42"

    assert result.installations.expense.pack_slug == "expense_approval"
    assert result.installations.expense.subject_kind == "expense_request"
    assert result.installations.invoice.pack_slug == "invoice_ops"
    assert result.installations.invoice.subject_kind == "invoice_request"

    refute result.installations.expense.installation_id ==
             result.installations.invoice.installation_id

    assert result.subjects.expense.installation_id == result.installations.expense.installation_id
    assert result.subjects.expense.subject_kind == "expense_request"
    assert result.subjects.expense.source_ref == result.routing.shared_source_ref

    assert result.subjects.invoice.installation_id == result.installations.invoice.installation_id
    assert result.subjects.invoice.subject_kind == "invoice_request"
    assert result.subjects.invoice.source_ref == result.routing.shared_source_ref

    assert result.dispatches.expense.installation_id ==
             result.installations.expense.installation_id

    assert result.dispatches.expense.tenant_id == result.routing.tenant_id
    assert result.dispatches.expense.recipe_ref == "expense_capture"
    assert result.dispatches.expense.classification == :accepted

    assert result.dispatches.invoice.installation_id ==
             result.installations.invoice.installation_id

    assert result.dispatches.invoice.tenant_id == result.routing.tenant_id
    assert result.dispatches.invoice.recipe_ref == "invoice_capture"
    assert result.dispatches.invoice.classification == :accepted
  end
end
