defmodule StackLab.ReplayRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.ReplayRoundtrip

  test "clean replay suppresses side effects and projects replay bundle refs" do
    assert {:ok, receipt} = ReplayRoundtrip.run()

    assert receipt.side_effects_invoked? == false
    assert receipt.bundle_projection.decision_class == :clean
    assert receipt.agent_evidence_export.ledger_ref =~ "agent-ledger://stack-lab/replay/"
    assert receipt.agent_evidence_export.runtime_receipt_refs != []

    assert receipt.agent_evidence_export.redaction_manifest_ref ==
             "redaction://stack-lab/replay-roundtrip/default"

    assert receipt.agent_evidence_export.event_count == 3
    assert receipt.agent_evidence_export.payload_hash |> String.starts_with?("sha256:")
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

  test "agent evidence export fails closed for missing sequence" do
    assert {:error, {:missing_replay_sequence, %{from_seq: 10, to_seq: 12, event_count: 2}}} =
             ReplayRoundtrip.run(%{
               agent_events: [
                 %{
                   event_ref: "agent-event://stack-lab/replay/10",
                   event_kind: :conversation,
                   seq: 10
                 },
                 %{
                   event_ref: "agent-event://stack-lab/replay/12",
                   event_kind: :projection,
                   seq: 12
                 }
               ]
             })
  end
end
