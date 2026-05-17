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
    assert scenario.deterministic_command == "mix test"
    assert scenario.live_profiles == []

    assert Enum.sort(Map.keys(scenario.cases)) == [
             :bypass_rejections,
             :content_shape_gate,
             :fixture_faults,
             :foundation_path,
             :operation_graph_gate
           ]
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
