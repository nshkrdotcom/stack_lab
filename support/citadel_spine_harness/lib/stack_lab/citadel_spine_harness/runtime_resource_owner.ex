defmodule StackLab.CitadelSpineHarness.RuntimeResourceOwner do
  @moduledoc false

  use GenServer

  @held_key {__MODULE__, :held}

  @spec transaction((-> result)) :: result when result: var
  def transaction(fun) when is_function(fun, 0) do
    if Process.get(@held_key) do
      fun.()
    else
      ensure_started!()
      token = make_ref()
      :ok = GenServer.call(__MODULE__, {:acquire, self(), token}, :infinity)
      Process.put(@held_key, true)

      try do
        fun.()
      after
        Process.delete(@held_key)
        GenServer.call(__MODULE__, {:release, self(), token}, :infinity)
      end
    end
  end

  @impl GenServer
  def init(_opts) do
    {:ok, %{owner: nil, queue: :queue.new()}}
  end

  @impl GenServer
  def handle_call({:acquire, pid, token}, _from, %{owner: nil} = state) do
    {:reply, :ok, %{state | owner: monitor_owner(pid, token)}}
  end

  def handle_call({:acquire, pid, token}, from, state) do
    {:noreply, %{state | queue: :queue.in({from, pid, token}, state.queue)}}
  end

  def handle_call({:release, pid, token}, _from, %{owner: {pid, token, monitor_ref}} = state) do
    Process.demonitor(monitor_ref, [:flush])
    {:reply, :ok, grant_next(%{state | owner: nil})}
  end

  def handle_call({:release, _pid, _token}, _from, state) do
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(
        {:DOWN, monitor_ref, :process, _pid, _reason},
        %{owner: {_owner_pid, _owner_token, monitor_ref}} = state
      ) do
    {:noreply, grant_next(%{state | owner: nil})}
  end

  def handle_info({:DOWN, _monitor_ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  defp ensure_started! do
    case GenServer.start(__MODULE__, [], name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  defp grant_next(%{owner: nil, queue: queue} = state) do
    case :queue.out(queue) do
      {{:value, {from, pid, token}}, next_queue} ->
        if Process.alive?(pid) do
          GenServer.reply(from, :ok)
          %{state | owner: monitor_owner(pid, token), queue: next_queue}
        else
          grant_next(%{state | queue: next_queue})
        end

      {:empty, _queue} ->
        state
    end
  end

  defp monitor_owner(pid, token) do
    {pid, token, Process.monitor(pid)}
  end
end
