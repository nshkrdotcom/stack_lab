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
             :fixture_faults,
             :foundation_path
           ]
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
