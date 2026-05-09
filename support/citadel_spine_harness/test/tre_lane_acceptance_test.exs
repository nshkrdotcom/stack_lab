defmodule StackLab.CitadelSpineHarness.TreLaneAcceptanceTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness

  defp direct_run_entrypoint do
    "Mezzanine.IntegrationBridge.DirectRun" <> "Dispatch" <> "er.invoke_run_intent/2"
  end

  defp direct_run_module_name do
    "Mezzanine.IntegrationBridge.DirectRun" <> "Dispatch" <> "er"
  end

  test "scenario is neutral StackLab acceptance, not Extravaganza runtime logic" do
    scenario = CitadelSpineHarness.tre_lane_acceptance_scenario()

    assert scenario.name == :tre_lane_acceptance
    assert scenario.owner_repo == :stack_lab
    assert scenario.product_repo == :none
    assert scenario.path == [:stack_lab, :mezzanine, :jido_integration, :execution_plane]

    assert scenario.cases == %{
             deterministic_fixture_runner: %{kind: :neutral_lower_lane},
             installed_rex_runner: %{kind: :operator_supplied_runner, requires: :runner_path}
           }
  end

  @tag timeout: 120_000
  test "deterministic runner case exercises the public TRE lower lane and records claim refs" do
    assert {:ok, receipt} =
             CitadelSpineHarness.exercise_tre_lane_acceptance(:deterministic_fixture_runner)

    assert receipt.scenario_id == "tre.neutral_execution_plane.v1"
    assert receipt.acceptance_kind == :neutral_tre_lane
    assert receipt.imports_extravaganza_internals? == false
    assert receipt.path == [:stack_lab, :mezzanine, :jido_integration, :execution_plane]

    assert receipt.public_entrypoints == [
             direct_run_entrypoint(),
             "Jido.Integration.V2.invoke/3",
             "ExecutionPlane.Process.TreRhai.execute/2"
           ]

    assert receipt.runtime_profile.runtime_profile_ref ==
             "runtime-profile://stack-lab/tre/local"

    assert receipt.lower_runtime.lower_runtime_kind == "tre_rhai"
    assert receipt.lower_runtime.policy_bundle_hash =~ "sha256:"
    assert receipt.lower_runtime.cedar_schema_hash =~ "sha256:"
    assert receipt.lower_runtime.script_hash =~ "sha256:"
    assert receipt.runner.hash =~ "sha256:"
    assert receipt.runner.kind == :fixture_subprocess_contract

    assert receipt.jido_control_plane.run_status == :completed
    assert receipt.execution_plane_receipt.status == "succeeded"
    assert receipt.execution_plane_receipt.runner_output == "stack-lab-tre-ok"

    assert String.starts_with?(
             receipt.receipt_refs.execution_plane_receipt_ref,
             "execution-plane-tre-receipt://"
           )

    assert String.starts_with?(
             receipt.receipt_refs.jido_governed_lower_receipt_ref,
             "lower-receipt://"
           )

    assert String.starts_with?(
             receipt.receipt_refs.mezzanine_governed_lower_receipt_ref,
             "lower-receipt://"
           )

    assert receipt.receipt_refs.projection_ref ==
             "projection://stack-lab/tre/neutral-lane"

    assert receipt.artifact_refs != []
    assert receipt.event_refs != []

    assert Enum.map(receipt.acceptance_claim_rows, & &1.id) == [
             "tre_lower_lane_public_path",
             "tre_authority_policy_refs_present",
             "tre_script_hash_bound",
             "tre_runner_hash_recorded",
             "tre_mezzanine_receipt_reduced"
           ]
  end

  test "installed runner case fails closed when no runner path is supplied" do
    assert {:error, {:runner_path_required, :installed_rex_runner}} =
             CitadelSpineHarness.exercise_tre_lane_acceptance(:installed_rex_runner)
  end

  test "runbook documents the root command and optional rex-runner path" do
    runbook =
      StackLab.CitadelSpineHarness.repo_roots().stack_lab
      |> Path.join("docs/runbooks/tre_lane_acceptance.md")
      |> File.read!()

    assert String.contains?(runbook, "mix stack_lab.tre_lane_check")
    assert String.contains?(runbook, "--runner-path /absolute/path/to/rex-runner")
    assert String.contains?(runbook, direct_run_module_name())
    assert String.contains?(runbook, "ExecutionPlane.Process.TreRhai")
    assert String.contains?(runbook, "does not import or execute Extravaganza internals")
  end
end
