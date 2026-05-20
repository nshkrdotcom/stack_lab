defmodule StackLab.SynapseAcceptanceTest do
  use ExUnit.Case, async: true

  alias StackLab.SynapseAcceptance

  test "root acceptance wrapper validates the proof app receipt" do
    temp_dir = Path.join(System.tmp_dir!(), "stack_lab_synapse_acceptance_test")
    receipt_path = Path.join(temp_dir, "receipt.json")
    parent = self()

    runner = fn command, args, opts ->
      send(parent, {:command, command, args, opts})
      File.mkdir_p!(Path.dirname(receipt_path))
      File.write!(receipt_path, Jason.encode!(valid_receipt()))
      {"stack_lab.proof_app.synapse.acceptance passed\n", 0}
    end

    assert {:ok, receipt} =
             SynapseAcceptance.run(
               example_receipt_path: receipt_path,
               runner: runner,
               example_root: File.cwd!()
             )

    assert receipt["status"] == "pass"
    assert receipt["no_bypass"]["status"] == "pass"
    assert_received {:command, _command, _args, opts}
    assert opts[:env] == [{"MIX_ENV", "test"}]
    assert opts[:env_allowlist] == ["MIX_ENV"]
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "stack_lab_synapse_acceptance_test"))
  end

  defp valid_receipt do
    %{
      "schema_version" => "stack_lab.synapse_product_acceptance.v1",
      "status" => "pass",
      "product_repo" => "synapse",
      "no_bypass" => %{"status" => "pass"},
      "proofs" => %{
        "run_start" => %{"status" => "pass"},
        "turn_submission" => %{"status" => "accepted"},
        "review_decision" => %{"status" => "accepted"}
      }
    }
  end
end
