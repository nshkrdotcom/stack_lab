defmodule StackLab.Examples.TRINITYParityHarnessTest do
  use ExUnit.Case, async: true

  alias StackLab.Examples.TRINITYParityHarness
  alias StackLab.Examples.TRINITYParityHarness.NoBypassFixtures

  @help_output """
  mix trinity.artifact.fetch             # Downloads artifact
  mix trinity.demo                       # Runs demo
  mix trinity.env.check                  # Checks env
  mix trinity.gates                      # Runs gates
  mix trinity.hitl.adapted               # HITL adapted
  mix trinity.hitl.base_qwen             # HITL base
  mix trinity.hitl.gpu                   # HITL gpu
  mix trinity.hitl.head_route            # HITL head route
  mix trinity.hitl.mock_loop             # HITL mock loop
  mix trinity.hitl.vector                # HITL vector
  mix trinity.parity.check               # Parity
  mix trinity.route.demo                 # Route demo
  mix trinity.sakana.export_adapted      # Export
  mix trinity.sakana.import_python       # Import
  mix trinity.sakana.large_tensor_chunks # Chunks
  mix trinity.sakana.parity_sample       # Sample
  mix trinity.sakana.router_trace        # Trace
  """

  test "default fast parity receipt signs off executable rows and defers heavy rows" do
    assert {:ok, receipt} =
             TRINITYParityHarness.run(
               command_runner: fn _root, ["help", "--search", "trinity"] ->
                 @help_output
               end
             )

    assert receipt.status == :pass

    assert Enum.map(receipt.rows, & &1.id) == [
             :source_inventory,
             :task_surface,
             :prompt_eval_fixtures,
             :no_bypass_fixtures,
             :deferred_cuda_parity,
             :deferred_stage_parity
           ]

    assert Enum.find(receipt.rows, &(&1.id == :task_surface)).status == :pass
    assert Enum.find(receipt.rows, &(&1.id == :deferred_cuda_parity)).status == :deferred
  end

  test "task-surface row shells old and new command surfaces through a runner" do
    assert {:ok, receipt} =
             TRINITYParityHarness.run(
               rows: [:task_surface],
               command_runner: fn _root, ["help", "--search", "trinity"] -> @help_output end
             )

    assert [%{id: :task_surface, status: :pass, details: details}] = receipt.rows
    assert length(details.old) == 17
    assert details.old == details.new
  end

  test "phase 15 CUDA and stage rows sign off generated receipts" do
    phase15_dir = write_phase15_receipts!()

    assert {:ok, receipt} =
             TRINITYParityHarness.run(
               rows: [:cuda_parity, :stage_parity],
               phase15_dir: phase15_dir
             )

    assert receipt.status == :pass

    assert Enum.map(receipt.rows, &{&1.id, &1.status}) == [
             cuda_parity: :pass,
             stage_parity: :pass
           ]

    cuda = Enum.find(receipt.rows, &(&1.id == :cuda_parity))
    assert cuda.details.stable_matches["agent_id"] == 37
    assert cuda.details.route_hash_matches == 0

    stage = Enum.find(receipt.rows, &(&1.id == :stage_parity))
    assert stage.details.strict_stage_tolerances?
  end

  test "no-bypass fixtures fail and pass in the intended places" do
    results = NoBypassFixtures.run()

    assert Enum.map(results, &{&1.id, &1.status}) == [
             self_hosted_inference_core_import: :open_defect,
             crucible_factorization_import: :open_defect,
             trinity_router_import: :pass,
             appkit_router_decision_projection_import: :pass
           ]

    assert Enum.all?(results, &(&1.status == &1.expected_status))
  end

  defp write_phase15_receipts! do
    root =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_trinity_phase15_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)

    old_cases = Enum.map(1..37, &phase15_case(&1, "old-route-#{&1}"))
    new_cases = Enum.map(1..37, &phase15_case(&1, "new-route-#{&1}"))

    File.write!(
      Path.join(root, "coordinator_cuda_qwen_router_prompt_eval_logits.json"),
      Jason.encode!(%{cases: old_cases})
    )

    File.write!(
      Path.join(root, "framework_cuda_qwen_router_prompt_eval_logits.json"),
      Jason.encode!(%{cases: new_cases})
    )

    log = "Summary\n  passed: 37\n  failed: 0\n\nPASS qwen_router_prompt_eval\n"
    File.write!(Path.join(root, "coordinator_cuda_qwen_router_prompt_eval.log"), log)
    File.write!(Path.join(root, "framework_cuda_qwen_router_prompt_eval.log"), log)

    File.write!(
      Path.join(root, "stage_parity_summary.json"),
      Jason.encode!(%{
        ok: true,
        exit_status: 0,
        python_report: "python.json",
        elixir_report: "elixir.json",
        comparator_args: ["python.json", "elixir.json", "--strict-stage-tolerances"]
      })
    )

    root
  end

  defp phase15_case(index, route_hash) do
    %{
      id: "case-#{index}",
      agent_id: rem(index, 7),
      role_id: rem(index, 3),
      token_count: index + 10,
      transcript_hash: "transcript-#{index}",
      route_hash: route_hash
    }
  end
end
