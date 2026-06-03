ExUnit.start()

defmodule StackLab.ChassisBridgeTest do
  use ExUnit.Case, async: true

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

  test "runs chassis proof catalog with proof names and evidence" do
    assert {:ok, report} = StackLab.ChassisBridge.run(:chassis)

    assert report.passed == 12
    assert report.failed == 0
    assert report.skipped == 0
    assert Enum.map(report.proofs, & &1.name) == @proof_names
    assert Enum.all?(report.proofs, &(&1.status == :pass))
    assert Enum.all?(report.proofs, &(is_map(&1.evidence) and map_size(&1.evidence) > 0))
  end

  test "runs chassis evolution proof catalog with scenario evidence" do
    assert {:ok, report} = StackLab.ChassisBridge.run(:chassis_evolution)

    assert report.tag == :chassis_evolution
    assert report.passed == 21
    assert report.failed == 0
    assert report.skipped == 0

    names = Enum.map(report.proofs, & &1.name)
    assert "chassis.evolution.source_level_patch_success.v1" in names
    assert "chassis.evolution.receipt_redaction.v1" in names
    assert "chassis.evolution.mezzanine_projections_reduced.v1" in names

    source =
      Enum.find(report.proofs, &(&1.name == "chassis.evolution.source_level_patch_success.v1"))

    assert source.status == :pass
    assert source.evidence.final_state == :committed
    assert length(source.evidence.spans) == 16
  end

  test "unknown tags fail closed instead of returning a zero-success report" do
    assert {:error, {:unknown_tag, :missing}} = StackLab.ChassisBridge.run(:missing)
  end
end
