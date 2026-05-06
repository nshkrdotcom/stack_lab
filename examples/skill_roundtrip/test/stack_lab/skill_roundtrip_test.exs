defmodule StackLab.SkillRoundtripTest do
  use ExUnit.Case, async: true
  use JidoHive.SkillConformanceContracts

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

    assert report.duplicate_binding_result == :rejected
    assert report.missing_ref_result == :rejected
    assert report.rollback_revision == 3
    assert report.composition_count == 1
    assert report.invocation_effect_status == :ready_after_gates
    assert report.provider_effect_started? == false
    assert report.budget_denial == :rejected
    assert report.projection_redaction == "refs_only"
    assert report.trace_redaction == "private_state_redacted"
    assert report.durable_store_mode == :durable
  end

  test "external conformance helper rejects unsafe skill manifests" do
    assert_safe_skill_manifest(SkillRoundtrip.manifest("external", 1))

    reason =
      "external"
      |> SkillRoundtrip.manifest(1)
      |> Map.put(:raw_secret, "hidden")
      |> refute_safe_skill_manifest()

    assert {:raw_skill_field_forbidden, [:raw_secret]} = reason
  end

  test "roundtrip does not expose raw projection or trace keys" do
    assert {:ok, report} = SkillRoundtrip.run()

    refute Map.has_key?(report, :private_state)
    refute Map.has_key?(report, :provider_payload)
  end
end
