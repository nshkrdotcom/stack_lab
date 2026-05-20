defmodule StackLab.CitadelSpineHarness.TimingTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness.Timing

  test "await_until returns when the named condition is true" do
    assert :ok = Timing.await_until(:already_ready, fn -> true end, timeout_ms: 1)
  end

  test "await_until reports the named unmet condition without raising when requested" do
    assert {:error, %{code: :timeout, label: :never_ready, last_result: false}} =
             Timing.await_until(:never_ready, fn -> false end,
               timeout_ms: 1,
               interval_ms: 1,
               on_timeout: :return_error
             )
  end

  test "named zero delay is a no-op" do
    assert :ok = Timing.delay(:zero_delay_probe, 0)
  end
end
