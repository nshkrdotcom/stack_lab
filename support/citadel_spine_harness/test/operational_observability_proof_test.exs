defmodule StackLab.CitadelSpineHarness.OperationalObservabilityProofTest do
  use ExUnit.Case, async: true

  alias Citadel.ObservabilityContract.{OperationalRunbook, OperationalSLO, OperationalSignal}
  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.OperationalObservabilityProof

  test "Scenario 43 composes deterministic run evidence with operational health evidence" do
    assert {:ok, proof} =
             CitadelSpineHarness.exercise_operational_observability_proof(
               :deterministic_run_health
             )

    assert proof.case == :deterministic_run_health
    assert proof.scenario == 43
    assert proof.deterministic_run_evidence.receipt_contract == "DeterministicRunReceipt.v1"
    assert proof.deterministic_run_evidence.command_refs != []
    assert proof.operational_health.signal_contract == OperationalSignal.contract_name()
    assert proof.operational_health.operator_visibility? == true
    assert proof.aitrace_boundary.replay_dependency? == false
    assert proof.aitrace_boundary.audit_event_emitted? == false
    assert proof.aitrace_boundary.replay_event_emitted? == false

    assert proof.operational_health.signal_refs |> Enum.sort() ==
             OperationalSignal.signal_names()
             |> Enum.map(&"operational-signal://#{&1}")
             |> Enum.sort()

    assert proof.operational_health.slo_threshold_refs |> Enum.sort() ==
             OperationalSLO.thresholds()
             |> Map.values()
             |> Enum.map(& &1.metric_ref)
             |> Enum.sort()

    assert proof.operational_health.runbook_refs |> Enum.sort() ==
             OperationalRunbook.entry_names() |> Enum.sort()

    assert :ok = OperationalObservabilityProof.validate_proof(proof)
  end

  test "operator backend envelopes stay separate from AITrace audit and replay" do
    assert {:ok, proof} =
             OperationalObservabilityProof.run_case(:deterministic_run_health)

    for {_name, envelope} <- proof.operational_health.backend_envelopes do
      assert Map.keys(envelope) |> Enum.sort() == [:log, :metric, :telemetry, :trace]
      refute Map.has_key?(envelope, :audit)
      refute Map.has_key?(envelope, :replay)
      assert envelope.telemetry.backend == :telemetry
      assert envelope.metric.backend == :metric
      assert envelope.log.backend == :log
      assert envelope.trace.backend == :trace
    end
  end

  test "proof validation rejects missing operational health and AITrace boundary coupling" do
    assert {:ok, proof} =
             OperationalObservabilityProof.run_case(:deterministic_run_health)

    assert {:error, :missing_operational_health_evidence} =
             proof
             |> Map.delete(:operational_health)
             |> OperationalObservabilityProof.validate_proof()

    coupled =
      put_in(proof, [:aitrace_boundary, :replay_dependency?], true)

    assert {:error, :aitrace_boundary_not_separate} =
             OperationalObservabilityProof.validate_proof(coupled)
  end
end
