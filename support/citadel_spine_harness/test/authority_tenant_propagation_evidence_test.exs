defmodule StackLab.CitadelSpineHarness.AuthorityTenantPropagationEvidenceTest do
  use ExUnit.Case, async: false

  alias StackLab.CitadelSpineHarness

  test "describes the Phase 6 AuthorityTenantPropagation evidence consumer scenario" do
    scenario = CitadelSpineHarness.authority_tenant_propagation_scenario()

    assert scenario.name == :phase6_authority_tenant_propagation

    assert scenario.cases == %{
             owner_composed_evidence: %{kind: :owner_composed_evidence}
           }

    assert scenario.contract == "AuthorityTenantPropagation.v1"
    assert scenario.owner_repos == [:citadel, :mezzanine, :jido_integration]
    assert scenario.consumer_repo == :stack_lab
    assert scenario.real_lower_facts_case == :authorized_mezzanine_readback
  end

  test "composes Citadel, Mezzanine, Jido Integration, and real lower facts evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_authority_tenant_propagation(:owner_composed_evidence)

    assert result.case == :owner_composed_evidence
    assert result.stack_lab_role == :evidence_composer_not_owner
    assert result.contract.id == "AuthorityTenantPropagation.v1"
    assert result.contract.owner == :citadel_mezzanine_jido_integration

    assert result.service_mode_gate.citadel_owner_consumed?
    assert result.service_mode_gate.mezzanine_owner_consumed?
    assert result.service_mode_gate.jido_integration_owner_consumed?
    assert result.service_mode_gate.real_lower_facts_read_consumed?
    assert result.service_mode_gate.no_bypass_scope_present?
    assert result.service_mode_gate.authorization_scope_ref_consistent?
    assert result.service_mode_gate.lower_facts_propagation_ref_consistent?
    assert result.service_mode_gate.harness_self_assertion_rejected?
    assert result.service_mode_gate.cross_tenant_lower_read_rejected?
    assert result.service_mode_gate.direct_lower_shortcut_rejected?

    assert result.citadel.tenant_ref == "tenant:tenant-phase6-m8"
    assert result.citadel.authority_decision_ref == "authority-decision:phase6-m8"
    assert result.citadel.budget_ref == "budget://phase6/m8/local-no-spend"

    assert result.mezzanine.authorization_scope_ref ==
             "authorization-scope://tenant-phase6-m8/exec-phase6-m8"

    assert result.mezzanine.no_bypass_scope_ref ==
             "no-bypass://phase6/m8/authority-tenant-budget"

    assert result.jido.tenant_scope_ref == "tenant-scope://tenant-phase6-m8/run-phase6-m8"
    assert result.jido.authorization_scope_ref == result.mezzanine.authorization_scope_ref
    assert result.jido.lower_facts_operation == :resolve_trace

    assert result.real_lower_facts.case == :authorized_mezzanine_readback
    assert result.real_lower_facts.operation == :fetch_run
    assert result.real_lower_facts.source == :lower_run_status

    assert result.negative_failures.missing_authority == :missing_authority_decision
    assert result.negative_failures.missing_budget == :missing_budget_ref
    assert result.negative_failures.missing_no_bypass_scope == :missing_no_bypass_scope_ref
    assert result.negative_failures.cross_tenant_scope == {:cross_tenant_scope, "tenant-other"}

    assert result.negative_failures.lower_facts_mismatch ==
             {:lower_facts_tenant_mismatch, "tenant-other"}

    assert result.negative_failures.direct_lower_shortcut ==
             {:forbidden_evidence, :direct_lower_shortcut_bypassing_authority}

    assert result.negative_failures.harness_self_assertion ==
             {:forbidden_evidence, :harness_self_assertion_as_authority_evidence}

    assert result.negative_failures.cross_tenant_lower_read == :unauthorized_lower_read
  end
end
