defmodule StackLab.Examples.MultiNodeRoundtripTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness.RemoteSupport
  alias StackLab.Examples.MultiNodeRoundtrip

  @distribution_skip (case RemoteSupport.ensure_distribution_started() do
                        :ok ->
                          false

                        {:error, reason} ->
                          RemoteSupport.distribution_start_error_message(reason)
                      end)

  test "multi-node scenario points at the multi-node harness files" do
    scenario = MultiNodeRoundtrip.scenario()

    assert scenario.name == :multi_node_roundtrip
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  @tag skip: @distribution_skip
  test "remote acceptance case drives Citadel into durable Spine acceptance across nodes" do
    assert {:ok, result} = MultiNodeRoundtrip.exercise(:acceptance)

    assert result.case == :acceptance
    assert result.transport.status == :accepted
    assert result.citadel.replay_status == :submission_accepted
    assert result.transport.submission_key == result.citadel.submission_key
    assert result.transport.submission_key == result.spine.submission_key
    assert result.transport.submission_receipt_ref == result.spine.submission_receipt_ref
    assert result.scope.workspace_root == result.runtime_inputs.workspace_root
    assert result.scope.file_scope == result.runtime_inputs.file_scope
    assert result.remote.remote_node != Node.self()
  end

  @tag skip: @distribution_skip
  test "remote scope rejection returns a typed Spine rejection and supersedes the Citadel entry" do
    assert {:ok, result} = MultiNodeRoundtrip.exercise(:scope_rejection)

    assert result.case == :scope_rejection
    assert result.transport.rejection_family == :scope_unresolvable
    assert result.transport.reason_code == "workspace_ref_unresolved"
    assert result.citadel.replay_status == :superseded
    assert result.citadel.last_error_code == "workspace_ref_unresolved"
    assert result.citadel.has_redecision_entry
    assert result.spine.rejection_family == :scope_unresolvable
    assert result.spine.reason_code == "workspace_ref_unresolved"
    assert result.remote.remote_node != Node.self()
  end
end
