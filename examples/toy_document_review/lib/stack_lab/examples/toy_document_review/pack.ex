defmodule StackLab.Examples.ToyDocumentReview.Pack do
  @moduledoc false

  alias Mezzanine.Pack.{
    DecisionSpec,
    EvidenceBinding,
    EvidenceSpec,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    OperatorActionSpec,
    ProjectionSpec,
    ResourceEffectBinding,
    RuntimeBinding,
    SourceBinding,
    SourceKindSpec,
    SourcePublicationBinding,
    SubjectKindSpec,
    ToolBinding
  }

  alias StackLab.Examples.ToyDocumentReview.LocalHttpConnector

  @pack_slug "toy_document_review"
  @version "1.0.1"
  @credential_scope_ref LocalHttpConnector.credential_scope_ref()

  def pack_slug, do: @pack_slug
  def version, do: @version

  def manifest(manifest_digest, version \\ @version) when is_binary(manifest_digest) do
    %Manifest{
      pack_slug: @pack_slug,
      version: version,
      description: "Neutral document review product pack for generic substrate proof",
      profile_slots: profile_slots(),
      subject_kind_specs: [
        %SubjectKindSpec{
          name: "review_document",
          description: "Document requiring deterministic review"
        }
      ],
      source_kind_specs: [
        %SourceKindSpec{
          name: "document_feed",
          subject_kind: "review_document",
          description: "Local HTTP document feed"
        }
      ],
      binding_specs: binding_specs(manifest_digest),
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: "review_document",
          initial_state: "submitted",
          terminal_states: ["archived", "expired"],
          transitions: [
            %{from: "submitted", to: "reviewing", trigger: {:execution_requested, "review_run"}},
            %{from: "reviewing", to: "reviewed", trigger: {:execution_completed, "review_run"}},
            %{
              from: "reviewed",
              to: "expired",
              trigger: {:decision_made, "operator_summary", :expired}
            },
            %{from: "reviewed", to: "archived", trigger: {:operator_action, "archive_document"}}
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: "review_run",
          runtime_class: :session,
          placement_ref: "review_runtime",
          workspace_policy: %{strategy: :none},
          sandbox_policy_ref: "sandbox://toy-document-review/local",
          prompt_refs: ["prompt://toy-document-review/review"],
          applicable_to: ["review_document"]
        }
      ],
      decision_specs: [
        %DecisionSpec{
          decision_kind: "operator_summary",
          trigger: {:on_subject_entered_state, "reviewed"},
          required_evidence_kinds: ["review_report"],
          authorized_actors: ["role://toy-document-review/operator"],
          allowed_decisions: [:accept, :reject, :expired],
          required_within_hours: 24
        }
      ],
      evidence_specs: [
        %EvidenceSpec{
          evidence_kind: "review_report",
          collector_ref: "review_evidence",
          collection_strategy: :automatic,
          collected_on: {:execution_completed, "review_run"},
          schema: %{"artifact_kind" => "review_report"}
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: "document_review_queue", subject_kinds: ["review_document"]}
      ],
      operator_action_specs: [
        %OperatorActionSpec{
          action_kind: "archive_document",
          description: "Archive a reviewed document through the resource effect binding",
          applicable_states: ["reviewed"],
          authorized_roles: ["toy_document_review_operator"],
          effect: {:dispatch_effect, "archive_document"}
        }
      ]
    }
  end

  defp binding_specs(manifest_digest) do
    [
      %SourceBinding{
        binding_ref: "document_source",
        source_kind: "document_feed",
        subject_kind: "review_document",
        connector_ref: LocalHttpConnector.connector_ref(),
        manifest_ref: LocalHttpConnector.manifest_ref(),
        operation_refs: %{read: "toy.documents.read"},
        credential_binding_ref: @credential_scope_ref,
        adapter_ref: "adapter://toy-document-review/source",
        connection_ref: "connection://toy-document-review/local-http",
        projection_profile_ref: "projection://toy-document-review/source",
        retry_policy_ref: "retry://toy-document-review/read",
        metadata:
          metadata(manifest_digest, %{read: :source_read}, %{read: :read}, %{
            read: ["documents:read"]
          })
      },
      %SourcePublicationBinding{
        binding_ref: "review_publication",
        source_binding_ref: "document_source",
        connector_ref: LocalHttpConnector.connector_ref(),
        manifest_ref: LocalHttpConnector.manifest_ref(),
        operation_refs: %{publish: "toy.reviews.publish"},
        credential_binding_ref: @credential_scope_ref,
        template_ref: "template://toy-document-review/review-summary",
        publication_profile_ref: "publication://toy-document-review/review",
        retry_policy_ref: "retry://toy-document-review/write",
        metadata:
          metadata(manifest_digest, %{publish: :source_write}, %{publish: :write}, %{
            publish: ["documents:write"]
          })
      },
      %RuntimeBinding{
        binding_ref: "review_runtime",
        runtime_family: :direct,
        connector_ref: LocalHttpConnector.connector_ref(),
        manifest_ref: LocalHttpConnector.manifest_ref(),
        operation_refs: %{run: "toy.review.run"},
        credential_binding_ref: @credential_scope_ref,
        session_policy_ref: "session://toy-document-review/direct",
        retry_policy_ref: "retry://toy-document-review/runtime",
        metadata:
          metadata(manifest_digest, %{run: :runtime_session}, %{run: :write}, %{
            run: ["reviews:run"]
          })
      },
      %ToolBinding{
        binding_ref: "review_extract_tool",
        runtime_binding_ref: "review_runtime",
        connector_ref: LocalHttpConnector.connector_ref(),
        manifest_ref: LocalHttpConnector.manifest_ref(),
        operation_refs: %{lookup: "toy.review.extract"},
        authorization_class: "runtime_tool_invocation",
        credential_binding_ref: @credential_scope_ref,
        tool_schema_ref: "schema://toy-document-review/tool/extract",
        input_policy_ref: "input-policy://toy-document-review/tool/extract",
        retry_policy_ref: "retry://toy-document-review/tool",
        metadata:
          metadata(
            manifest_digest,
            %{lookup: :runtime_tool_invocation},
            %{lookup: :read},
            %{lookup: ["documents:read"]}
          )
      },
      %EvidenceBinding{
        binding_ref: "review_evidence",
        evidence_kind: "review_report",
        connector_ref: LocalHttpConnector.connector_ref(),
        manifest_ref: LocalHttpConnector.manifest_ref(),
        operation_refs: %{collect: "toy.evidence.collect"},
        credential_binding_ref: @credential_scope_ref,
        collection_policy_ref: "evidence-policy://toy-document-review/review-report",
        retry_policy_ref: "retry://toy-document-review/evidence",
        metadata:
          metadata(manifest_digest, %{collect: :evidence_collection}, %{collect: :read}, %{
            collect: ["evidence:read"]
          })
      },
      %ResourceEffectBinding{
        binding_ref: "archive_effect",
        effect_kind: "archive_document",
        connector_ref: LocalHttpConnector.connector_ref(),
        manifest_ref: LocalHttpConnector.manifest_ref(),
        operation_refs: %{archive: "toy.document.archive"},
        operation_group_ref: "operation-group://toy-document-review/archive",
        credential_binding_ref: @credential_scope_ref,
        confirmation_policy_ref: "confirmation-policy://toy-document-review/archive",
        retry_policy_ref: "retry://toy-document-review/archive",
        metadata:
          metadata(manifest_digest, %{archive: :resource_effect}, %{archive: :write}, %{
            archive: ["effects:write"]
          })
      }
    ]
  end

  defp metadata(manifest_digest, operation_classes, side_effect_classes, required_scopes) do
    %{
      manifest_digest: manifest_digest,
      operation_classes: operation_classes,
      side_effect_classes: side_effect_classes,
      required_scopes: required_scopes
    }
  end

  defp profile_slots do
    %{
      source_profile_ref: {:custom, "profile://toy-document-review/source"},
      runtime_profile_ref: {:custom, "profile://toy-document-review/runtime"},
      tool_scope_ref: {:custom, "profile://toy-document-review/tools"},
      evidence_profile_ref: {:custom, "profile://toy-document-review/evidence"},
      publication_profile_ref: {:custom, "profile://toy-document-review/publication"},
      review_profile_ref: {:custom, "profile://toy-document-review/review"},
      memory_profile_ref: :none,
      projection_profile_ref: {:custom, "profile://toy-document-review/projection"}
    }
  end
end
