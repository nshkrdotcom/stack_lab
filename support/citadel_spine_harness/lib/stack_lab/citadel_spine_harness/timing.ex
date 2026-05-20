defmodule StackLab.CitadelSpineHarness.Timing do
  @moduledoc false

  @default_timeout_ms 2_000
  @default_interval_ms 25

  @spec await_until(atom(), (-> boolean()), keyword()) :: :ok | {:error, map()}
  def await_until(label, predicate, opts \\ [])
      when is_atom(label) and is_function(predicate, 0) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)
    on_timeout = Keyword.get(opts, :on_timeout, :raise)
    deadline_ms = now_ms() + timeout_ms

    do_await_until(label, predicate, deadline_ms, interval_ms, on_timeout, nil)
  end

  @spec delay(atom(), non_neg_integer()) :: :ok
  def delay(label, delay_ms) when is_atom(label) and is_integer(delay_ms) and delay_ms >= 0 do
    sleep(delay_ms)
  end

  @spec soak(atom(), non_neg_integer()) :: :ok
  def soak(label, delay_ms) when is_atom(label) do
    delay(label, delay_ms)
  end

  @spec retry_delay(atom(), non_neg_integer()) :: :ok
  def retry_delay(label, delay_ms) when is_atom(label) do
    delay(label, delay_ms)
  end

  defp do_await_until(label, predicate, deadline_ms, interval_ms, on_timeout, last_result) do
    case predicate.() do
      true ->
        :ok

      false ->
        retry_or_timeout(label, predicate, deadline_ms, interval_ms, on_timeout, false)

      other ->
        retry_or_timeout(
          label,
          predicate,
          deadline_ms,
          interval_ms,
          on_timeout,
          other || last_result
        )
    end
  end

  defp retry_or_timeout(label, predicate, deadline_ms, interval_ms, on_timeout, last_result) do
    remaining_ms = deadline_ms - now_ms()

    if remaining_ms <= 0 do
      timeout(label, on_timeout, last_result)
    else
      retry_delay(label, min(interval_ms, remaining_ms))
      do_await_until(label, predicate, deadline_ms, interval_ms, on_timeout, last_result)
    end
  end

  defp timeout(label, :return_error, last_result) do
    {:error, %{code: :timeout, label: label, last_result: last_result}}
  end

  defp timeout(label, :raise, last_result) do
    raise "timed out waiting for #{label}: last_result=#{inspect(last_result)}"
  end

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp sleep(0), do: :ok
  defp sleep(delay_ms), do: Process.sleep(delay_ms)
end
