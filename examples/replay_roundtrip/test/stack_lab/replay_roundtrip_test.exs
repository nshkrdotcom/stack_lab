defmodule StackLab.ReplayRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.ReplayRoundtrip

  test "clean replay suppresses side effects and projects replay bundle refs" do
    assert {:ok, receipt} = ReplayRoundtrip.run()

    assert receipt.side_effects_invoked? == false
    assert receipt.bundle_projection.decision_class == :clean
    assert "EVAL-002" in receipt.fixture_refs
  end

  test "variant replay reports divergence and bounded drift signal" do
    assert {:ok, receipt} =
             ReplayRoundtrip.run(%{
               replay_mode: :guard_variant,
               variant_overrides: %{guard_chain_ref: "guard-chain://candidate"}
             })

    assert receipt.divergence_count == 1
    assert [%{signal_class: :guard_decision_drift}] = receipt.drift_signals
  end
end
