defmodule StackLab.CitadelSpineHarness.MezzanineRestartRecovery do
  @moduledoc false

  alias Ash
  alias Mezzanine.Execution.ExecutionRecord
  alias Mezzanine.Objects.SubjectRecord
  alias Mezzanine.RuntimeScheduler.ReconcileOnStart
  alias StackLab.CitadelSpineHarness.{DispatchProbe, LowerGatewayStub, MezzanineSubstrate}

  @tenant_id "tenant-1"
  @dispatch_snapshot %{
    "placement_ref" => "local_docker",
    "execution_params" => %{"timeout_ms" => 600_000},
    "connector_bindings" => %{"github_write" => %{"connector_key" => "github_app"}}
  }

  @spec run_case(:temporal_replay_after_restart) :: {:ok, map()}
  def run_case(:temporal_replay_after_restart) do
    MezzanineSubstrate.with_store(:temporal_replay_after_restart, fn repo_config ->
      installation_id = "stack-lab-installation"
      tenant_id = @tenant_id
      {:ok, ledger} = start_submission_ledger()

      try do
        {:ok, subject} = ingest_subject(installation_id, "stack-lab:restart-recovery")
        {:ok, execution} = dispatch_execution(subject, tenant_id, installation_id)
        initial_handoff = DispatchProbe.temporal_handoff_for!(execution.id)
        recovery_now = DateTime.add(DateTime.utc_now(), 5, :second)
        claimed = crash_after_submission!(execution.id, ledger)

        :ok = DispatchProbe.drop_temporal_handoff!(execution.id)

        before_restart = %{
          execution_dispatch_state: fetch_execution!(execution.id).dispatch_state,
          temporal_handoff_ref: initial_handoff.id,
          handoff_status: :missing_after_crash,
          submission_dedupe_key: claimed.submission_dedupe_key
        }

        :ok = MezzanineSubstrate.restart_runtime!(repo_config)

        {:ok, reconcile_summary} = reconcile_on_start!(installation_id, recovery_now)

        after_execution = fetch_execution!(execution.id)
        after_handoff = DispatchProbe.temporal_handoff_for!(execution.id)

        final_dispatch =
          LowerGatewayStub.with_handlers(
            %{
              lookup_submission: fn [submission_dedupe_key, replay_tenant_id] ->
                if replay_tenant_id != tenant_id do
                  raise "restart recovery replayed the wrong tenant"
                end

                if submission_dedupe_key != claimed.submission_dedupe_key do
                  raise "restart recovery changed the submission dedupe key"
                end

                {:accepted, normalize_lookup_acceptance!(replay_duplicate!(ledger, claimed))}
              end
            },
            fn ->
              dispatch = DispatchProbe.perform_dispatch!(execution.id)

              if dispatch.classification != :accepted do
                raise "expected restart recovery replay to resume as accepted, got: #{inspect(dispatch)}"
              end

              dispatch
            end
          )

        ledger_stats = submission_ledger_stats(ledger)

        {:ok,
         %{
           case: :temporal_replay_after_restart,
           before_restart: before_restart,
           after_restart: %{
             recovered_count: reconcile_summary.dispatch_recovered_count,
             execution_dispatch_state: after_execution.dispatch_state,
             temporal_handoff_ref: after_handoff.id,
             handoff_status: normalize_handoff_state(after_handoff.state),
             dispatch_attempt_count: after_execution.dispatch_attempt_count
           },
           final: %{
             classification: final_dispatch.classification,
             execution_dispatch_state: final_dispatch.execution.dispatch_state,
             handoff_status: final_dispatch.job_status,
             temporal_handoff_ref: final_dispatch.handoff.id,
             submission_ref_status: final_dispatch.execution.submission_ref["status"],
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
      subject_kind: "linear_coding_ticket",
      lifecycle_state: "queued",
      schema_ref: "mezzanine.subject.linear_coding_ticket.payload.v1",
      schema_version: 1,
      payload: %{
        "identifier" => source_ref,
        "source_kind" => "stack_lab_restart_recovery",
        "title" => "Restart recovery proof"
      },
      trace_id: "trace-subject-#{source_ref}",
      causation_id: "cause-subject-#{source_ref}",
      actor_ref: %{kind: :intake}
    })
  end

  defp dispatch_execution(subject, tenant_id, installation_id) do
    ExecutionRecord.dispatch(%{
      tenant_id: tenant_id,
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

  defp crash_after_submission!(execution_id, ledger) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        LowerGatewayStub.with_handlers(
          %{
            dispatch: fn [claimed] ->
              send(parent, {:claimed_dispatch, claimed})
              persist_initial_acceptance!(ledger, claimed)
              exit(:dispatch_process_crashed)
            end
          },
          fn ->
            DispatchProbe.perform_dispatch!(execution_id)
          end
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

  defp reconcile_on_start!(installation_id, recovery_now) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    apply(ReconcileOnStart, :reconcile, [installation_id, recovery_now, []])
  end

  defp normalize_lookup_acceptance!(%{
         "submission_ref" => submission_ref,
         "lower_receipt" => lower_receipt
       }) do
    %{submission_ref: submission_ref, lower_receipt: lower_receipt}
  end

  defp normalize_handoff_state(state) when is_binary(state), do: String.to_atom(state)
end
