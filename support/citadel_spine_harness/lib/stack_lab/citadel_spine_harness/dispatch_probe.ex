defmodule StackLab.CitadelSpineHarness.DispatchProbe do
  @moduledoc false

  alias Mezzanine.Execution.ExecutionRecord
  alias Mezzanine.Execution.Repo
  alias Mezzanine.ExecutionDispatchWorker

  @dispatch_worker Oban.Worker.to_string(Mezzanine.ExecutionDispatchWorker)

  @type result :: %{
          execution: ExecutionRecord.t(),
          job: Oban.Job.t(),
          worker_result: :ok | :discard | {:snooze, pos_integer()} | {:error, term()},
          classification: atom(),
          job_status: atom()
        }

  @spec perform_dispatch!(Ecto.UUID.t(), keyword()) :: result()
  def perform_dispatch!(execution_id, opts \\ []) do
    job = dispatch_job_for!(execution_id)
    attempt = Keyword.get(opts, :attempt, 1)

    worker_result =
      ExecutionDispatchWorker.perform(%Oban.Job{
        id: job.id,
        attempt: attempt,
        queue: job.queue,
        args: job.args
      })

    {:ok, execution} = Ash.get(ExecutionRecord, execution_id)

    %{
      execution: execution,
      job: job,
      worker_result: worker_result,
      classification: classification_for(execution),
      job_status: job_status_for(worker_result, execution)
    }
  end

  @spec dispatch_job_for!(Ecto.UUID.t()) :: Oban.Job.t()
  def dispatch_job_for!(execution_id) do
    Repo.all(Oban.Job)
    |> Enum.find(fn job ->
      job.worker == @dispatch_worker and job.args["execution_id"] == execution_id
    end)
    |> case do
      nil -> raise "expected a dispatch job for execution #{execution_id}"
      job -> job
    end
  end

  @spec delete_dispatch_jobs!(Ecto.UUID.t()) :: :ok
  def delete_dispatch_jobs!(execution_id) do
    Repo.all(Oban.Job)
    |> Enum.filter(fn job ->
      job.worker == @dispatch_worker and job.args["execution_id"] == execution_id
    end)
    |> Enum.each(&Repo.delete!/1)

    :ok
  end

  defp classification_for(%ExecutionRecord{dispatch_state: state})
       when state in [:accepted, :awaiting_receipt],
       do: :accepted

  defp classification_for(%ExecutionRecord{dispatch_state: :rejected}), do: :terminal_rejection

  defp classification_for(%ExecutionRecord{failure_kind: :semantic_failure}),
    do: :semantic_failure

  defp classification_for(%ExecutionRecord{dispatch_state: :dispatching_retry}),
    do: :retryable_failure

  defp classification_for(%ExecutionRecord{dispatch_state: state}), do: state

  defp job_status_for(:ok, _execution), do: :completed

  defp job_status_for(:discard, %ExecutionRecord{dispatch_state: :rejected}),
    do: :terminal

  defp job_status_for(:discard, _execution), do: :completed
  defp job_status_for({:snooze, _seconds}, _execution), do: :scheduled
  defp job_status_for({:error, _reason}, _execution), do: :failed
end
