defmodule StackLab.HiveRoundtripTest do
  use ExUnit.Case, async: true

  alias StackLab.HiveRoundtrip

  test "proves HIVE-001 through HIVE-010 in one assembled roundtrip" do
    assert {:ok, report} = HiveRoundtrip.run()

    assert report.fixture_refs ==
             ~w[HIVE-001 HIVE-002 HIVE-003 HIVE-004 HIVE-005 HIVE-006 HIVE-007 HIVE-008 HIVE-009 HIVE-010]

    assert report.store_mode == :memory
    assert report.durable_store_mode == :durable
    assert report.handoff.memory_scope_ref == "memory-scope://tenant-a/run-1/shared"
    assert report.routed_message.delivery_status == :accepted_no_provider_effect
    assert report.memory_decision.decision == :allow
    assert report.pattern_plan.provider_effect_status == :suppressed_for_replay
    assert report.projection.redaction_posture == "refs_only"
    assert report.trace_projection.workflow_lifecycle_ref == "workflow://life-1"
  end

  test "keeps negative gates closed" do
    assert {:ok, report} = HiveRoundtrip.run()

    assert {:error, {:missing_ref, :skill_admission_ref}} = report.negative_results.missing_skill
    assert {:error, :cross_tenant_message} = report.negative_results.cross_tenant_message
    assert {:error, :undeclared_recipient} = report.negative_results.undeclared_recipient

    assert {:error, :missing_shared_memory_grant} =
             report.negative_results.missing_shared_memory_grant

    assert {:error, :unknown_memory_scope} = report.negative_results.unknown_memory_scope

    assert {:error, :side_effecting_replay_not_allowed} =
             report.negative_results.side_effecting_replay

    assert {:error, {:raw_field_rejected, [:agent_message_body]}} =
             report.negative_results.raw_projection
  end

  test "projections never include raw multi-agent body fields" do
    assert {:ok, report} = HiveRoundtrip.run()
    projection_map = Map.from_struct(report.projection)

    refute Map.has_key?(projection_map, :agent_message_body)
    refute Map.has_key?(projection_map, :memory_body)
    refute Map.has_key?(projection_map, :provider_payload)
    refute Map.has_key?(projection_map, :skill_private_state)
  end
end
