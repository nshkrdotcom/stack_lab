defmodule StackLab.GnTenNodeLab.RunnerTest do
  use ExUnit.Case, async: false

  alias StackLab.GnTenNodeLab.{RunState, Runner}

  test "boots a topology, records readiness, and cleans up peers" do
    state_path = temp_state_path()

    assert {:ok, receipt} =
             Runner.up(fixture_topology_path(),
               state_path: state_path,
               run_id: "run-test",
               keep?: true
             )

    assert receipt["status"] == "pass"
    assert receipt["state_path"] == state_path
    assert receipt["keep_requested?"] == true
    assert receipt["peers_kept?"] == false
    assert [%{"node_id" => "fixture_profile_0", "ready?" => true}] = receipt["boot_receipts"]
    assert [%{"stopped?" => true, "reachable_after_stop?" => false}] = receipt["cleanup"]

    assert %{"path" => log_path, "contains_cookie?" => false, "contains_raw_payload?" => false} =
             receipt["log_artifact"]

    assert File.exists?(log_path)
    log = File.read!(log_path)
    assert log =~ "fixture_profile_0"
    assert log =~ "lifecycle"
    refute log =~ "cookie_value"
    refute log =~ "raw_prompt"
    refute encoded_contains_cookie?(receipt)

    assert {:ok, status} = Runner.status(state_path: state_path)
    assert status["status"] == "pass"

    assert {:ok, probe} = Runner.probe("fixture_profile_0", state_path: state_path)
    assert probe["status"] == "pass"

    assert {:ok, down} = Runner.down(state_path: state_path)
    assert down["cleanup"]["state_file_removed?"] == true

    assert {:ok, status} = Runner.status(state_path: state_path)
    assert status["status"] == "no_active_run"
  end

  test "returns structured failure for missing topology" do
    assert {:error, receipt} =
             Runner.up("/tmp/stack_lab_missing_topology.exs",
               state_path: temp_state_path(),
               run_id: "run-missing"
             )

    assert receipt["status"] == "fail"

    assert [%{"code" => "topology_file_eval_failed"}] =
             stringify_failure_keys(receipt["failures"])
  end

  test "probe reports a missing node from run state" do
    state_path = temp_state_path()
    RunState.write!(%{"boot_receipts" => []}, state_path)

    assert {:error, receipt} = Runner.probe("unknown_node", state_path: state_path)
    assert [%{code: "node_not_found"}] = receipt["failures"]
  end

  defp fixture_topology_path do
    Path.expand("../../../priv/topologies/fixture_single_node.exs", __DIR__)
  end

  defp temp_state_path do
    Path.join(
      System.tmp_dir!(),
      "stack_lab_node_lab_state_#{System.unique_integer([:positive])}.json"
    )
  end

  defp encoded_contains_cookie?(receipt) do
    receipt
    |> Jason.encode!()
    |> String.contains?("cookie_value")
  end

  defp stringify_failure_keys(failures) do
    Enum.map(failures, fn failure ->
      Map.new(failure, fn {key, value} -> {to_string(key), value} end)
    end)
  end
end
