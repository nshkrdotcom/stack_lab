defmodule StackLab.GnTenNodeLabTaskTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.StackLab.GnTen.NodeLab.Attach
  alias Mix.Tasks.StackLab.GnTen.NodeLab.Down
  alias Mix.Tasks.StackLab.GnTen.NodeLab.Probe
  alias Mix.Tasks.StackLab.GnTen.NodeLab.Status
  alias Mix.Tasks.StackLab.GnTen.NodeLab.Up
  alias StackLab.GnTenNodeLab.RunState

  import ExUnit.CaptureIO

  setup do
    Enum.each([Up, Status, Probe, Down, Attach], &Mix.Task.reenable/1)
    :ok
  end

  test "up requires a topology path" do
    assert_raise Mix.Error, ~r/expected --topology <path>/, fn ->
      Up.run([])
    end
  end

  test "status reports no active run as JSON" do
    state_path = temp_state_path()

    output =
      capture_io(fn ->
        Status.run(["--state", state_path, "--json"])
      end)

    assert {:ok, receipt} = Jason.decode(output)
    assert receipt["status"] == "no_active_run"
    assert receipt["state_path"] == state_path
  end

  test "status reports debug summary without cookie values" do
    state_path = temp_state_path()
    write_fixture_state(state_path)

    output =
      capture_io(fn ->
        Status.run(["--state", state_path, "--json"])
      end)

    assert {:ok, receipt} = Jason.decode(output)
    assert receipt["summary"]["run_id"] == "run-task"
    assert [%{"node_id" => "fixture_profile_0"}] = receipt["summary"]["nodes"]
    assert receipt["summary"]["artifact_hygiene"]["log_path_allowed?"] == true
    refute String.contains?(output, "cookie_value")
    refute String.contains?(output, "supersecret")
  end

  test "probe requires a logical node id" do
    assert_raise Mix.Error, ~r/expected --node <logical_node_id>/, fn ->
      Probe.run([])
    end
  end

  test "attach requires a logical node id" do
    assert_raise Mix.Error, ~r/expected --node <logical_node_id>/, fn ->
      Attach.run([])
    end
  end

  test "attach prints a redacted recipe from run state" do
    state_path = temp_state_path()
    write_fixture_state(state_path)

    output =
      capture_io(fn ->
        Attach.run(["--state", state_path, "--node", "fixture_profile_0", "--json"])
      end)

    assert {:ok, receipt} = Jason.decode(output)
    assert receipt["status"] == "not_attached"
    assert receipt["redacted_attach_recipe"]["secret_value_present?"] == false
    refute String.contains?(output, "cookie_value")
    refute String.contains?(output, "supersecret")
  end

  test "down is idempotent when no run state exists" do
    state_path = temp_state_path()

    output =
      capture_io(fn ->
        Down.run(["--state", state_path, "--json"])
      end)

    assert {:ok, receipt} = Jason.decode(output)
    assert receipt["status"] == "pass"
    assert receipt["cleanup"]["state_file_removed?"] == true
  end

  defp temp_state_path do
    Path.join(
      System.tmp_dir!(),
      "stack_lab_node_lab_task_state_#{System.unique_integer([:positive])}.json"
    )
  end

  defp write_fixture_state(state_path) do
    log_path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_node_lab_task_log_#{System.unique_integer([:positive])}.log"
      )

    File.write!(log_path, "fixture_profile_0 lifecycle ready\n")

    RunState.write!(
      %{
        "schema_version" => "stack_lab.gn_ten_node_lab.run.v1",
        "status" => "pass",
        "run_id" => "run-task",
        "topology_ref" => "topology://stack_lab/test",
        "node_count" => 1,
        "peers_kept?" => false,
        "cookie_value" => "supersecret",
        "boot_receipts" => [
          %{
            "node_id" => "fixture_profile_0",
            "profile" => "fixture_profile",
            "node" => "fixture_profile_0@localhost",
            "started_apps" => [],
            "owner_group_membership" => [],
            "ready?" => true
          }
        ],
        "cleanup" => [%{"node_id" => "fixture_profile_0", "stopped?" => true}],
        "log_artifact" => %{
          "path" => log_path,
          "contains_cookie?" => false,
          "contains_raw_payload?" => false
        }
      },
      state_path
    )
  end
end
