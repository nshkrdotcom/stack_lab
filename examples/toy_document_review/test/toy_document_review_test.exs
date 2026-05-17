defmodule StackLab.Examples.ToyDocumentReviewTest do
  use StackLab.Examples.ToyDocumentReview.DataCase, async: false

  alias StackLab.Examples.ToyDocumentReview
  alias StackLab.Examples.ToyDocumentReview.LocalHttpService

  setup do
    service = start_supervised!({LocalHttpService, []})
    %{service: service}
  end

  test "scenario exposes deterministic proof ownership" do
    scenario = ToyDocumentReview.scenario()

    assert scenario.name == :toy_document_review
    assert scenario.pack_slug == "toy_document_review"

    assert scenario.deterministic_command ==
             "mix stack_lab.proof_app.toy_document_review.acceptance --json"

    assert scenario.live_profiles == []

    assert Enum.sort(Map.keys(scenario.cases)) == [
             :bypass_rejections,
             :content_shape_gate,
             :content_store_acceptance,
             :fixture_faults,
             :foundation_path,
             :full_neutral_acceptance,
             :operation_graph_gate,
             :receipt_projection_replay
           ]
  end

  test "source inputs and state mapping cover upload and event-style updates" do
    assert [
             %{input_kind: :uploaded_document_source, external_state: "submitted"},
             %{input_kind: :event_style_review_update, external_state: "review.completed"}
           ] = ToyDocumentReview.source_inputs()

    assert ToyDocumentReview.state_mapping()["submitted"] == %{
             source_state: :open,
             workflow_state: :submitted
           }

    assert ToyDocumentReview.state_mapping()["review.completed"] == %{
             source_state: :terminal,
             workflow_state: :reviewed
           }
  end

  test "content shape gate measures payloads results and keeps content storage hypotheses blocked" do
    proof = ToyDocumentReview.run_content_shape_gate()

    assert proof.gate == :content_store_shape
    assert proof.fixture == :toy_document_review
    assert proof.payload_count == 6
    assert proof.result_count == 8
    assert proof.streaming_occurrence_count == 0
    assert proof.storage_modes_observed == [:inline]
    assert proof.largest_observed_byte_size < proof.inline_threshold_bytes

    assert proof.source_categories.provider_response == 3
    assert proof.source_categories.product_authored_content == 6
    assert proof.source_categories.normalized_platform_record == 3
    assert proof.source_categories.operator_visible_output == 2

    assert proof.acceptance.default_inline_threshold_accepted?
    refute proof.acceptance.production_content_addressed_load_bearing?
    refute proof.acceptance.production_streaming_load_bearing?

    assert proof.acceptance.backend_decision == :inline_until_real_payloads_exceed_threshold
    assert :operation_receipt in proof.acceptance.retention_refs_required
    assert :projection in proof.acceptance.retention_refs_required

    assert Enum.all?(proof.redaction_schema_requirements, &is_binary(&1.schema_ref))
    assert Enum.all?(proof.redaction_schema_requirements, &is_binary(&1.redaction_ref))
  end

  test "content store acceptance proves deterministic refs and blocked production backends" do
    proof = ToyDocumentReview.run_content_store_acceptance()

    assert proof.gate == :content_store_acceptance
    assert proof.fixture == :toy_document_review

    assert proof.content_shape_gate.storage_modes_observed == [:inline]
    assert proof.content_shape_gate.inline_threshold_accepted?
    refute proof.content_shape_gate.production_content_addressed_load_bearing?
    refute proof.content_shape_gate.production_streaming_load_bearing?

    assert proof.content_shape_gate.backend_decision ==
             :inline_until_real_payloads_exceed_threshold

    assert proof.envelope_contracts.inline_payload_storage_mode == :inline
    assert proof.envelope_contracts.content_addressed_result_storage_mode == :content_addressed
    assert proof.envelope_contracts.stream_payload_storage_mode == :stream
    assert String.starts_with?(proof.envelope_contracts.content_result_hash, "sha256:")
    assert String.starts_with?(proof.envelope_contracts.content_result_ref, "content://")
    assert String.starts_with?(proof.envelope_contracts.stream_payload_ref, "stream://")

    assert proof.projection_access.inline_readback_mode == :inline_redacted
    assert proof.projection_access.inline_data_visible?
    assert proof.projection_access.content_addressed_readback_mode == :content_store_ref
    refute proof.projection_access.content_addressed_data_visible?
    assert proof.projection_access.stream_readback_mode == :stream_ref
    refute proof.projection_access.stream_data_visible?

    assert proof.content_store_contract.deterministic_content_ref_resolved?
    assert proof.content_store_contract.cross_tenant_denied?
    assert proof.content_store_contract.retained_delete_denied?

    assert proof.content_store_contract.deterministic_content_hash ==
             proof.envelope_contracts.content_result_hash

    assert proof.final_decision ==
             :content_addressed_and_streaming_backend_blocked_until_measured_payloads_require_it
  end

  test "operation graph gate proves parallel joins review gates optional failure and policies" do
    assert {:ok, proof} = ToyDocumentReview.run_operation_graph_gate()

    refs = StackLab.Examples.ToyDocumentReview.OperationGraphGate.node_refs()

    assert proof.graph.node_count == 6

    assert proof.graph.dependency_relations == [
             :blocks_on_confirmation,
             :blocks_on_review,
             :blocks_on_success,
             :parallel_allowed
           ]

    assert proof.initial_ready_node_refs == [
             refs.document_source,
             refs.review_extract_tool
           ]

    assert proof.one_branch_ready_node_refs == [refs.review_extract_tool]
    assert proof.alternate_completion_orders.converge?

    assert proof.alternate_completion_orders.source_first_ready_node_refs == [
             refs.review_runtime
           ]

    assert proof.alternate_completion_orders.tool_first_ready_node_refs == [
             refs.review_runtime
           ]

    assert proof.review_confirmation_gate.before_review_ready_node_refs == [
             refs.review_evidence
           ]

    assert proof.review_confirmation_gate.before_confirmation_ready_node_refs == [
             refs.review_evidence
           ]

    assert proof.review_confirmation_gate.after_confirmation_ready_node_refs == [
             refs.review_publication
           ]

    assert proof.optional_branch_failure.failed_node_ref == refs.review_evidence
    assert proof.optional_branch_failure.allows_publication?

    assert proof.concurrent_runtime_evidence_branch.source_done_ready_node_refs == [
             refs.review_runtime,
             refs.review_evidence
           ]

    assert proof.concurrent_runtime_evidence_branch.runtime_first_ready_node_refs == [
             refs.review_evidence
           ]

    assert proof.concurrent_runtime_evidence_branch.evidence_first_ready_node_refs == [
             refs.review_runtime
           ]

    assert proof.concurrent_runtime_evidence_branch.both_done_ready_node_refs == [
             refs.review_publication
           ]

    assert proof.concurrent_runtime_evidence_branch.alternate_completion_orders_converge?

    assert proof.retry_cancellation_exclusion.retry_ready_node_refs == []
    assert proof.retry_cancellation_exclusion.canceled_ready_node_refs == []

    assert [intent] = proof.publication_activity_intents
    assert intent.node_ref == refs.review_publication
    assert intent.operation_context_ref == "operation-context://toy-document-review/graph-gate"
    assert intent.operation_plan_ref == "operation-plan://toy-document-review/review-publication"

    assert intent.predecessor_event_refs == [
             "event://toy-document-review/review_runtime/succeeded",
             "event://toy-document-review/review-runtime/reviewed",
             "event://toy-document-review/review-runtime/confirmed",
             "event://toy-document-review/review_evidence/failed"
           ]

    assert intent.retry_policy == %{max_attempts: 2, backoff: :linear}
    assert intent.timeout_policy == %{timeout_ms: 30_000}

    assert intent.cancellation_policy == %{
             cancellation_scope_ref: "cancel://toy-document-review/review-run"
           }
  end

  test "foundation proof crosses pack registry manifest authority lease resolver and receipt path",
       %{service: service} do
    assert {:ok, proof} = ToyDocumentReview.run_foundation_proof(service: service)

    assert proof.pack.compiled?
    assert proof.pack.binding_count == 6
    assert proof.registry.active_binding_epoch > 0
    assert proof.local_http_fixture.supervised?
    assert proof.local_http_fixture.ordered_event_sequences == [1, 2, 3]

    assert proof.component_path == ToyDocumentReview.required_components()

    assert Enum.map(proof.operations, & &1.binding_kind) == [
             :source,
             :source_publication,
             :runtime,
             :runtime_tool,
             :evidence,
             :resource_effect
           ]

    assert Enum.all?(proof.operations, & &1.jido_manifest_lookup_used?)
    assert Enum.all?(proof.operations, & &1.citadel_authority_used?)
    assert Enum.all?(proof.operations, & &1.credential_lease_used?)
    assert Enum.all?(proof.operations, & &1.binding_resolver_used?)
    assert Enum.all?(proof.operations, & &1.lower_invocation_used?)
    assert Enum.all?(proof.operations, &(&1.receipt_status == :succeeded))

    assert Enum.all?(
             proof.operations,
             &match?(%Mezzanine.Substrate.OperationReceipt{}, &1.operation_receipt)
           )
  end

  test "receipt projection replay preflight requires production reducer projection outbox and replay" do
    preflight = ToyDocumentReview.receipt_projection_replay_preflight()

    assert preflight.gate == :phase5_toy_receipt_projection_replay_preflight
    assert preflight.accepted?
    assert preflight.blocked_components == []
    assert preflight.components.generic_receipt_reduction
    assert preflight.components.production_projection_mapping
    assert preflight.components.mezzanine_execution_record_emission
    assert preflight.components.aitrace_causal_replay

    assert preflight.required_path == [
             :pack_compiler,
             :config_registry,
             :jido_manifest_lookup,
             :citadel_authority,
             :credential_lease,
             :binding_resolver,
             :lower_invocation,
             :receipt_creation,
             :generic_receipt_reduction,
             :production_projection_mapping,
             :mezzanine_execution_record_emission,
             :aitrace_causal_replay
           ]
  end

  test "receipt projection replay proof crosses production reducer and AITrace proof profile",
       %{service: service} do
    assert {:ok, proof} = ToyDocumentReview.run_receipt_projection_replay_proof(service: service)

    assert proof.preflight.accepted?
    assert proof.reducer_module == Mezzanine.Projections.ReceiptReducer
    assert proof.projection_module == Mezzanine.Projections.SubjectRuntimeProjection

    assert proof.projection.status == :succeeded
    assert proof.projection.operation_count == 6

    assert proof.projection.operation_roles == [
             :source,
             :publication,
             :runtime,
             :evidence,
             :tool,
             :resource_effect
           ]

    assert proof.projection.evidence_count == 1
    assert proof.projection.source_publication_count == 1
    assert proof.projection.resource_effect_count == 1
    assert proof.projection.provider_fact_count == 6
    assert proof.lower_receipt_summary.status == :succeeded
    assert proof.lower_receipt_summary.operation_count == 6

    assert proof.lineage.event_kinds == [
             :command_recorded,
             :credential_lease_materialized,
             :effect_receipted,
             :effect_requested,
             :evidence_attached,
             :jido_manifest_resolved,
             :operation_requested,
             :projection_updated,
             :receipt_reduced,
             :replay_exported,
             :review_opened,
             :workflow_started
           ]

    assert proof.lineage.trace_levels == [:core_lineage, :detailed_proof, :replay_minimum]
    assert [_projection_event_ref] = proof.lineage.projection_visible_event_refs

    assert proof.aitrace_replay.replay_complete?
    refute proof.aitrace_replay.projection_diverged?
    assert proof.aitrace_replay.trace_profile == :stacklab_proof
    assert proof.aitrace_replay.required_trace_level == :detailed_proof

    assert proof.product_shape_comparison.accepted?
    assert proof.product_shape_comparison.generic_fact_coverage.operation_roles_complete?
    assert proof.product_shape_comparison.generic_fact_coverage.provider_object_refs_present?
    assert proof.product_shape_comparison.generic_fact_coverage.provider_facts_present?
    assert proof.product_shape_comparison.generic_fact_coverage.lower_receipt_summary_present?
    assert proof.product_shape_comparison.generic_fact_coverage.result_access_summaries_present?
    assert proof.product_shape_comparison.generic_fact_coverage.lineage_refs_present?
  end

  test "appkit role-ref probe keeps concrete binding refs below AppKit" do
    assert {:ok, proof} = ToyDocumentReview.appkit_role_ref_probe()

    assert proof.accepted?
    refute proof.concrete_binding_refs_seen?

    assert proof.surfaces == [
             :source_candidates,
             :source_publication,
             :runtime_operation,
             :runtime_tool,
             :evidence_collection,
             :resource_effect,
             :review_opened,
             :trace_replay
           ]

    assert proof.operation_role_refs == [:run, :lookup]
  end

  test "full Gate 3 proof covers out-of-order replay negative controls and delayed export",
       %{service: service} do
    assert {:ok, proof} = ToyDocumentReview.run_full_gate3_proof(service: service)

    assert proof.accepted?
    assert proof.emit_order_replay.replay_complete?
    assert proof.out_of_order_replay.order_diverged?
    refute proof.out_of_order_replay.projection_diverged?
    assert proof.missing_predecessor_negative_control.accepted?
    assert proof.delayed_export_proof.accepted?
    assert proof.retry_out_of_order_receipt_proof.order_diverged?
    refute proof.retry_out_of_order_receipt_proof.projection_diverged?
  end

  test "full neutral acceptance crosses all required implementation layers", %{service: service} do
    assert {:ok, proof} = ToyDocumentReview.run_full_acceptance(service: service)

    assert proof.accepted?
    assert proof.component_path == ToyDocumentReview.full_acceptance_components()
    assert proof.foundation.operation_count == 6
    assert proof.full_gate3.accepted?
    assert proof.neutral_code_scan.accepted?
    refute proof.live_acceptance.required?

    assert proof.execution_plane.accepted?
    assert proof.execution_plane.lower_simulation_configured?
    assert proof.bypass_rejections.missing_manifest_fail_closed?
    assert proof.fault_matrix.pagination_ordered?
  end

  test "local HTTP fixture covers deterministic fault and pagination behavior", %{
    service: service
  } do
    matrix = ToyDocumentReview.fault_matrix(service)

    assert {:error, %{reason: :retryable_failure, retryable?: true}} = matrix.retryable_failure
    assert {:error, %{reason: :terminal_failure, retryable?: false}} = matrix.terminal_failure
    assert {:error, %{reason: :auth_rejected}} = matrix.auth_rejection
    assert {:error, %{reason: :credential_expired, retryable?: true}} = matrix.credential_expiry
    assert {:error, %{reason: :schema_version_mismatch}} = matrix.schema_mismatch
    assert {:error, %{reason: :timeout, retryable?: true}} = matrix.timeout

    assert {:ok, page_one} = matrix.ordered_page_one
    assert {:ok, page_two} = matrix.ordered_page_two

    assert Enum.map(page_one.body.events ++ page_two.body.events, & &1.sequence) == [1, 2, 3]
    assert page_one.body.next_cursor == 2
    assert page_two.body.next_cursor == nil
  end

  test "bypass attempts fail closed before lower invocation is reachable" do
    rejections = ToyDocumentReview.bypass_rejections()

    assert {:error, missing_authority} = rejections.binding_resolver_missing_authority
    assert missing_authority.reason == :missing_authority_decision

    assert {:error, missing_lease} = rejections.binding_resolver_missing_credential_lease
    assert missing_lease.reason == :missing_credential_lease

    assert {:error, {:connector_manifest_missing, "connector://toy-document-review/missing"}} =
             rejections.manifest_lookup_missing_connector

    assert {:error, {:missing_required_components, missing}} =
             rejections.missing_required_component

    assert :config_registry in missing
    assert :receipt_creation in missing
  end
end
