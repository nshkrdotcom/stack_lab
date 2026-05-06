defmodule StackLab.CitadelSpineHarness.InstallationRuntimeLeaseTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "same tenant can hold distinct installation leases while fencing a competing owner" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_installation_runtime_lease(:two_owner_fencing)

    assert result.case == :two_owner_fencing
    assert result.tenant_id == "tenant-installation-lease"
    assert result.environment == "stage3"

    refute result.installations.expense.installation_id ==
             result.installations.invoice.installation_id

    assert result.first_claims.expense.installation_id ==
             result.installations.expense.installation_id

    assert result.first_claims.invoice.installation_id ==
             result.installations.invoice.installation_id

    assert result.first_claims.expense.holder == "scheduler-a"
    assert result.first_claims.invoice.holder == "scheduler-b"

    assert result.competing_claim.status == :held_by_other

    assert result.competing_claim.fence.installation_id ==
             result.installations.expense.installation_id

    assert result.competing_claim.fence.holder == "scheduler-a"
    assert result.competing_claim.fence.epoch == 1

    assert result.stale_takeover.status == :stale_epoch

    assert result.stale_takeover.fence.installation_id ==
             result.installations.expense.installation_id

    assert result.stale_takeover.fence.epoch == 1

    assert result.takeover.status == :acquired
    assert result.takeover.lease.installation_id == result.installations.expense.installation_id
    assert result.takeover.lease.holder == "scheduler-b"
    assert result.takeover.lease.epoch == 2

    assert result.persisted.expense == result.takeover.lease
    assert result.persisted.invoice == result.first_claims.invoice
  end
end
