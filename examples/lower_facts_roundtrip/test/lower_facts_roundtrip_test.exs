defmodule StackLab.Examples.LowerFactsRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.LowerFactsRoundtrip

  test "lower-facts scenario exposes the dedicated Stage-1 readback proof" do
    scenario = LowerFactsRoundtrip.scenario()

    assert scenario.name == :lower_facts_roundtrip

    assert scenario.cases == %{
             generic_readback: %{kind: :generic_readback}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "generic readback returns typed lower facts without operator aggregation" do
    assert {:ok, result} = LowerFactsRoundtrip.exercise(:generic_readback)

    assert result.case == :generic_readback
    assert result.receipt.status == :accepted
    assert result.run.capability_id == "inference.execute"
    assert result.run.status == :completed
    assert result.attempt.listed_attempt_id == result.attempt.fetched_attempt_id
    assert result.attempt.status == :completed

    assert result.events == [
             "inference.request_admitted",
             "inference.attempt_started",
             "inference.attempt_completed"
           ]

    assert result.artifact.run_artifact_ids == [result.artifact.artifact_id]
  end
end
