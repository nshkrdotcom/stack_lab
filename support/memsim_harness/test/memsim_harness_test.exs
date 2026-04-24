defmodule StackLab.MemsimHarnessTest do
  use ExUnit.Case, async: true

  alias StackLab.MemsimHarness

  test "scenario 700 advertises the local-only multi-node epoch drill" do
    scenario = MemsimHarness.scenario()

    assert scenario.id == 700
    assert scenario.name == :multi_node_epoch_monotonicity_and_ordering
    assert scenario.local_only?
    refute scenario.release_evidence?
    assert scenario.concurrency_class == :simulated_multi_node
    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.toxiproxy_config)
  end

  test "seed and truncate cover deterministic memory substrate stores" do
    fixture = MemsimHarness.seed!(tenant_ref: "tenant://phase7/m7a", seed: 700)

    assert fixture.seed == 700
    assert fixture.tenant_ref == "tenant://phase7/m7a"

    assert %{kind: :postgres_truth_store, lifecycle: :deterministic_seed_truncate} =
             fixture.postgres_truth_store

    writer_nodes =
      Enum.filter(fixture.node_identities, &(&1.node_role == :memory_writer))

    assert length(writer_nodes) >= 2
    assert Enum.any?(fixture.node_identities, &(&1.node_role == :stacklab_probe))

    assert [_ | _] = fixture.stores.access_graph
    assert [_ | _] = fixture.stores.tiers.private
    assert [_ | _] = fixture.stores.policies
    assert [_ | _] = fixture.stores.proof_tokens
    assert [_ | _] = fixture.stores.invalidations

    assert [hook] = MemsimHarness.partition_hooks(fixture)
    assert hook.local_only?
    refute hook.release_evidence?
    assert File.exists?(hook.toxiproxy_config)

    truncated = MemsimHarness.truncate!(fixture)

    assert truncated.postgres_truth_store.seeded? == false
    assert truncated.stores.access_graph == []
    assert truncated.stores.tiers.private == []
    assert truncated.stores.tiers.shared == []
    assert truncated.stores.tiers.governed == []
    assert truncated.stores.policies == []
    assert truncated.stores.proof_tokens == []
    assert truncated.stores.invalidations == []
    assert truncated.observations.aitrace_receipts == []
    assert truncated.cleanup.leaves_tracked_artifacts? == false
  end

  test "scenario 700 proves epoch monotonicity, snapshot pinning, and evidence collection" do
    assert {:ok, result} =
             MemsimHarness.run_epoch_monotonicity(
               tenant_ref: "tenant://phase7/m7a",
               seed: 700
             )

    assert result.scenario.id == 700

    source_node_refs =
      result.graph_commits
      |> Enum.map(& &1.source_node_ref)
      |> Enum.uniq()

    assert length(source_node_refs) >= 2

    epochs = Enum.map(result.graph_commits, & &1.epoch)
    assert epochs == Enum.sort(epochs)
    assert epochs == Enum.uniq(epochs)

    assert Enum.all?(result.graph_commits, &present_order_evidence?/1)
    assert Enum.all?(result.evidence.proof_tokens, &present_order_evidence?/1)
    assert [_ | _] = result.evidence.db_row_refs
    assert [_ | _] = result.evidence.cluster_invalidation_observations

    assert result.snapshot_pin.concurrent_revocation.epoch > result.snapshot_pin.snapshot_epoch
    refute result.snapshot_pin.split_epoch?

    assert Enum.all?(result.snapshot_pin.read_epochs, fn {_read, epoch} ->
             epoch == result.snapshot_pin.snapshot_epoch
           end)

    assert [:duplicate_epoch, :missing_source_node_ref, :reused_epoch] ==
             Enum.map(result.negative_failures, & &1.reason)

    assert :ok = MemsimHarness.validate_evidence(result)
  end

  test "AITrace receipt collector distinguishes spans from different source nodes" do
    assert {:ok, result} = MemsimHarness.run_epoch_monotonicity(seed: 700)

    receipts_by_node = MemsimHarness.aitrace_receipts_by_node(result)

    assert map_size(receipts_by_node) >= 2

    for {node_ref, receipts} <- receipts_by_node do
      assert String.starts_with?(node_ref, "node://")
      assert [_ | _] = receipts

      assert Enum.all?(receipts, fn receipt ->
               receipt.source_node_ref == node_ref and
                 receipt.node_order_evidence.source_node_ref == node_ref and
                 Enum.all?(receipt.spans, &(&1.source_node_ref == node_ref))
             end)
    end
  end

  test "evidence validation rejects missing multi-node and local-only claims" do
    assert {:ok, result} = MemsimHarness.run_epoch_monotonicity(seed: 700)
    [first_receipt | _] = result.evidence.aitrace_receipts
    [first_commit | remaining_commits] = result.graph_commits

    one_node_receipts =
      put_in(result.evidence.aitrace_receipts, [first_receipt, first_receipt])

    assert {:error, {:aitrace_receipts_by_node, :requires_multiple_source_nodes}} =
             MemsimHarness.validate_evidence(one_node_receipts)

    duplicate_epoch =
      put_in(result.graph_commits, [
        first_commit,
        %{hd(remaining_commits) | epoch: first_commit.epoch} | tl(remaining_commits)
      ])

    assert {:error, {:graph_epochs, :not_unique}} =
             MemsimHarness.validate_evidence(duplicate_epoch)

    missing_node =
      put_in(result.graph_commits, [%{first_commit | source_node_ref: ""} | remaining_commits])

    assert {:error, {:graph_commits, :missing_source_node_ref}} =
             MemsimHarness.validate_evidence(missing_node)

    missing_invalidation = put_in(result.evidence.cluster_invalidation_observations, [])

    assert {:error, {:cluster_invalidations, :missing_observations}} =
             MemsimHarness.validate_evidence(missing_invalidation)

    release_claim =
      put_in(result.partition_hooks, [
        %{hd(result.partition_hooks) | release_evidence?: true, local_only?: false}
      ])

    assert {:error, {:partition_hooks, :release_evidence_claimed_before_owner_gate}} =
             MemsimHarness.validate_evidence(release_claim)
  end

  defp present_order_evidence?(record) do
    is_binary(record.source_node_ref) and record.source_node_ref != "" and
      is_binary(record.commit_lsn) and record.commit_lsn != "" and
      match?(
        %{wall_ns: wall_ns, logical: logical, source_node_ref: node_ref}
        when is_integer(wall_ns) and is_integer(logical) and is_binary(node_ref),
        record.commit_hlc
      )
  end
end
