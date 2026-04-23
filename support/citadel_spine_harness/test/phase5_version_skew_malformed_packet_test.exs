defmodule StackLab.CitadelSpineHarness.Phase5VersionSkewMalformedPacketTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness

  test "describes Phase 5 scenario 209 version-skew malformed-packet proof" do
    scenario = CitadelSpineHarness.phase5_version_skew_malformed_packet_scenario()

    assert scenario.name == :phase5_version_skew_malformed_packet
    assert scenario.runbook == "version_skew_malformed_packet.md"

    assert scenario.cases == %{
             contract_chaos: %{
               kind: :contract_chaos,
               scenario: 209
             }
           }
  end

  test "scenario 209 proves accepted versions and contract-chaos failures fail closed" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_version_skew_malformed_packet(:contract_chaos)

    assert result.case == :contract_chaos
    assert result.scenario == 209
    assert result.owning_milestone =~ "Milestone 7"

    assert result.positive.citadel_invocation_request.schema_version == 2
    assert result.positive.citadel_invocation_request.bridge_acceptance_status == :accepted

    assert result.positive.citadel_invocation_request.execution_intent_invocation_schema_version ==
             2

    assert result.positive.citadel_invocation_request.schema_hash =~ ~r/\Asha256:[0-9a-f]{64}\z/

    assert result.positive.mezzanine_operator_workflow_signal.schema_version ==
             "Mezzanine.OperatorWorkflowSignal.v1"

    assert result.positive.mezzanine_operator_workflow_signal.signal_version ==
             "operator-cancel.v1"

    assert result.positive.mezzanine_operator_workflow_signal.ordering_state == "applied"
    assert result.positive.mezzanine_operator_workflow_signal.workflow_mode == "cancel_requested"

    failure = result.negative_failures.missing_required_and_unknown_field_precedence
    assert failure.primary_classification == :missing_required_fields
    assert failure.secondary_classifications == [:unknown_critical_fields]
    assert failure.field_policy_precedence == :missing_required_fields_before_unknown_fields
    assert failure.observed_field_violations.missing_required_fields == [:schema_version]
    assert failure.observed_field_violations.unknown_extension_namespaces == ["unknown_critical"]
    refute failure.accepted?

    assert result.negative_failures.malformed_schema_version.result ==
             {:error, :malformed_schema_version}

    assert result.negative_failures.downgraded_schema_version.result ==
             {:error, :downgrade_version}

    assert result.negative_failures.future_schema_version.result ==
             {:error, :unknown_future_version}

    assert result.negative_failures.stale_schema_hash.result ==
             {:error, :schema_hash_outside_accepted_hash_set}

    assert result.negative_failures.invocation_bridge_transition_window.result ==
             {:error, :unsupported_transition_window}

    assert result.negative_failures.legacy_v1_bridge_entry.result ==
             {:error, :legacy_v1_not_a_bridge_entrypoint}

    assert result.negative_failures.missing_signal_version_old_shape.last_signal_error ==
             {:missing_required_fields, [:signal_version]}

    refute result.negative_failures.missing_signal_version_old_shape.ordered_signal_applied?

    assert result.negative_failures.unregistered_or_stale_signal_version.result ==
             {:error, {:unregistered_signal, "operator.cancel", "operator-cancel.v0"}}

    assert result.negative_failures.operator_signal_stale_schema_hash.result ==
             {:error, :schema_hash_outside_accepted_hash_set}

    assert result.negative_failures.brain_ingress_old_shape_without_pin.result ==
             {:error, :missing_active_workflow_ingress_pin}

    assert result.negative_failures.brain_ingress_old_shape_without_pin.enforcement_point ==
             :before_ledger_acceptance

    assert result.brain_ingress_source_scan.workflow_bound_entrypoints == []
    refute result.brain_ingress_source_scan.current_workflow_bound_old_shape_intake?

    assert result.contract_home_evidence.canonical_producer_exists?
    assert result.contract_home_evidence.citadel_local_slice_disposition == :welded_internal_slice
    assert result.contract_home_evidence.citadel_welded_slice_exists?

    assert result.contract_home_evidence.retired_contracts_publishable_paths == []

    refute result.contract_home_evidence.independent_consumer_contract_fork?

    refute result.stop_condition_evidence.scenario_209_first_proof_deferred_to_milestone_10?
    refute result.stop_condition_evidence.accepted_any_negative_failure?
    refute result.stop_condition_evidence.unknown_field_primary_when_missing_required?
    refute result.stop_condition_evidence.active_workflow_old_shape_without_pin_accepted?
  end
end
