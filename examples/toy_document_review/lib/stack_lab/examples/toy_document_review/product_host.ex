defmodule StackLab.Examples.ToyDocumentReview.ProductHost do
  @moduledoc false

  alias StackLab.Examples.ToyDocumentReview.Pack

  @required_components [
    :pack_compiler,
    :config_registry,
    :jido_manifest_lookup,
    :citadel_authority,
    :credential_lease,
    :binding_resolver,
    :lower_invocation,
    :receipt_creation
  ]

  @phase5_components @required_components ++
                       [
                         :generic_receipt_reduction,
                         :production_projection_mapping,
                         :mezzanine_execution_record_emission,
                         :aitrace_causal_replay
                       ]

  @phase5_replay_event_kinds [
    :command_recorded,
    :workflow_started,
    :operation_requested,
    :jido_manifest_resolved,
    :credential_lease_materialized,
    :effect_requested,
    :effect_receipted,
    :receipt_reduced,
    :evidence_attached,
    :review_opened,
    :projection_updated,
    :replay_exported
  ]

  @full_acceptance_components [
    :appkit_role_ref_boundary,
    :pack_compiler,
    :config_registry,
    :jido_manifest_lookup,
    :citadel_authority,
    :credential_lease,
    :binding_resolver,
    :lower_invocation,
    :execution_plane_dispatch_plan,
    :receipt_creation,
    :generic_receipt_reduction,
    :production_projection_mapping,
    :mezzanine_execution_record_emission,
    :aitrace_causal_replay,
    :aitrace_full_replay_gate
  ]

  @stacklab_detailed_event_kinds [
    :operation_requested,
    :effect_requested,
    :effect_receipted,
    :receipt_reduced,
    :projection_updated
  ]

  @execution_route_ref "generic_substrate:v1"

  @extravaganza_required_field_groups %{
    standard_envelope: [
      :ok,
      :schema,
      :operation,
      :trace_id,
      :execution_route_ref,
      :idempotency_key,
      :runtime_profile_ref,
      :data,
      :refs,
      :warnings,
      :generated_at
    ],
    refs: [
      :subject_ref,
      :run_ref,
      :workflow_ref,
      :runtime_profile_ref,
      :authority_ref,
      :decision_ref,
      :connector_manifest_ref,
      :capability_negotiation_ref,
      :lower_request_ref,
      :lower_receipt_ref,
      :source_publication_ref,
      :evidence_chain_ref,
      :event_page_ref,
      :execution_route_ref,
      :idempotency_key
    ],
    run_detail_runtime_row: [
      :subject_ref,
      :run_ref,
      :execution_ref,
      :workflow_ref,
      :state,
      :status_reason,
      :updated_at,
      :session_ref,
      :workspace_ref,
      :token_totals
    ],
    provider_request_response: [
      :provider,
      :operation,
      :provider_request_ref,
      :provider_response_ref,
      :provider_request_sent?,
      :provider_response_received?,
      :receipt_recorded?,
      :raw_material_present?
    ],
    lower_receipt: [:lower_receipt_ref, :attempt_ref, :status],
    event_page_entry: [
      :event_ref,
      :event_seq,
      :event_kind,
      :observed_at,
      :run_ref,
      :subject_ref,
      :attempt_ref,
      :extensions
    ]
  }

  @operation_bindings [
    source_read: %{
      binding_ref: "document_source",
      binding_kind: :source,
      operation_role: "read",
      operation_class: :source_read,
      capability: "document_source_read"
    },
    source_publication: %{
      binding_ref: "review_publication",
      binding_kind: :source_publication,
      operation_role: "publish",
      operation_class: :source_write,
      capability: "review_publication"
    },
    runtime: %{
      binding_ref: "review_runtime",
      binding_kind: :runtime,
      operation_role: "run",
      operation_class: :runtime_session,
      capability: "review_runtime"
    },
    runtime_tool: %{
      binding_ref: "review_extract_tool",
      binding_kind: :runtime_tool,
      operation_role: "lookup",
      operation_class: :runtime_tool_invocation,
      capability: "review_extract_tool"
    },
    evidence: %{
      binding_ref: "review_evidence",
      binding_kind: :evidence,
      operation_role: "collect",
      operation_class: :evidence_collection,
      capability: "review_evidence"
    },
    resource_effect: %{
      binding_ref: "archive_effect",
      binding_kind: :resource_effect,
      operation_role: "archive",
      operation_class: :resource_effect,
      capability: "archive_document"
    }
  ]

  @forbidden_neutral_terms [
    "Extra" <> "vaganza",
    "Lin" <> "ear",
    "Git" <> "Hub",
    "Co" <> "dex",
    "Sym" <> "phony"
  ]

  def scenario do
    %{
      name: :toy_document_review,
      pack_slug: Pack.pack_slug(),
      deterministic_command: "mix stack_lab.proof_app.toy_document_review.acceptance --json",
      live_profiles: [],
      cases: %{
        full_neutral_acceptance: %{kind: :deterministic_full_acceptance},
        foundation_path: %{kind: :deterministic_foundation},
        content_shape_gate: %{kind: :deterministic_content_shape_gate},
        content_store_acceptance: %{kind: :deterministic_content_store_acceptance},
        operation_graph_gate: %{kind: :deterministic_operation_graph_gate},
        receipt_projection_replay: %{kind: :deterministic_receipt_projection_replay},
        fixture_faults: %{kind: :local_http_fault_matrix},
        bypass_rejections: %{kind: :required_component_rejections}
      }
    }
  end

  def required_components, do: @required_components
  def phase5_components, do: @phase5_components
  def phase5_replay_event_kinds, do: @phase5_replay_event_kinds
  def full_acceptance_components, do: @full_acceptance_components
  def stacklab_detailed_event_kinds, do: @stacklab_detailed_event_kinds
  def execution_route_ref, do: @execution_route_ref
  def extravaganza_required_field_groups, do: @extravaganza_required_field_groups
  def operation_bindings, do: @operation_bindings
  def forbidden_neutral_terms, do: @forbidden_neutral_terms

  def source_inputs do
    [
      %{
        input_kind: :uploaded_document_source,
        source_ref: "upload://toy-document-review/doc-001",
        subject_ref: "subject://toy-document-review/doc-001",
        external_state: "submitted",
        payload_ref: "payload://toy-document-review/uploaded-document/doc-001"
      },
      %{
        input_kind: :event_style_review_update,
        source_ref: "event://toy-document-review/3",
        subject_ref: "subject://toy-document-review/doc-001",
        external_state: "review.completed",
        payload_ref: "payload://toy-document-review/event/review-completed/doc-001"
      }
    ]
  end

  def state_mapping do
    %{
      "submitted" => %{source_state: :open, workflow_state: :submitted},
      "review.started" => %{source_state: :active, workflow_state: :reviewing},
      "review.completed" => %{source_state: :terminal, workflow_state: :reviewed},
      "archived" => %{source_state: :terminal, workflow_state: :archived},
      "expired" => %{source_state: :terminal, workflow_state: :expired}
    }
  end
end
