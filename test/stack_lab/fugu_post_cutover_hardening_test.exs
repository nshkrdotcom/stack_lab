defmodule StackLab.FuguPostCutoverHardeningTest do
  use ExUnit.Case, async: true

  alias StackLab.FuguPostCutoverHardening

  test "records local performance and provider-free cost posture" do
    assert {:ok, receipt} = FuguPostCutoverHardening.run()

    assert receipt["schema_version"] == "stack_lab.fugu_post_cutover_hardening.v1"
    assert receipt["status"] == "pass"
    assert receipt["local_performance"]["measurement_scope"] == "local_receipt_build_snapshot"
    assert is_integer(receipt["local_performance"]["scheduler_count"])
    assert is_integer(receipt["local_performance"]["process_count"])
    assert is_integer(receipt["local_performance"]["receipt_build_elapsed_us"])
    assert is_integer(receipt["local_performance"]["memory_bytes"]["total"])

    assert receipt["cost_posture"]["profile"] == "provider_free_deterministic"
    assert receipt["cost_posture"]["live_provider_calls"] == 0
    assert receipt["cost_posture"]["provider_cost_usd"] == "0.00"
    assert nonempty_list?(receipt["cost_posture"]["cost_evidence_refs"])
  end

  test "maps covered failure fixture families and open warnings" do
    assert {:ok, receipt} = FuguPostCutoverHardening.run()

    closeout = receipt["failure_fixture_closeout"]
    assert closeout["no_new_release_blocking_defects?"] == true

    families =
      closeout["covered_families"]
      |> Enum.map(& &1["family"])

    assert "context" in families
    assert "authority" in families
    assert "router" in families
    assert "model_execution" in families
    assert "eval_cost_lineage" in families
    assert "memory_persistence_restart" in families
    assert "optimization_adaptive" in families

    assert Enum.all?(closeout["covered_families"], fn family ->
             family["status"] == "covered_for_provider_free_release" and
               nonempty_list?(family["fixture_refs"])
           end)

    assert [%{"code" => "artifact_source_sha_stale", "status" => "non_release_warning"}] =
             closeout["open_warnings"]
  end

  test "keeps extraction and next router/GEPA work as explicit decisions" do
    assert {:ok, receipt} = FuguPostCutoverHardening.run()

    assert receipt["decisions"]["context_abi_extraction"]["decision"] ==
             "defer_hex_or_external_extraction"

    assert receipt["decisions"]["router_next"]["decision"] ==
             "prioritize_distributed_parity_then_learning"

    assert receipt["decisions"]["gepa_next"]["decision"] ==
             "prioritize_candidate_quality_without_auto_promotion"

    assert receipt["v2_handoff"]["target_docset"] == "../nshkr_v2/06_implementation_checklist.md"
    assert nonempty_list?(receipt["v2_handoff"]["required_green_receipts_before_v2_phase8"])
  end

  test "writes a hardening receipt to the requested path" do
    path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_fugu_post_cutover_hardening_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, receipt} = FuguPostCutoverHardening.run(source_ref: "test://phase18")
    assert FuguPostCutoverHardening.write_receipt!(receipt, path) == path
    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["source_ref"] == "test://phase18"
  end

  defp nonempty_list?(value), do: is_list(value) and value != []
end
