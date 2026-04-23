defmodule StackLab.CitadelSpineHarness.Phase5LineageContextMissingTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness

  test "describes Phase 5 scenario 208 lineage context missing proof" do
    scenario = CitadelSpineHarness.phase5_lineage_context_missing_scenario()

    assert scenario.name == :phase5_lineage_context_missing
    assert scenario.runbook == "lineage_context_missing.md"

    assert scenario.cases == %{
             lineage_context_missing: %{
               kind: :lineage_context_missing,
               scenario: 208
             }
           }
  end

  test "scenario 208 proves envelope lineage and fail-closed missing context evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_lineage_context_missing(:lineage_context_missing)

    assert result.case == :lineage_context_missing
    assert result.scenario == 208
    assert result.runtime_envelope.runtime_class == :source_integration
    assert result.runtime_envelope.expected_local_max_ms == 30_000
    assert result.runtime_envelope.ci_timeout_ms == 60_000
    assert String.starts_with?(result.canonical_idempotency_key, "idem:v1:")

    assert result.positive.minimum_lineage.trace_id == result.trace_id
    assert result.positive.minimum_lineage.tenant_id == result.tenant_id

    assert result.positive.minimum_lineage.canonical_idempotency_key ==
             result.canonical_idempotency_key

    assert result.positive.minimum_lineage.workflow_id == :optional_extended_evidence
    assert result.positive.minimum_lineage.aitrace_span_id == :optional_extended_evidence

    assert result.positive.idempotency_correlation["contract_name"] ==
             "Mezzanine.IdempotencyCorrelationEvidence.v1"

    assert result.positive.idempotency_correlation["canonical_idempotency_key"] ==
             result.canonical_idempotency_key

    assert result.positive.idempotency_correlation["platform_envelope_idempotency_key"] ==
             result.canonical_idempotency_key

    assert result.positive.idempotency_correlation["execution_plane_route_idempotency_key"] ==
             result.canonical_idempotency_key

    assert String.starts_with?(
             result.positive.idempotency_correlation["jido_lower_submission_dedupe_key"],
             "idem:v1:lower_submission:"
           )

    assert result.positive.signal_ingress.lineage.trace_id == result.trace_id

    assert result.positive.signal_ingress.lineage.canonical_idempotency_key ==
             result.canonical_idempotency_key

    assert result.positive.signal_ingress.lineage.source_anchor == %{
             kind: :source_position,
             value: "cursor/208"
           }

    assert result.positive.signal_ingress.source_anchor_recorded == %{
             "kind" => "source_position",
             "value" => "cursor/208"
           }

    assert result.positive.signal_ingress.delivery_order_scope == :partition_fifo
    assert result.positive.signal_ingress.async_handoff?

    assert result.positive.execution_plane.lineage_idempotency_key ==
             result.canonical_idempotency_key

    assert result.positive.execution_plane.envelope_idempotency_key ==
             result.canonical_idempotency_key

    assert result.positive.execution_plane.route_idempotency_key ==
             result.canonical_idempotency_key

    assert result.positive.execution_lineage_store.owner_posture ==
             :audit_owned_durable_lineage_ledger_lookup_index

    assert result.positive.execution_lineage_store.public_lookup == %{
             execution_id: "execution-scenario-208",
             installation_id: "installation-scenario-208",
             subject_id: "subject-scenario-208",
             trace_id: result.trace_id
           }

    assert result.positive.execution_lineage_store.lower_lookup_after_authorization?
    refute result.positive.execution_lineage_store.tenant_authorization_override?
    refute result.positive.execution_lineage_store.workflow_lifecycle_truth?
    refute result.positive.execution_lineage_store.lower_runtime_truth?

    assert String.starts_with?(
             result.positive.semantic_failure.journal_entry_id,
             "semantic_failure_journal:v1:"
           )

    assert result.positive.semantic_failure.journal_identity_payload[
             "canonical_idempotency_key"
           ] == result.canonical_idempotency_key

    assert String.starts_with?(
             result.positive.semantic_failure.semantic_failure_payload_hash,
             "sha256:"
           )

    assert result.positive.semantic_failure.legacy_alias_only?
    refute result.positive.semantic_failure.delimiter_joined_write_key?

    assert result.positive.aitrace.trace_id == result.trace_id
    assert result.positive.aitrace.trace_id_source.kind == :external_alias
    assert result.positive.aitrace.span_id_source.kind == :external_alias
    assert result.positive.aitrace.start_time == nil
    assert %DateTime{} = result.positive.aitrace.start_wall_time
    assert result.positive.aitrace.clock_domain.source == "citadel_trace_envelope"

    assert result.positive.aitrace.lineage.canonical_idempotency_key ==
             result.canonical_idempotency_key

    assert result.positive.aitrace.platform_envelope_field_map.trace_id ==
             "AITrace.Trace.trace_id"

    refute result.positive.aitrace.mandatory_runtime_backend?

    ledger = result.positive.causal_reconstruction_ledger
    assert ledger.product_or_operator_request_ref == "operator-request/scenario-208"
    assert ledger.tenant_id == result.tenant_id
    assert ledger.authority_decision_ref == "authority-decision/scenario-208"
    assert ledger.trace_id == result.trace_id
    assert ledger.causation_id == "operator-request/scenario-208"
    assert ledger.canonical_idempotency_key == result.canonical_idempotency_key
    assert ledger.source_ordering_anchor == "cursor/208"
    assert ledger.idempotency_alias_map_ref == "Mezzanine.IdempotencyCorrelationEvidence.v1"
    assert ledger.workflow_ref == "workflow-scenario-208"

    assert String.starts_with?(
             ledger.lower_submission_ref,
             "idem:v1:lower_submission:"
           )

    assert ledger.execution_plane_route_ref == "route-scenario-208"
    assert ledger.signal_ingress_accepted_ref == result.positive.signal_ingress.accepted_ref
    assert ledger.audit_lineage_lookup == result.positive.execution_lineage_store.public_lookup

    assert ledger.semantic_failure_journal_entry_id ==
             result.positive.semantic_failure.journal_entry_id

    assert String.starts_with?(ledger.aitrace_export_ref, "aitrace://stack_lab/scenario208/")
    assert ledger.release_manifest_ref == "phase5-v7-m5-lineage-context-missing"
    assert ledger.preserved_behavior == :lineage_context_reconstructable

    assert result.negative_failures.missing_trace.reason == :missing_lineage_fields
    assert :trace_id in result.negative_failures.missing_trace.missing_fields
    assert result.negative_failures.missing_trace.safe_action == :reject
    assert result.negative_failures.missing_trace.partition_queue_depths_unchanged?
    refute result.negative_failures.missing_trace.accepted?

    assert result.negative_failures.missing_canonical_root.reason == :missing_lineage_fields

    assert :canonical_idempotency_key in result.negative_failures.missing_canonical_root.missing_fields

    assert result.negative_failures.missing_source_anchor.reason == :missing_lineage_fields

    assert :source_position_or_revision in result.negative_failures.missing_source_anchor.missing_fields

    assert result.negative_failures.regressed_source_anchor.reason ==
             :regressed_source_position_or_revision

    assert result.negative_failures.regressed_source_anchor.safe_action == :reject

    assert result.negative_failures.regressed_source_anchor.previous_source_anchor == %{
             kind: :source_position,
             value: "cursor/208"
           }

    assert result.negative_failures.regressed_source_anchor.current_source_anchor == %{
             kind: :source_position,
             value: "cursor/207"
           }

    refute result.stop_condition_evidence.aitrace_mandatory_runtime_backend?
    refute result.stop_condition_evidence.release_manifest_required_for_runtime_acceptance?
    refute result.stop_condition_evidence.missing_lineage_rejection_only?
    refute result.stop_condition_evidence.silently_minted_causation_or_idempotency?
  end
end
