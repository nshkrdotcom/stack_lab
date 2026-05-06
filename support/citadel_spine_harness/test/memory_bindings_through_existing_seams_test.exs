defmodule StackLab.CitadelSpineHarness.MemoryBindingsThroughExistingSeamsTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "Scenario 28 keeps memory integrations on the frozen execution, context, subject, and observer seams" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_memory_bindings_through_existing_seams(
               :memory_bindings_through_existing_seams
             )

    assert result.case == :memory_bindings_through_existing_seams

    assert result.installation.external_system_ref == "hindsight.primary"
    assert result.installation.binding_count == 4

    assert result.installation.attachments == [
             "jido_integration.audit_subscriber",
             "mezzanine.execution_recipe",
             "mezzanine.subject_kind",
             "outer_brain.context_adapter"
           ]

    assert result.context.success.trace_id == "trace-stage14-memory-runtime"
    assert result.context.success.status == :ok
    assert result.context.success.fragment_count == 1
    assert result.context.success.fragment_provenance["source_ref"] == "workspace_memory"
    assert result.context.success.fragment_provenance["binding_key"] == "workspace_memory"
    assert result.context.success.fragment_provenance["adapter_key"] == "hindsight_context"

    assert result.context.success.fragment_provenance["external_system_ref"] ==
             "hindsight.primary"

    assert result.context.degraded.trace_id == "trace-stage14-memory-runtime"
    assert result.context.degraded.status == :degraded
    assert result.context.degraded.error == :timeout

    assert result.inference.dispatch.trace_id == "trace-stage14-memory-runtime"
    assert result.inference.dispatch.runtime_class == "inference"
    assert result.inference.dispatch.placement_ref == "memory_reasoner"
    assert result.inference.dispatch.descriptor_attachment == "mezzanine.execution_recipe"
    assert result.inference.dispatch.external_system_ref == "hindsight.primary"
    assert result.inference.dispatch.workflow_handoff_count == 1

    assert result.inference.outcome.dispatch_state == :failed
    assert result.inference.outcome.failure_kind == :semantic_failure

    assert result.inference.outcome.normalized_outcome == %{
             "error" => %{
               "kind" => "semantic_failure",
               "reason" => "insufficient_context"
             }
           }

    assert result.inference.outcome.subject_state == "needs_correction"
    assert "lifecycle_advanced" in result.inference.outcome.trace_fact_kinds

    assert result.memory_subject.first_execution.trace_id == "trace-stage14-memory-maintenance"
    assert result.memory_subject.first_execution.runtime_class == "inference"
    assert result.memory_subject.retry.retry_execution_count == 1
    assert result.memory_subject.retry.supersession_reason == :retry_semantic
    assert result.memory_subject.retry.subject_state_after_retry == "consolidated"

    assert result.memory_subject.archival.status == :archived
    assert result.memory_subject.archival.hot_subject_row_count == 0
    assert result.memory_subject.archival.bundle_subject_state == "consolidated"
    assert result.memory_subject.archival.bundle_trace_ids == ["trace-stage14-memory-maintenance"]
    assert result.memory_subject.archival.removed.subject == 1
    assert "execution_dispatched" in result.memory_subject.archival.trace_fact_kinds

    assert result.observer.surface == "jido_integration.audit_subscriber"
    assert result.observer.export_count >= 4

    assert result.observer.export_kinds == [
             "artifact.recorded",
             "attempt.recorded",
             "event.appended",
             "run.accepted"
           ]

    assert result.observer.trace_ids == ["trace-stage14-memory-runtime"]
    assert result.observer.tenant_ids == ["tenant-stage14-memory"]
    assert result.observer.installation_ids == [result.installation.installation_id]
    assert result.observer.staleness == [:live]
    assert result.observer.durable_export_ids?
    assert result.observer.payload_ref_present?

    assert result.boundaries.allowed_binding_families_only?
    assert result.boundaries.no_secondary_binding_plane?
    assert result.boundaries.observer_surface == "jido_integration.audit_subscriber"
  end
end
