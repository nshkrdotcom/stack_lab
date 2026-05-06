defmodule StackLab.CitadelSpineHarness.Phase5AiNativeMinimalSeamsTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  test "describes Phase 5 scenarios 210, 210A, and 211" do
    context_budget = CitadelSpineHarness.phase5_context_budget_exceeded_scenario()
    cost_attribution = CitadelSpineHarness.phase5_cost_attribution_missing_scenario()
    semantic_failure = CitadelSpineHarness.phase5_semantic_failure_evidence_gap_scenario()

    assert context_budget.name == :phase5_context_budget_exceeded
    assert context_budget.runbook == "context_budget_exceeded.md"

    assert context_budget.cases.context_budget_exceeded == %{
             kind: :context_budget_exceeded,
             scenario: 210
           }

    assert cost_attribution.name == :phase5_cost_attribution_missing
    assert cost_attribution.runbook == "cost_attribution_missing.md"

    assert cost_attribution.cases.cost_attribution_missing == %{
             kind: :cost_attribution_missing,
             scenario: "210A"
           }

    assert semantic_failure.name == :phase5_semantic_failure_evidence_gap
    assert semantic_failure.runbook == "semantic_failure_evidence_gap.md"

    assert semantic_failure.cases.semantic_failure_evidence_gap == %{
             kind: :semantic_failure_evidence_gap,
             scenario: 211
           }
  end

  test "scenario 210 proves context budget exceeded failures fail closed at every locus" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_context_budget_exceeded(:context_budget_exceeded)

    assert result.case == :context_budget_exceeded
    assert result.scenario_id == 210
    assert result.positive.context_pack_decision == :allow
    assert result.positive.fragment_count == 1

    failures = result.negative_failures

    loci =
      failures
      |> Map.values()
      |> Enum.map(& &1.locus)
      |> Enum.uniq()
      |> Enum.sort()

    assert loci == [
             :post_run_reconcile,
             :preflight,
             :runtime_admission,
             :stream_tick,
             :tool_result_append
           ]

    assert {:error, {:missing_required_inference_descriptor_refs, missing}} =
             failures.preflight_descriptor_refs.result

    assert Enum.sort(missing) == ["endpoint_id", "model_identity", "model_version"]

    assert failures.tool_result_append_context_bytes.result == {:error, :context_budget_exceeded}
    assert failures.tool_result_append_context_bytes.decision == :reject_context_append
    refute failures.tool_result_append_context_bytes.fragments_appended?

    assert failures.tool_result_append_unavailable_meter.result ==
             {:error, :context_budget_meter_unavailable}

    assert failures.tool_result_append_unavailable_meter.decision ==
             :quarantine_meter_unavailable

    refute failures.tool_result_append_unavailable_meter.fragments_appended?

    assert_failure_reason(failures.preflight_input_tokens, :input_tokens_budget_exceeded)
    assert_failure_reason(failures.preflight_wall_clock, :request_wall_clock_budget_exceeded)
    assert_failure_reason(failures.stream_tick_output_tokens, :output_token_budget_exceeded)
    assert_failure_reason(failures.stream_tick_streamed_bytes, :streamed_byte_budget_exceeded)
    assert_failure_reason(failures.runtime_admission_gpu_seconds, :gpu_seconds_budget_exceeded)
    assert_failure_reason(failures.runtime_admission_cpu_ms, :cpu_ms_budget_exceeded)

    assert_failure_reason(
      failures.runtime_admission_memory_mb_seconds,
      :memory_mb_seconds_budget_exceeded
    )

    assert_failure_reason(failures.runtime_admission_cost, :cost_budget_exceeded)

    assert_failure_reason(
      failures.runtime_admission_concurrency,
      :tenant_role_model_target_concurrency_exceeded
    )

    assert failures.post_run_reconcile_actual_cost.result == {:error, :actual_cost_overrun}
    refute failures.post_run_reconcile_actual_cost.retroactive_authorization?
  end

  test "scenario 210A proves opaque cost counters cannot satisfy attribution joins" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_cost_attribution_missing(
               :cost_attribution_missing
             )

    assert result.case == :cost_attribution_missing
    assert result.scenario_id == "210A"
    assert result.positive.attribution_decision == :attribute

    assert result.non_product_surface == %{
             billing_product_surface: false,
             chargeback_product_surface: false,
             invoice_product_surface: false,
             quota_ui_surface: false
           }

    assert_missing_cost_refs(result.negative_failures.global_counter_only)
    assert_missing_cost_refs(result.negative_failures.provider_session_only)
    assert_missing_cost_refs(result.negative_failures.opaque_runtime_cost_map)

    assert_missing_cost_refs(result.negative_failures.missing_tenant_join, [:tenant_ref])

    assert_missing_cost_refs(result.negative_failures.missing_endpoint_join, [
      :endpoint_descriptor_ref
    ])

    assert_missing_cost_refs(result.negative_failures.missing_source_meter_join, [
      :source_meter_refs
    ])
  end

  test "scenario 211 proves semantic failure evidence gaps and unsafe exports fail closed" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_phase5_semantic_failure_evidence_gap(
               :semantic_failure_evidence_gap
             )

    assert result.case == :semantic_failure_evidence_gap
    assert result.scenario_id == 211
    assert String.starts_with?(result.positive.journal_entry_id, "semantic_failure_journal:v1:")
    assert String.starts_with?(result.positive.semantic_failure_payload_hash, "sha256:")
    assert String.contains?(result.positive.corrected_output_artifact_ref, "artifact://")
    assert result.positive.evidence_refs != []

    ref_summary = result.positive.reply_publication_ref_summary
    assert String.starts_with?(ref_summary.body_hash, "sha256:")
    assert String.starts_with?(ref_summary.schema_hash, "sha256:")
    assert String.contains?(ref_summary.artifact_id, "reply-scenario-211")

    failures = result.negative_failures

    assert failures.missing_evidence_refs ==
             {:error, :missing_semantic_failure_evidence_refs}

    assert failures.raw_prompt_provider_body_export ==
             {:error, :raw_sensitive_payload_not_export_evidence}

    assert failures.feedback_training_promotion_fields ==
             {:error, :feedback_training_promotion_field_forbidden}

    assert failures.opaque_delimiter_new_write ==
             {:error, :legacy_delimiter_journal_id_new_write_forbidden}

    assert failures.delimiter_collision.legacy_ids_equal
    refute failures.delimiter_collision.structured_ids_equal?
    assert failures.delimiter_collision.result == :structured_ids_do_not_collide

    assert failures.agent_mutation_proposal_denial.result ==
             {:error, :agent_direct_mutation_path_forbidden}

    refute failures.agent_mutation_proposal_denial.direct_mutation_allowed?
    assert failures.agent_mutation_proposal_denial.proposal_state == :quarantined
    assert failures.agent_mutation_proposal_denial.blast_radius == :tenant_local

    assert failures.agent_mutation_proposal_denial.quarantined_scopes == [
             :multi_tenant,
             :platform_global
           ]

    assert failures.unbounded_reply_publication == {:error, :invalid_reply_publication}
  end

  defp assert_failure_reason(failure, expected_reason) do
    assert failure.result == {:error, expected_reason}
    refute failure.side_effect_committed?
  end

  defp assert_missing_cost_refs(result, expected_missing \\ nil) do
    assert {:error, {:missing_cost_attribution_join_refs, missing}} = result

    if expected_missing do
      assert Enum.sort(missing) == Enum.sort(expected_missing)
    else
      assert missing != []
    end
  end
end
