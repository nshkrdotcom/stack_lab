defmodule StackLab.Examples.SingleNodeRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.SingleNodeRoundtrip

  test "single-node scenario exposes the real same-node proof surface" do
    scenario = SingleNodeRoundtrip.scenario()

    assert scenario.name == :single_node_roundtrip
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
    assert Map.has_key?(scenario.cases, :acceptance)
    assert Map.has_key?(scenario.cases, :duplicate)
    assert Map.has_key?(scenario.cases, :scope_rejection)
  end

  test "acceptance case drives a real Citadel outbox entry into durable Spine acceptance" do
    assert {:ok, result} = SingleNodeRoundtrip.exercise(:acceptance)

    assert result.case == :acceptance
    assert result.transport.status == :accepted
    assert result.citadel.replay_status == :submission_accepted
    assert result.citadel.submission_key == result.spine.submission_key
    assert result.citadel.submission_receipt_ref == result.spine.submission_receipt_ref
    assert result.runtime_inputs.workspace_root == result.scope.workspace_root
  end

  test "duplicate case preserves one durable Spine submission while Citadel accepts both entries" do
    assert {:ok, result} = SingleNodeRoundtrip.exercise(:duplicate)

    assert result.case == :duplicate
    assert result.first.transport.status == :accepted
    assert result.second.transport.status == :duplicate
    assert result.first.citadel.submission_key == result.second.citadel.submission_key

    assert result.first.citadel.submission_receipt_ref ==
             result.second.citadel.submission_receipt_ref

    assert result.ledger.submission_key == result.first.citadel.submission_key
  end

  test "scope rejection case returns a typed Spine rejection and supersedes the Citadel entry" do
    assert {:ok, result} = SingleNodeRoundtrip.exercise(:scope_rejection)

    assert result.case == :scope_rejection
    assert result.transport.rejection_family == :scope_unresolvable
    assert result.transport.reason_code == "workspace_ref_unresolved"
    assert result.citadel.replay_status == :superseded
    assert result.citadel.last_error_code == "workspace_ref_unresolved"
    assert result.citadel.has_redecision_entry
  end
end
