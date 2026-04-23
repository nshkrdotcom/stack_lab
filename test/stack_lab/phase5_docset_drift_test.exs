defmodule StackLab.Phase5DocsetDriftTest do
  use ExUnit.Case, async: true

  alias StackLab.Phase5DocsetDrift

  @predicates ["feature_freeze_invariant", "public_contract_admission"]

  test "passes a consistent Phase 5 docset with semantic predicate evidence" do
    docs_root = fixture_docset!()

    assert {:ok, result} =
             Phase5DocsetDrift.run(docs_root: docs_root, stack_lab_root: empty_stack_lab_root!())

    assert result.status == :pass
    assert result.release_manifest_scenario_ids == ["201", "210A"]
    assert result.stack_lab_spec_scenario_ids == ["201", "210A"]

    assert result.runbook_readme_index == [
             "cost_attribution_missing.md",
             "temporal_postgres_projection_drift.md"
           ]

    assert result.audits.semantic_closeout_audit.status == :pass
  end

  test "rejects structural-only Scenario 212 closeout parity" do
    docs_root = fixture_docset!(semantic_profile: structural_only_semantic_profile())

    assert {:error, result} =
             Phase5DocsetDrift.run(docs_root: docs_root, stack_lab_root: empty_stack_lab_root!())

    assert %{check: :semantic_closeout_structural_only} in result.failures
  end

  defp fixture_docset!(opts \\ []) do
    root =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_phase5_docset_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(root, "contracts"))
    File.mkdir_p!(Path.join(root, "stack_lab"))
    File.mkdir_p!(Path.join(root, "runbooks"))
    File.mkdir_p!(Path.join(root, "v7"))

    semantic_profile = Keyword.get(opts, :semantic_profile, passing_semantic_profile())

    manifest = %{
      "semantic_closeout_profile_schema" => %{
        "predicate_ids" => @predicates,
        "predicate_status_values" => [
          "pass",
          "fail",
          "unknown",
          "not_applicable_with_evidence"
        ]
      },
      "m10_scenario_212_semantic_closeout_predicate_check" => semantic_profile,
      "targeted_proofs" => [
        %{
          "id" => 201,
          "name" => "temporal_postgres_projection_drift",
          "runbook" => "runbooks/temporal_postgres_projection_drift.md",
          "proof_status" => "source_implemented",
          "source_ref" => "phase5/stack-lab-hardening-v7@abc123",
          "proof_output_ref" =>
            "v7/0061_stack_lab_scenario_201_temporal_postgres_projection_drift.md",
          "owning_milestone" => "Milestone 2"
        },
        %{
          "id" => "210A",
          "name" => "cost_attribution_missing",
          "runbook" => "runbooks/cost_attribution_missing.md"
        }
      ],
      "stack_lab_runtime_envelopes" => [
        %{
          "scenario_id" => 201,
          "runtime_class" => "contract_unit",
          "expected_local_max_ms" => 30_000,
          "ci_timeout_ms" => 60_000,
          "measurement_scope" => "fixture after compile",
          "timeout_safe_action" => "fail milestone",
          "positive_path_runtime_ref" => "positive fixture passed",
          "negative_failure_runtime_ref" => "negative fixture passed",
          "observed_local_or_ci_runtime_ms" => 100,
          "timeout_result" => "completed_inside_ci_timeout",
          "proof_output_ref" =>
            "v7/0061_stack_lab_scenario_201_temporal_postgres_projection_drift.md"
        },
        %{
          "scenario_id" => "210A",
          "runtime_class" => "source_integration",
          "expected_local_max_ms" => 30_000,
          "ci_timeout_ms" => 60_000,
          "measurement_scope" => "fixture after app boot",
          "timeout_safe_action" => "fail milestone"
        }
      ]
    }

    File.write!(
      Path.join(root, "contracts/phase5_release_manifest.json"),
      Jason.encode!(manifest, pretty: true)
    )

    File.write!(Path.join(root, "stack_lab/STACK_LAB_SPEC.md"), stack_lab_spec())
    File.write!(Path.join(root, "runbooks/README.md"), runbook_readme())
    File.write!(Path.join(root, "runbooks/temporal_postgres_projection_drift.md"), runbook("201"))
    File.write!(Path.join(root, "runbooks/cost_attribution_missing.md"), runbook("210A"))
    File.write!(Path.join(root, "v7/0010_master_checklist.md"), "Scenario 201\nScenario 210A\n")

    root
  end

  defp passing_semantic_profile do
    %{
      "structural_only_rejected" => true,
      "negative_structural_only_fixture_rejected" => true,
      "predicate_matrix" =>
        Enum.map(@predicates, fn predicate ->
          %{
            "predicate_id" => predicate,
            "predicate_status" => "pass",
            "source_anchor_refs" => ["source:#{predicate}"],
            "evidence_refs" => ["evidence:#{predicate}"],
            "failing_anchor_refs" => [],
            "checker_source_or_command_ref" => Phase5DocsetDrift.checker_ref(),
            "release_manifest_ref" => "m10_scenario_212_semantic_closeout_predicate_check"
          }
        end)
    }
  end

  defp structural_only_semantic_profile do
    %{
      "structural_only_rejected" => false,
      "negative_structural_only_fixture_rejected" => false,
      "predicate_matrix" => []
    }
  end

  defp stack_lab_spec do
    """
    # Phase 5 Stack Lab Hardening Spec

    ## Scenario Matrix

    | Scenario | Name | Owner | Hardening profile | Runbook |
    | --- | --- | --- | --- | --- |
    | 201 | temporal_postgres_projection_drift | Mezzanine | drift | `runbooks/temporal_postgres_projection_drift.md` |
    | 210A | cost_attribution_missing | Outer Brain | cost | `runbooks/cost_attribution_missing.md` |

    ## Runtime Envelope Matrix
    """
  end

  defp runbook_readme do
    """
    # Phase 5 Runbooks

    ## Runbook Index

    - `temporal_postgres_projection_drift.md`
    - `cost_attribution_missing.md`

    ## Standard Fields
    """
  end

  defp runbook(scenario_id) do
    """
    # Runbook #{scenario_id}

    ## Failure Mode

    Failure mode.

    ## Expected Safe Action

    Safe action.

    ## Operator Procedure

    1. Identify the entry condition.
    2. Freeze unsafe processing.
    3. Run the positive fixture.
    4. Run the negative fixture.
    5. Capture evidence and escalate when refs cannot be joined.

    ## Evidence To Collect

    - evidence refs.

    ## Code Reduction Expectation

    Narrow unsafe path.

    ## Stop Conditions

    - missing evidence.
    """
  end

  defp empty_stack_lab_root! do
    root = Path.join(System.tmp_dir!(), "stack_lab_empty_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    root
  end
end
