defmodule StackLab.SynapseLiveSliceTest do
  use ExUnit.Case, async: true

  alias StackLab.SynapseLiveSlice

  test "root live-slice wrapper validates the proof app receipt" do
    temp_dir = Path.join(System.tmp_dir!(), "stack_lab_synapse_live_slice_test")
    receipt_path = Path.join(temp_dir, "receipt.json")

    runner = fn _command, _args, _opts ->
      File.mkdir_p!(Path.dirname(receipt_path))
      File.write!(receipt_path, Jason.encode!(valid_receipt()))
      {"stack_lab.proof_app.synapse.live_slice passed\n", 0}
    end

    assert {:ok, receipt} =
             SynapseLiveSlice.run(
               example_receipt_path: receipt_path,
               runner: runner,
               example_root: File.cwd!()
             )

    assert receipt["status"] == "pass"
    assert receipt["classification"] == "live_stack_deterministic"
    assert receipt["no_bypass"]["status"] == "pass"
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "stack_lab_synapse_live_slice_test"))
  end

  defp valid_receipt do
    %{
      "schema_version" => "stack_lab.synapse_live_slice.v1",
      "status" => "pass",
      "product_repo" => "synapse",
      "classification" => "live_stack_deterministic",
      "no_bypass" => %{"status" => "pass"},
      "proofs" => %{
        "fixture_acceptance" => %{"status" => "pass"},
        "run_start" => %{"status" => "pass"},
        "turn_submission" => %{"status" => "accepted"},
        "await" => %{"status" => "accepted"},
        "runtime_projection" => %{"status" => "pass"},
        "evidence_receipt" => %{"status" => "pass"},
        "denial_path" => %{"status" => "pass"}
      }
    }
  end
end
