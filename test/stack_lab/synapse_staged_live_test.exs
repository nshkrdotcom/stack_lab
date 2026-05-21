defmodule StackLab.SynapseStagedLiveTest do
  use ExUnit.Case, async: true

  alias StackLab.SynapseStagedLive

  test "root staged-live wrapper validates the proof app receipt" do
    temp_dir = Path.join(System.tmp_dir!(), "stack_lab_synapse_staged_live_test")
    receipt_path = Path.join(temp_dir, "receipt.json")
    parent = self()

    runner = fn command, args, opts ->
      send(parent, {:command, command, args, opts})
      File.mkdir_p!(Path.dirname(receipt_path))
      File.write!(receipt_path, Jason.encode!(valid_receipt()))
      {"stack_lab.proof_app.synapse.staged_live.v1 passed\n", 0}
    end

    assert {:ok, receipt} =
             SynapseStagedLive.run(
               example_receipt_path: receipt_path,
               runner: runner,
               example_root: File.cwd!()
             )

    assert receipt["status"] == "pass"
    assert receipt["classification"] == "staging_live"
    assert receipt["no_bypass"]["status"] == "pass"
    assert_received {:command, _command, _args, opts}
    assert opts[:env] == [{"MIX_ENV", "test"}]
    assert opts[:env_allowlist] == ["MIX_ENV"]
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "stack_lab_synapse_staged_live_test"))
  end

  defp valid_receipt do
    %{
      "schema_version" => "stack_lab.synapse_staged_live.v1",
      "status" => "pass",
      "product_repo" => "synapse",
      "classification" => "staging_live",
      "no_bypass" => %{"status" => "pass"},
      "proofs" => %{
        "fixture_acceptance" => %{"status" => "pass"},
        "run_start" => %{"status" => "pass", "feature_status" => "staging_live"},
        "governed_pipeline" => %{
          "status" => "pass",
          "citadel_authority" => "allow",
          "jido_receipt_status" => "success",
          "execution_plane_status" => "ok"
        },
        "timeline" => %{"status" => "pass"},
        "denial_path" => %{
          "status" => "pass",
          "lower_invocation_submitted?" => false
        },
        "evidence_chain" => %{"status" => "pass"}
      }
    }
  end
end
