defmodule StackLab.CitadelSpineHarness.MezzanineRestartRecovery do
  @moduledoc false

  alias Ash
  alias Mezzanine.Execution.{Dispatcher, DispatchOutboxEntry, ExecutionRecord}
  alias Mezzanine.Objects.SubjectRecord
  alias StackLab.CitadelSpineHarness.MezzanineSubstrate

  @dispatch_snapshot %{
    "placement_ref" => "local_docker",
    "execution_params" => %{"timeout_ms" => 600_000},
    "connector_bindings" => %{"github_write" => %{"connector_key" => "github_app"}}
  }

  @spec run_case(:dispatching_retry_after_restart) :: {:ok, map()}
  def run_case(:dispatching_retry_after_restart) do
    MezzanineSubstrate.with_store(:dispatching_retry_after_restart, fn repo_config ->
      installation_id = "stack-lab-installation"
      crash_now = ~U[2026-04-16 12:00:00.000000Z]
      recovery_now = ~U[2026-04-16 12:00:05.000000Z]
      {:ok, ledger} = start_submission_ledger()

      try do
        {:ok, subject} = ingest_subject(installation_id, "stack-lab:restart-recovery")
        {:ok, execution} = dispatch_execution(subject, installation_id)
        {:ok, initial_outbox} = DispatchOutboxEntry.by_execution_id(execution.id)
        claimed = crash_after_submission!(crash_now, ledger)

        before_restart = %{
          execution_dispatch_state: fetch_execution!(execution.id).dispatch_state,
          outbox_status: fetch_outbox!(execution.id).status,
          outbox_id: initial_outbox.id,
          submission_dedupe_key: claimed.submission_dedupe_key
        }

        :ok = MezzanineSubstrate.restart_runtime!(repo_config)

        {:ok, reconcile_summary} =
          runtime_scheduler_call!(:reconcile_on_start, [installation_id, recovery_now])

        after_execution = fetch_execution!(execution.id)
        after_outbox = fetch_outbox!(execution.id)

        replay_submit =
          fn replay_claim ->
            if replay_claim.execution_id != execution.id do
              raise "unexpected execution replayed after restart"
            end

            if replay_claim.outbox_id != initial_outbox.id do
              raise "restart recovery replayed a different outbox row"
            end

            if replay_claim.submission_dedupe_key != claimed.submission_dedupe_key do
              raise "restart recovery changed the submission dedupe key"
            end

            {:accepted, replay_duplicate!(ledger, replay_claim)}
          end

        {:ok, %{classification: :accepted, execution: accepted_execution}} =
          Dispatcher.dispatch_next(
            submit_fun: replay_submit,
            actor_ref: %{kind: :dispatcher},
            now: recovery_now
          )

        final_outbox = fetch_outbox!(execution.id)
        ledger_stats = submission_ledger_stats(ledger)

        {:ok,
         %{
           case: :dispatching_retry_after_restart,
           before_restart: before_restart,
           after_restart: %{
             recovered_count: reconcile_summary.recovered_count,
             execution_dispatch_state: after_execution.dispatch_state,
             outbox_status: after_outbox.status,
             dispatch_attempt_count: after_execution.dispatch_attempt_count
           },
           final: %{
             classification: :accepted,
             execution_dispatch_state: accepted_execution.dispatch_state,
             outbox_status: final_outbox.status,
             outbox_id: final_outbox.id,
             submission_ref_status: accepted_execution.submission_ref["status"],
             unique_submission_count: ledger_stats.unique_submission_count,
             duplicate_replay_count: ledger_stats.duplicate_replay_count
           }
         }}
      after
        stop_submission_ledger(ledger)
      end
    end)
  end

  defp ingest_subject(installation_id, source_ref) do
    SubjectRecord.ingest(%{
      installation_id: installation_id,
      source_ref: source_ref,
      subject_kind: "generic_task",
      lifecycle_state: "queued",
      payload: %{},
      trace_id: "trace-subject-#{source_ref}",
      causation_id: "cause-subject-#{source_ref}",
      actor_ref: %{kind: :intake}
    })
  end

  defp dispatch_execution(subject, installation_id) do
    ExecutionRecord.dispatch(%{
      installation_id: installation_id,
      subject_id: subject.id,
      recipe_ref: "restart_recovery_recipe",
      compiled_pack_revision: 9,
      binding_snapshot: @dispatch_snapshot,
      dispatch_envelope: %{"capability" => "sandbox.exec"},
      submission_dedupe_key: "#{installation_id}:exec:restart-recovery",
      trace_id: "trace-restart-recovery",
      causation_id: "cause-restart-recovery",
      actor_ref: %{kind: :scheduler}
    })
  end

  defp crash_after_submission!(now, ledger) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Dispatcher.dispatch_next(
          submit_fun: fn claimed ->
            send(parent, {:claimed_dispatch, claimed})
            persist_initial_acceptance!(ledger, claimed)
            exit(:dispatch_process_crashed)
          end,
          actor_ref: %{kind: :dispatcher},
          now: now
        )
      end)

    claimed =
      receive do
        {:claimed_dispatch, claimed} -> claimed
      after
        5_000 -> raise "timed out waiting for claimed dispatch before simulated crash"
      end

    receive do
      {:DOWN, ^ref, :process, ^pid, :dispatch_process_crashed} -> :ok
    after
      5_000 -> raise "timed out waiting for simulated dispatcher crash"
    end

    claimed
  end

  defp start_submission_ledger do
    Agent.start_link(fn ->
      %{submissions: %{}, unique_submission_count: 0, duplicate_replay_count: 0}
    end)
  end

  defp stop_submission_ledger(ledger) do
    Agent.stop(ledger)
  end

  defp persist_initial_acceptance!(ledger, claimed) do
    acceptance = acceptance_payload(claimed, "accepted")

    Agent.update(ledger, fn state ->
      %{
        state
        | submissions: Map.put(state.submissions, claimed.submission_dedupe_key, acceptance),
          unique_submission_count: state.unique_submission_count + 1
      }
    end)

    acceptance
  end

  defp replay_duplicate!(ledger, claimed) do
    Agent.get_and_update(ledger, fn state ->
      acceptance = Map.fetch!(state.submissions, claimed.submission_dedupe_key)

      duplicate_acceptance = %{
        "submission_ref" => Map.put(acceptance["submission_ref"], "status", "duplicate"),
        "lower_receipt" => acceptance["lower_receipt"]
      }

      {duplicate_acceptance, %{state | duplicate_replay_count: state.duplicate_replay_count + 1}}
    end)
  end

  defp submission_ledger_stats(ledger) do
    Agent.get(ledger, fn state ->
      %{
        unique_submission_count: state.unique_submission_count,
        duplicate_replay_count: state.duplicate_replay_count
      }
    end)
  end

  defp acceptance_payload(claimed, submission_status) do
    %{
      "submission_ref" => %{
        "id" => "submission-#{claimed.submission_dedupe_key}",
        "status" => submission_status
      },
      "lower_receipt" => %{
        "state" => "accepted",
        "ji_submission_key" => "ji-#{claimed.submission_dedupe_key}",
        "run_id" => "run-#{claimed.execution_id}"
      }
    }
  end

  defp fetch_execution!(execution_id) do
    {:ok, execution} = Ash.get(ExecutionRecord, execution_id)
    execution
  end

  defp fetch_outbox!(execution_id) do
    {:ok, outbox} = DispatchOutboxEntry.by_execution_id(execution_id)
    outbox
  end

  defp runtime_scheduler_call!(function, args) when is_atom(function) and is_list(args) do
    module = MezzanineRuntimeScheduler

    if function_exported?(module, function, length(args)) do
      apply(module, function, args)
    else
      raise "#{inspect(module)}.#{function}/#{length(args)} is unavailable"
    end
  end
end
