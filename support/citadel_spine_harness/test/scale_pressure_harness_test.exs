defmodule StackLab.CitadelSpineHarness.ScalePressureHarnessTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.ScalePressureHarness

  test "describes the Phase 6 scale-pressure harness release gate" do
    scenario = CitadelSpineHarness.scale_pressure_harness_scenario()

    assert scenario.name == :phase6_scale_pressure_harness
    assert scenario.runbook == "scale_pressure_harness.md"
    assert scenario.scenario == 610
    assert scenario.owner_repo == :stack_lab

    assert scenario.contracts == [
             "ScalePressureProfile.v1",
             "ProviderFaultMatrix.v1",
             "BudgetCostAuthorityContract.v1"
           ]

    assert scenario.cases == %{
             bounded_local_pressure: %{
               kind: :bounded_local_pressure,
               scenario: 610
             }
           }
  end

  test "parses only the M11 ScalePressureProfile.v1 contract shape" do
    assert {:ok, profile} = ScalePressureHarness.parse_profile(ScalePressureHarness.profile())

    assert profile.contract_name == "ScalePressureProfile.v1"
    assert profile.owner_repo == :stack_lab
    assert profile.tenant_count == 3
    assert profile.agent_count_per_tenant == 4
    assert profile.work_items_per_agent == 2
    assert profile.concurrency_cap == 6
    assert profile.rate_limits.dispatch_window.limit == 6
    assert profile.backpressure_policy.action == :reject_over_cap
    assert profile.restart_replay_class == :bounded_restart_replay_evidence
    assert profile.cleanup_class == :profile_install_cleanup_required
    refute profile.slo_claim_status.claim?

    assert {:error, {:missing_required_fields, [:rate_limits]}} =
             profile
             |> Map.delete(:rate_limits)
             |> ScalePressureHarness.parse_profile()

    assert {:error, {:legacy_pressure_field_forbidden, :max_concurrency}} =
             profile
             |> Map.put(:max_concurrency, 6)
             |> ScalePressureHarness.parse_profile()
  end

  test "runs bounded local pressure with explicit no-SLO, no-egress, budget, fault, and cleanup evidence" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_scale_pressure_harness(:bounded_local_pressure)

    assert result.case == :bounded_local_pressure
    assert result.scenario == 610
    assert result.stack_lab_role == :scale_pressure_owner

    assert result.profile.contract_name == "ScalePressureProfile.v1"
    assert result.profile.tenant_count == 3
    assert result.profile.agent_count_per_tenant == 4
    assert result.profile.agent_count == 12
    assert result.profile.work_items_per_agent == 2
    assert result.profile.work_item_count == 24
    assert result.profile.concurrency_cap == 6
    refute result.profile.slo_claim_status.claim?
    assert result.profile.slo_claim_status.reason == :bounded_local_pressure_no_owned_metrics

    assert result.dispatch.scheduler == :bounded_async_stream
    assert result.dispatch.admitted_work_items == 24
    assert result.dispatch.concurrency_cap == 6
    assert result.dispatch.max_in_flight_observed <= 6
    assert result.dispatch.backpressure_action == :reject_over_cap

    assert result.no_egress_policy.external_egress == :deny
    assert result.no_egress_policy.process_spawn == :deny
    assert result.no_egress_policy.raw_external_saas_write_path == :deny
    assert result.no_egress_policy.provider_spend_cents == 0
    assert result.no_egress_policy.external_write_refs == []

    assert result.budget_cost.enforcement_points == [
             :preflight,
             :tool_result_append,
             :stream_tick,
             :runtime_admission,
             :post_run_reconcile
           ]

    assert result.budget_cost.provider_billable_units == 0
    refute result.budget_cost.real_provider_spend?

    assert Enum.map(result.provider_fault_matrix.faults, & &1.fault_class) |> Enum.sort() ==
             [:malformed_response, :partial_response, :rate_limit, :timeout, :unavailable_meter]

    assert Enum.all?(
             result.provider_fault_matrix.faults,
             &(&1.injected_at == :configured_adapter_boundary and not &1.lower_side_effects?)
           )

    assert result.cleanup.status == :passed
    assert result.cleanup.install_ref == "profile-install://phase6/m11/scale-pressure"
    assert result.cleanup.removed_ref == "profile-cleanup://phase6/m11/scale-pressure"
    assert result.raw_payload_scan.result == :passed

    refute raw_payload_present?(result)
    assert :ok = ScalePressureHarness.validate_evidence(result)
  end

  test "records required M11 negative pressure failures" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_scale_pressure_harness(:bounded_local_pressure)

    assert result.negative_failures.overload_rejection == {:concurrency_cap_exceeded, 7}
    assert result.negative_failures.cleanup_failure == :cleanup_required
    assert result.negative_failures.egress_attempt == :external_egress_denied
    assert result.negative_failures.cross_tenant_pressure_leak == :cross_tenant_pressure_leak

    assert {:error, {:concurrency_cap_exceeded, 7}} =
             result
             |> put_in([:profile, :concurrency_cap], 7)
             |> ScalePressureHarness.validate_evidence()

    assert {:error, :cleanup_required} =
             result
             |> put_in([:cleanup, :status], :failed)
             |> ScalePressureHarness.validate_evidence()

    assert {:error, :external_egress_denied} =
             result
             |> put_in([:no_egress_policy, :external_egress], :allow)
             |> ScalePressureHarness.validate_evidence()

    assert {:error, :cross_tenant_pressure_leak} =
             result
             |> put_in(
               [:work_items, Access.at(0), :observed_tenant_ref],
               "tenant://phase6/m11/t2"
             )
             |> ScalePressureHarness.validate_evidence()
  end

  defp raw_payload_present?(term) when is_map(term) do
    Enum.any?(term, fn
      {key, _value} when key in [:raw_payload, :raw_prompt, :provider_body, :full_prompt] -> true
      {_key, value} -> raw_payload_present?(value)
    end)
  end

  defp raw_payload_present?(term) when is_list(term), do: Enum.any?(term, &raw_payload_present?/1)
  defp raw_payload_present?(term) when is_binary(term), do: String.contains?(term, "raw_payload")
  defp raw_payload_present?(_term), do: false
end
