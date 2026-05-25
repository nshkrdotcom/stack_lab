defmodule StackLab.FuguReadinessHandoffTest do
  use ExUnit.Case, async: true

  alias StackLab.{FuguLiveProviderGuard, FuguReadinessHandoff}

  test "builds the provider-free fugu single-node readiness handoff receipt" do
    assert {:ok, receipt} = FuguReadinessHandoff.run()

    assert receipt["schema_version"] == "stack_lab.fugu_single_node_readiness.v1"
    assert receipt["status"] == "pass"
    assert receipt["v2_unblocker?"] == true
    refute receipt["distributed_claim"]["proven?"]

    proof_ids =
      receipt["required_provider_free_proofs"]
      |> Enum.map(& &1["proof_id"])

    assert "context_abi_roundtrip" in proof_ids
    assert "nshkr_router_fabric_roundtrip" in proof_ids
    assert "extravaganza_external_acceptance" in proof_ids

    assert receipt["live_provider_profile"]["live_provider_behavior_ci_default?"] == false

    assert receipt["live_provider_profile"]["required_secret_wrapper"] ==
             "~/scripts/with_bash_secrets"
  end

  test "live provider guard rejects ambient live execution" do
    assert {:error, reason} = FuguLiveProviderGuard.validate([])
    assert reason["code"] == "live_profile_requires_explicit_opt_in"

    assert {:error, reason} = FuguLiveProviderGuard.validate(allow_live?: true)
    assert reason["code"] == "live_profile_requires_secret_wrapper"

    assert {:error, reason} = FuguLiveProviderGuard.validate(secrets_loaded?: true)
    assert reason["code"] == "live_profile_requires_allow_live"
  end

  test "live provider guard accepts explicit dry-run posture" do
    assert {:ok, receipt} =
             FuguLiveProviderGuard.validate(
               allow_live?: true,
               secrets_loaded?: true,
               execution_mode: "dry_run_guard_passed",
               command: "mix stack_lab.provider_smoke_check --linear-api-key-stdin"
             )

    assert receipt["status"] == "guard_passed"
    assert receipt["execution_mode"] == "dry_run_guard_passed"
    assert receipt["forwarded_command"] =~ "provider_smoke_check"
  end

  test "writes a receipt to the requested path" do
    path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_fugu_readiness_handoff_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, receipt} = FuguReadinessHandoff.run(source_ref: "test://phase16")
    assert FuguReadinessHandoff.write_receipt!(receipt, path) == path
    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["source_ref"] == "test://phase16"
  end
end
