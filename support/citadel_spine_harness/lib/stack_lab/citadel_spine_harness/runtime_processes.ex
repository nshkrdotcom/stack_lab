defmodule StackLab.CitadelSpineHarness.RuntimeProcesses do
  @moduledoc false

  @task_supervisor StackLab.CitadelSpineHarness.TaskSupervisor
  @dynamic_supervisor StackLab.CitadelSpineHarness.RuntimeSupportSupervisor

  @spec async((-> term())) :: Task.t()
  def async(fun) when is_function(fun, 0) do
    ensure_started!()
    Task.Supervisor.async_nolink(@task_supervisor, fun)
  end

  @spec async_stream(Enumerable.t(), (term() -> term()), keyword()) :: Enumerable.t()
  def async_stream(enumerable, fun, opts \\ []) when is_function(fun, 1) do
    ensure_started!()
    Task.Supervisor.async_stream_nolink(@task_supervisor, enumerable, fun, opts)
  end

  @spec start_agent((-> term())) :: {:ok, pid()} | {:error, term()}
  def start_agent(fun) when is_function(fun, 0) do
    ensure_started!()
    DynamicSupervisor.start_child(@dynamic_supervisor, {Agent, fun})
  end

  @spec start_task_child((-> term())) :: {:ok, pid()} | {:error, term()}
  def start_task_child(fun) when is_function(fun, 0) do
    ensure_started!()
    Task.Supervisor.start_child(@task_supervisor, fun)
  end

  defp ensure_started! do
    case Application.ensure_all_started(:stack_lab_citadel_spine_harness) do
      {:ok, _started} -> :ok
      {:error, reason} -> raise "failed to start harness supervisors: #{inspect(reason)}"
    end
  end
end
