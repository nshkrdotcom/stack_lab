defmodule StackLab.CitadelSpineHarness.Phase5ArtifactReferenceBoundaryTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness

  test "describes Phase 5 scenario 204 artifact reference payload boundary" do
    scenario = CitadelSpineHarness.phase5_artifact_reference_boundary_scenario()

    assert scenario.name == :phase5_artifact_reference_boundary
    assert scenario.runbook == "artifact_reference_payload_bypass.md"

    assert scenario.cases == %{
             payload_boundary_fault_matrix: %{
               kind: :payload_boundary_fault_matrix,
               scenario: 204
             }
           }
  end

  test "scenario 204 proves refs, store failures, timeout, and digest mismatch fail closed" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_artifact_reference_boundary(
               :payload_boundary_fault_matrix
             )

    assert result.case == :payload_boundary_fault_matrix
    assert result.scenario == 204

    assert result.positive.valid_execution_ref.classification == :ref_required
    assert result.positive.valid_execution_ref.content_hash_alg == "sha256"
    assert result.positive.valid_execution_ref.schema_hash_alg == "sha256"
    assert result.positive.valid_reply_ref.preview_byte_size <= 2_048
    assert sha256_ref?(result.positive.valid_reply_ref.body_hash)

    assert result.negative_failures.store_unavailable.safe_action == :unavailable_fail_closed
    assert result.negative_failures.store_unavailable.bytes_accepted? == false
    assert result.negative_failures.fetch_timeout.safe_action == :unavailable_fail_closed
    assert result.negative_failures.fetch_timeout.bytes_accepted? == false
    assert result.negative_failures.digest_mismatch.safe_action == :quarantine_digest_mismatch
    assert result.negative_failures.digest_mismatch.bytes_accepted? == false

    assert result.negative_failures.hash_only_authorization.reason ==
             :hash_is_not_fetch_authorization

    assert result.negative_failures.hash_only_authorization.safe_action ==
             :unavailable_fail_closed

    assert result.negative_failures.oversized_inline.classification == :ref_required
    assert result.negative_failures.oversized_inline.safe_action == :reject_before_durable_write
    assert result.no_generic_shared_cas_fallback?
    assert result.accepted_bytes_on_failure? == false
  end

  defp sha256_ref?("sha256:" <> digest) when byte_size(digest) == 64 do
    digest
    |> :binary.bin_to_list()
    |> Enum.all?(fn byte -> byte in ?0..?9 or byte in ?a..?f end)
  end

  defp sha256_ref?(_value), do: false
end
