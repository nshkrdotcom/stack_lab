defmodule StackLab.CitadelSpineHarness.Phase3M6ReleaseReadinessTest do
  use ExUnit.Case, async: false

  alias Mezzanine.AppKitBridge.OperatorActionService
  alias Mezzanine.Execution.LifecycleContinuation

  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.MezzanineOperationalStack

  @now ~U[2026-04-18 19:00:00Z]
  @future ~U[2026-04-20 19:00:00Z]

  test "Scenario 39 proves stale installation revisions fail closed during lease ownership changes" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_installation_runtime_lease(:two_owner_fencing)

    assert result.case == :two_owner_fencing
    assert result.competing_claim.status == :held_by_other
    assert result.stale_takeover.status == :stale_epoch
    assert result.takeover.status == :acquired

    assert result.persisted.expense.holder == "scheduler-b"
    assert result.persisted.expense.epoch == 2

    assert result.stale_revision.status == :stale_revision
    assert result.stale_revision.attempted_revision == 0
    assert result.stale_revision.current_revision == 1
    assert result.stale_revision.fence.holder == "scheduler-b"
    assert result.stale_revision.fence.compiled_pack_revision == 1
  end

  test "Scenario 40 proves continuation retry, dead-letter, operator retry, waive, and duplicate safety" do
    MezzanineOperationalStack.with_store(:phase3_m6_continuation_dead_letter, fn _repo_config ->
      transient = continuation_fixture!("transient")

      assert {:ok, retry_scheduled} =
               LifecycleContinuation.process(transient.continuation_id,
                 now: @now,
                 handler: fn _continuation -> {:error, :lock_timeout} end,
                 backoff_ms: 1_000
               )

      assert retry_scheduled.status == :retry_scheduled
      assert retry_scheduled.last_error_class == "transient_lock"

      invalid = continuation_fixture!("invalid")

      assert {:ok, dead_lettered} =
               LifecycleContinuation.process(invalid.continuation_id,
                 now: @now,
                 handler: fn _continuation -> {:error, {:invalid_transition, "bad-target"}} end
               )

      assert dead_lettered.status == :dead_lettered
      assert dead_lettered.last_error_class == "invalid_transition"

      assert {:ok, operator_rows} =
               LifecycleContinuation.list_operator("tenant-phase3-m6", "installation-phase3-m6")

      assert Enum.map(operator_rows, & &1.continuation_id) |> Enum.sort() ==
               [dead_lettered.continuation_id, retry_scheduled.continuation_id] |> Enum.sort()

      assert {:ok, retry_action} =
               OperatorActionService.apply_action(
                 "tenant-phase3-m6",
                 dead_lettered.subject_id,
                 :retry_continuation,
                 %{continuation_id: dead_lettered.continuation_id},
                 %{"kind" => "operator", "id" => "operator-phase3-m6"}
               )

      assert retry_action.status == :completed
      assert retry_action.metadata.status == :pending

      assert {:ok, completed} =
               LifecycleContinuation.process(dead_lettered.continuation_id,
                 now: @future,
                 handler: fn _continuation -> :ok end
               )

      assert completed.status == :completed

      assert {:ok, :already_completed} =
               LifecycleContinuation.process(completed.continuation_id,
                 now: DateTime.add(@future, 1, :second),
                 handler: fn _continuation -> flunk("completed continuation processed twice") end
               )

      waived = continuation_fixture!("waived")

      assert {:ok, waived_dead_letter} =
               LifecycleContinuation.process(waived.continuation_id,
                 now: @now,
                 handler: fn _continuation -> {:error, :invalid_transition} end
               )

      assert {:ok, waive_action} =
               OperatorActionService.apply_action(
                 "tenant-phase3-m6",
                 waived_dead_letter.subject_id,
                 :waive_continuation,
                 %{
                   continuation_id: waived_dead_letter.continuation_id,
                   reason: "operator accepted terminal state"
                 },
                 %{"kind" => "operator", "id" => "operator-phase3-m6"}
               )

      assert waive_action.status == :completed
      assert waive_action.metadata.status == :completed
      assert waive_action.metadata.last_error_class == "operator_waived"
    end)
  end

  test "Scenario 43 proves duplicate worker ticks and node-loss reconciliation avoid duplicate lower submission" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_stage12_load_readiness(:shared_repo_pressure_posture)

    assert result.case == :shared_repo_pressure_posture
    assert result.lower_dispatch_ambiguity.recovered_count == 1
    assert result.lower_dispatch_ambiguity.unique_submission_count == 1
    assert result.lower_dispatch_ambiguity.duplicate_replay_count == 1

    assert result.startup_reconciliation.launcher_count == 3
    assert result.startup_reconciliation.reconcile_job_count == 1
    assert length(result.startup_reconciliation.summary_execution_ids) == 3

    assert result.pool_pressure.all_queries_succeeded?
    assert result.pool_pressure.checkout_timeout_count == 0
  end

  defp continuation_fixture!(suffix) do
    {:ok, continuation} =
      LifecycleContinuation.enqueue(%{
        continuation_id: "phase3-m6-continuation-#{suffix}",
        tenant_id: "tenant-phase3-m6",
        installation_id: "installation-phase3-m6",
        subject_id: Ecto.UUID.generate(),
        execution_id: Ecto.UUID.generate(),
        from_state: "processing",
        target_transition: "execution_completed:expense_capture",
        next_attempt_at: @now,
        trace_id: "trace-phase3-m6-#{suffix}",
        status: :pending,
        actor_ref: %{"kind" => "stack_lab"}
      })

    continuation
  end
end
