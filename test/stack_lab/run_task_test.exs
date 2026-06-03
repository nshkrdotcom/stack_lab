defmodule StackLab.RunTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @proof_names [
    "chassis.boundary.local_adapter_equivalence.v1",
    "chassis.boundary.no_pid_payloads.v1",
    "chassis.boundary.no_raw_secret_payloads.v1",
    "chassis.boundary.codec_digest_stability.v1",
    "chassis.boundary.idempotency_required_for_mutations.v1",
    "chassis.boundary.citadel_fail_closed.v1",
    "chassis.deployment.profile_monolith_local",
    "chassis.deployment.profile_ternary_split_3_local",
    "chassis.deployment.profile_maximal_decoupled_local",
    "chassis.secrets.no_plaintext_in_receipts",
    "chassis.tenant.residency_enforcement",
    "chassis.metabolic.auto_rollback_on_pressure"
  ]

  test "stack_lab.run emits structural JSON for chassis tag" do
    output =
      capture_io(fn ->
        Mix.Tasks.StackLab.Run.run(["--tag", "chassis", "--json"])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["passed"] == 12
    assert decoded["failed"] == 0
    assert decoded["skipped"] == 0
    assert Enum.map(decoded["proofs"], & &1["name"]) == @proof_names
  end

  test "stack_lab.run emits structural JSON for chassis evolution tag" do
    output =
      capture_io(fn ->
        Mix.Tasks.StackLab.Run.run(["--tag", "chassis_evolution", "--json"])
      end)

    assert {:ok, decoded} = Jason.decode(output)
    assert decoded["tag"] == "chassis_evolution"
    assert decoded["passed"] == 21
    assert decoded["failed"] == 0

    assert Enum.any?(
             decoded["proofs"],
             &(&1["name"] == "chassis.evolution.source_level_patch_success.v1")
           )
  end
end
