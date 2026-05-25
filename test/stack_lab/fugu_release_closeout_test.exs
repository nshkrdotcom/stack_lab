defmodule StackLab.FuguReleaseCloseoutTest do
  use ExUnit.Case, async: true

  alias StackLab.FuguReleaseCloseout

  test "maps every fugu release claim to source, tests, docs, scanners, QC, and receipts" do
    assert {:ok, receipt} = FuguReleaseCloseout.run()

    assert receipt["schema_version"] == "stack_lab.fugu_release_closeout.v1"
    assert receipt["status"] == "pass"
    assert receipt["claim_policy"]["all_public_claims_mapped?"] == true
    assert receipt["claim_policy"]["hidden_defects_allowed?"] == false

    claim_ids = Enum.map(receipt["public_claims"], & &1["claim_id"])

    assert "context_abi_single_node" in claim_ids
    assert "router_fabric_single_node" in claim_ids
    assert "product_boundary_acceptance" in claim_ids
    assert "adaptive_optimization_coordination" in claim_ids
    assert "persistence_restart_profiles" in claim_ids
    assert "live_and_distributed_boundaries" in claim_ids

    Enum.each(receipt["public_claims"], fn claim ->
      assert claim["status"] == "mapped"
      assert nonempty_list?(claim["owner_repos"])
      assert nonempty_list?(claim["source_refs"])
      assert nonempty_list?(claim["test_refs"])
      assert nonempty_list?(claim["scanner_refs"])
      assert nonempty_list?(claim["docs_refs"])
      assert nonempty_list?(claim["qc_refs"])
      assert nonempty_list?(claim["receipt_refs"])
      assert nonempty_list?(claim["proves"])
    end)
  end

  test "keeps live, distributed, and artifact freshness claims open instead of hiding them" do
    assert {:ok, receipt} = FuguReleaseCloseout.run()

    open_claims =
      receipt["open_non_release_claims"]
      |> Enum.map(& &1["claim"])

    assert "distributed_beam_placement" in open_claims
    assert "live_provider_behavior" in open_claims
    assert "artifact_source_sha_freshness" in open_claims

    refute receipt["claim_policy"]["authoritative_audit_claim?"]
    refute receipt["claim_policy"]["production_deployment_claim?"]
  end

  test "writes a release closeout receipt to the requested path" do
    path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_fugu_release_closeout_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, receipt} = FuguReleaseCloseout.run(source_ref: "test://phase17")
    assert FuguReleaseCloseout.write_receipt!(receipt, path) == path
    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["source_ref"] == "test://phase17"
  end

  defp nonempty_list?(value), do: is_list(value) and value != []
end
