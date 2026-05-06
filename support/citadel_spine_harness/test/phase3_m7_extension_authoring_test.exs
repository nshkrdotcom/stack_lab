defmodule StackLab.CitadelSpineHarness.Phase3M7ExtensionAuthoringTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "Scenario 34 proves internal/operator bundle authoring and activation failure gates" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_extension_authoring(:activation_failure_matrix)

    assert result.scenario == 34
    assert result.runbook == "pack_activation_failure.md"

    assert result.valid.status == :active
    assert result.valid.bundle_id == "bundle-stacklab-valid"
    assert result.valid.installation_revision == 1

    assert result.rejections.checksum == :checksum_mismatch
    assert result.rejections.signature == :signature_mismatch
    assert result.rejections.policy_ref == :invalid_policy_ref
    assert result.rejections.platform_migration == :pack_authored_platform_migration
    assert result.rejections.lifecycle_hint == :missing_lifecycle_hints
    assert result.rejections.context_adapter == :unknown_context_adapter

    assert result.stale_revision.status == :stale_revision
    assert result.stale_revision.attempted_revision == 0
    assert result.stale_revision.current_revision == 1

    assert result.absence.pack_authored_platform_migrations == :rejected_before_activation
  end
end
