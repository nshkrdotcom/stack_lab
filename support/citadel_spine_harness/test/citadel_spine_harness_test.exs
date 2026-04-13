defmodule StackLab.CitadelSpineHarnessTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.RemoteSpine
  alias StackLab.CitadelSpineHarness.RemoteSupport

  test "resolves sibling repo roots for harness-owned assembly" do
    roots = CitadelSpineHarness.repo_roots()

    assert File.dir?(roots.stack_lab)
    assert File.dir?(roots.citadel)
    assert File.dir?(roots.jido_integration)
  end

  test "describes the same-node proof cases as acceptance, rejection, and duplicate" do
    scenario = CitadelSpineHarness.same_node_scenario()

    assert scenario.name == :single_node_roundtrip

    assert scenario.cases |> Map.keys() |> Enum.sort() == [
             :acceptance,
             :duplicate,
             :scope_rejection
           ]

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the typed host proof case above the lower seam" do
    scenario = CitadelSpineHarness.typed_host_scenario()

    assert scenario.name == :typed_host_roundtrip

    assert scenario.cases == %{
             command_acceptance: %{kind: :command_acceptance},
             command_duplicate: %{kind: :command_duplicate},
             command_scope_rejection: %{kind: :command_scope_rejection}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the semantic host proof case above the typed boundary" do
    scenario = CitadelSpineHarness.semantic_host_scenario()

    assert scenario.name == :semantic_host_roundtrip

    assert scenario.cases == %{
             turn_acceptance: %{kind: :turn_acceptance},
             turn_replay: %{kind: :turn_replay},
             turn_scope_rejection: %{kind: :turn_scope_rejection}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "remote spine startup returns only after the remote service is callable" do
    remote = RemoteSupport.start_remote_spine!(:startup_probe)

    try do
      assert :ok == RemoteSupport.remote_call!(remote.remote_node, RemoteSpine, :ping, [])

      assert nil ==
               RemoteSupport.remote_call!(remote.remote_node, RemoteSpine, :fetch_rejection, [
                 "missing"
               ])
    after
      assert :ok == RemoteSupport.stop_remote_spine(remote)
    end
  end
end
