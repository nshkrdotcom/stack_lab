defmodule StackLab.GnTenNodeLabTaskTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.StackLab.GnTen.NodeLab.Down
  alias Mix.Tasks.StackLab.GnTen.NodeLab.Probe
  alias Mix.Tasks.StackLab.GnTen.NodeLab.Status
  alias Mix.Tasks.StackLab.GnTen.NodeLab.Up

  import ExUnit.CaptureIO

  setup do
    Enum.each([Up, Status, Probe, Down], &Mix.Task.reenable/1)
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

  test "probe requires a logical node id" do
    assert_raise Mix.Error, ~r/expected --node <logical_node_id>/, fn ->
      Probe.run([])
    end
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
end
