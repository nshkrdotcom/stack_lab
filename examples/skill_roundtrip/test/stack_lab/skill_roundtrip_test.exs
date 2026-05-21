defmodule StackLab.SkillRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.SkillRoundtrip

  test "assembled skill roundtrip validates all Phase G fixtures" do
    assert {:ok, report} = SkillRoundtrip.run()

    assert report.fixture_refs == [
             "SKILL-001",
             "SKILL-002",
             "SKILL-003",
             "SKILL-004",
             "SKILL-005",
             "SKILL-006",
             "SKILL-007",
             "SKILL-008",
             "SKILL-009",
             "SKILL-010"
           ]

    assert report.admission_status == :admitted_skill_package
    assert report.invocation_entrypoint == "invoke"
    assert report.raw_material_present? == false
    assert report.provider_effect_started? == false
    assert report.disallowed_skill_result == :rejected
    assert report.forbidden_path_result == :rejected
    assert report.credential_posture_result == :rejected
    assert report.projection_redaction == "refs_only"
    assert report.projection_admission_status == :admitted
    assert report.trace_redaction == "refs_only"
  end

  test "skill manifests are validated by Jido Integration contracts" do
    assert {:ok, package} =
             SkillRoundtrip.manifest("external", 1)
             |> Jido.Integration.V2.SkillContracts.package()

    reason =
      "external"
      |> SkillRoundtrip.manifest(1)
      |> Map.put(:raw_secret, "hidden")
      |> Jido.Integration.V2.SkillContracts.package()

    assert package.skill_ref == "skill://phase-g/external"
    assert {:error, {:forbidden_skill_package_fields, [:raw_secret]}} = reason
  end

  test "roundtrip does not expose raw projection or trace keys" do
    assert {:ok, report} = SkillRoundtrip.run()

    refute Map.has_key?(report, :private_state)
    refute Map.has_key?(report, :provider_payload)
  end
end
