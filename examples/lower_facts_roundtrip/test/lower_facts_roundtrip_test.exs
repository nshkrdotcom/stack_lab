defmodule StackLab.Examples.LowerFactsRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.Examples.LowerFactsRoundtrip

  test "lower-facts scenario exposes the dedicated Stage-1 readback proof" do
    scenario = LowerFactsRoundtrip.scenario()

    assert scenario.name == :lower_facts_roundtrip

    assert scenario.cases == %{
             generic_readback: %{kind: :generic_readback},
             authorized_mezzanine_readback: %{kind: :authorized_mezzanine_readback},
             unauthorized_mezzanine_readback: %{kind: :unauthorized_mezzanine_readback}
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

  test "authorized mezzanine readback stays execution-keyed and returns unreconciled lower truth" do
    assert {:ok, result} = LowerFactsRoundtrip.exercise(:authorized_mezzanine_readback)

    assert result.case == :authorized_mezzanine_readback
    assert result.operation == :fetch_run
    assert result.source == :lower_run_status
    assert result.freshness == :lower_authoritative_unreconciled
    refute result.operator_actionable?
    assert result.lineage.installation_id == "inst-lower-facts"
    assert result.lineage.execution_id =~ "execution-"
    assert result.run.run_id =~ "run-lower-facts-"
    assert result.run.status == :completed
  end

  test "unauthorized mezzanine readback is denied before lower readback escapes the substrate context" do
    assert {:ok, result} = LowerFactsRoundtrip.exercise(:unauthorized_mezzanine_readback)

    assert result.case == :unauthorized_mezzanine_readback
    assert result.error == :unauthorized_lower_read
  end
end
