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
end
