defmodule StackLab.CitadelSpineHarness.DispatchProbe do
  @moduledoc false

  alias Mezzanine.Execution.ExecutionRecord
  alias Mezzanine.LowerGateway
  alias Mezzanine.Objects.SubjectRecord

  @type result :: %{
          execution: ExecutionRecord.t(),
          handoff: map(),
          worker_result: :ok | :discard | {:snooze, pos_integer()} | {:error, term()},
          classification: atom(),
          job_status: atom()
        }

  @spec perform_dispatch!(Ecto.UUID.t(), keyword()) :: result()
  def perform_dispatch!(execution_id, opts \\ []) do
    handoff = temporal_handoff_for!(execution_id)
    {:ok, execution} = Ash.get(ExecutionRecord, execution_id)
    attempt = Keyword.get(opts, :attempt, execution.dispatch_attempt_count + 1)

    execution
    |> dispatch_result(attempt)
    |> Map.put(:handoff, handoff)
  end

  @spec temporal_handoff_for!(Ecto.UUID.t()) :: map()
  def temporal_handoff_for!(execution_id) do
    {:ok, execution} = Ash.get(ExecutionRecord, execution_id)

    %{
      id: "temporal-handoff:#{execution.id}:#{execution.dispatch_attempt_count}",
      state: "available",
      queue: "temporal_workflow",
      worker: "Mezzanine.Workflows.ExecutionAttempt",
      args: %{"execution_id" => execution.id}
    }
  end

  @spec drop_temporal_handoff!(Ecto.UUID.t()) :: :ok
  def drop_temporal_handoff!(_execution_id), do: :ok

  defp dispatch_result(%ExecutionRecord{} = execution, attempt) do
    if subject_paused?(execution.subject_id) do
      skipped_dispatch(execution)
    else
      execution
      |> mark_in_flight(attempt)
      |> dispatch_lower_or_replay()
    end
  end

  defp skipped_dispatch(%ExecutionRecord{} = execution) do
    %{
      execution: execution,
      worker_result: {:snooze, 60},
      classification: :paused,
      job_status: :scheduled
    }
  end

  defp mark_in_flight(%ExecutionRecord{dispatch_state: :queued} = execution, attempt) do
    {:ok, marked_execution} =
      ExecutionRecord.mark_dispatching(execution, %{
        trace_id: execution.trace_id,
        causation_id: "temporal-handoff-claim:#{execution.id}:#{attempt}"
      })

    marked_execution
  end

  defp mark_in_flight(%ExecutionRecord{dispatch_state: :in_flight} = execution, _attempt),
    do: execution

  defp mark_in_flight(%ExecutionRecord{} = execution, _attempt), do: execution

  defp dispatch_lower_or_replay(%ExecutionRecord{} = execution) do
    case LowerGateway.lookup_submission(execution.submission_dedupe_key, execution.tenant_id) do
      {:accepted, acceptance} ->
        record_accepted(execution, acceptance)

      :never_seen ->
        dispatch_lower(execution)

      {:rejected, rejection} ->
        record_terminal_rejection(execution, rejection)

      {:expired, expired_at} ->
        record_lookup_expired(execution, expired_at)

      {:error, error} ->
        retryable_error(execution, error)
    end
  end

  defp dispatch_lower(%ExecutionRecord{} = execution) do
    case LowerGateway.dispatch(dispatch_claim(execution)) do
      {:accepted, acceptance} ->
        record_accepted(execution, acceptance)

      {:rejected, rejection} ->
        record_terminal_rejection(execution, rejection)

      {:semantic_failure, failure} ->
        record_semantic_failure(execution, failure)

      {:error, {:retryable, error, payload}} ->
        record_retryable_failure(execution, error, payload)

      {:error, {:terminal, error, payload}} ->
        record_terminal_rejection(execution, payload, error)

      {:error, {:semantic_failure, payload}} ->
        record_semantic_failure(execution, payload)

      {:error, error} ->
        retryable_error(execution, error)
    end
  end

  defp record_accepted(execution, acceptance) do
    %{submission_ref: submission_ref, lower_receipt: lower_receipt} =
      normalize_acceptance!(acceptance)

    {:ok, accepted_execution} =
      ExecutionRecord.record_accepted(execution, %{
        submission_ref: submission_ref,
        lower_receipt: lower_receipt,
        trace_id: execution.trace_id,
        causation_id: "temporal-handoff-accepted:#{execution.id}",
        actor_ref: %{kind: :temporal_activity}
      })

    completed_dispatch(accepted_execution, :accepted, :ok)
  end

  defp record_terminal_rejection(execution, rejection, reason \\ "terminal_rejection") do
    {:ok, rejected_execution} =
      ExecutionRecord.record_terminal_rejection(execution, %{
        terminal_rejection_reason: to_string(reason),
        last_dispatch_error_payload: normalize_payload(rejection),
        trace_id: execution.trace_id,
        causation_id: "temporal-handoff-rejected:#{execution.id}",
        actor_ref: %{kind: :temporal_activity}
      })

    completed_dispatch(rejected_execution, :terminal_rejection, :discard)
  end

  defp record_semantic_failure(execution, failure) do
    {:ok, failed_execution} =
      ExecutionRecord.record_semantic_failure(execution, %{
        lower_receipt: Map.get(normalize_payload(failure), "lower_receipt", %{}),
        last_dispatch_error_payload: normalize_payload(failure),
        trace_id: execution.trace_id,
        causation_id: "temporal-handoff-semantic-failure:#{execution.id}",
        actor_ref: %{kind: :temporal_activity}
      })

    completed_dispatch(failed_execution, :semantic_failure, :discard)
  end

  defp record_retryable_failure(execution, error, payload) do
    next_dispatch_at = DateTime.add(DateTime.utc_now(), 30, :second)

    {:ok, retry_execution} =
      ExecutionRecord.record_retryable_failure(execution, %{
        last_dispatch_error_kind: inspect(error),
        last_dispatch_error_payload: normalize_payload(payload),
        next_dispatch_at: next_dispatch_at,
        trace_id: execution.trace_id,
        causation_id: "temporal-handoff-retry:#{execution.id}",
        actor_ref: %{kind: :temporal_activity}
      })

    %{
      execution: retry_execution,
      worker_result: {:snooze, 30},
      classification: :retryable_failure,
      job_status: :scheduled
    }
  end

  defp record_lookup_expired(execution, expired_at) do
    {:ok, expired_execution} =
      ExecutionRecord.record_lookup_expired(execution, %{
        last_dispatch_error_payload: %{"expired_at" => DateTime.to_iso8601(expired_at)},
        trace_id: execution.trace_id,
        causation_id: "temporal-handoff-lookup-expired:#{execution.id}",
        actor_ref: %{kind: :temporal_activity}
      })

    completed_dispatch(expired_execution, :infrastructure_error, :discard)
  end

  defp retryable_error(execution, error), do: record_retryable_failure(execution, error, %{})

  defp completed_dispatch(execution, classification, worker_result) do
    %{
      execution: execution,
      worker_result: worker_result,
      classification: classification,
      job_status: job_status_for(worker_result, execution)
    }
  end

  defp dispatch_claim(%ExecutionRecord{} = execution) do
    %{
      execution_id: execution.id,
      tenant_id: execution.tenant_id,
      installation_id: execution.installation_id,
      subject_id: execution.subject_id,
      trace_id: execution.trace_id,
      causation_id: execution.causation_id,
      submission_dedupe_key: execution.submission_dedupe_key,
      compiled_pack_revision: execution.compiled_pack_revision,
      binding_snapshot: execution.binding_snapshot,
      dispatch_envelope: execution.dispatch_envelope
    }
  end

  defp normalize_acceptance!(%{submission_ref: submission_ref, lower_receipt: lower_receipt}) do
    %{submission_ref: submission_ref, lower_receipt: lower_receipt}
  end

  defp normalize_acceptance!(%{
         "submission_ref" => submission_ref,
         "lower_receipt" => lower_receipt
       }) do
    %{submission_ref: submission_ref, lower_receipt: lower_receipt}
  end

  defp normalize_payload(payload) when is_map(payload) do
    Map.new(payload, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {key, value}
    end)
  end

  defp normalize_payload(payload), do: %{"payload" => inspect(payload)}

  defp subject_paused?(subject_id) do
    case Ash.get(SubjectRecord, subject_id) do
      {:ok, %{status: "paused"}} -> true
      _other -> false
    end
  end

  defp job_status_for(:ok, _execution), do: :completed

  defp job_status_for(:discard, %ExecutionRecord{dispatch_state: :rejected}),
    do: :terminal

  defp job_status_for(:discard, _execution), do: :completed
end
