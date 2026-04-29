defmodule StackLab.GnTen.DeploymentDrillsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Mix.Tasks.GnTen.Deploy.Rehearse
  alias Mix.Tasks.GnTen.Deploy.Report
  alias StackLab.GnTen.DeploymentDrills

  @date "2026-04-28"

  test "rehearse task requires --drill" do
    assert_raise Mix.Error, ~r/expected --drill <id>/, fn ->
      Rehearse.run([])
    end
  end

  test "unknown drill aborts before writing a receipt" do
    out_dir = temp_dir!()

    assert_raise Mix.Error, ~r/deploy_drill_unknown/, fn ->
      Rehearse.run(["--drill", "unknown", "--out", out_dir])
    end

    assert File.ls!(out_dir) == []
  end

  test "receipt missing required spans is rejected" do
    out_dir = temp_dir!()

    assert {:ok, result} =
             DeploymentDrills.rehearse("cold_deploy", out_dir: out_dir, date: @date)

    receipt =
      result.json_path
      |> File.read!()
      |> Jason.decode!()
      |> Map.update!("spans", &tl/1)

    assert {:error, failures} = DeploymentDrills.validate_receipt(receipt)
    assert Enum.any?(failures, &(&1.code == "deployment_receipt_missing_required_span"))
  end

  test "all drills write weak-attestation receipts and report passes" do
    out_dir = temp_dir!()

    assert {:ok, result} = DeploymentDrills.rehearse("all", out_dir: out_dir, date: @date)
    assert result.drill_count == 5
    assert DeploymentDrills.drill_ids() == ~w(
             cold_deploy
             backup_restore
             substrate_health
             zero_downtime_migration
             websocket_reconnect
           )

    assert {:ok, report} = DeploymentDrills.report(out_dir: out_dir)
    assert report["schema_version"] == "gn_ten_deployment_rehearsal_report_v1"
    assert report["profile"] == "deployment_single_node"
    assert report["drill_count"] == 5
    assert report["proof_posture"]["production_deployment_proven?"] == false

    Enum.each(DeploymentDrills.drill_ids(), fn drill ->
      receipt = out_dir |> Path.join("#{drill}.json") |> File.read!() |> Jason.decode!()
      assert receipt["proof_posture"]["production_deployment_proven?"] == false
      assert receipt["proof_posture"]["authoritative_audit?"] == false
      assert :ok = DeploymentDrills.validate_receipt(receipt)
    end)
  end

  test "report task summarizes generated receipts" do
    out_dir = temp_dir!()
    assert {:ok, _result} = DeploymentDrills.rehearse("all", out_dir: out_dir, date: @date)

    output =
      capture_io(fn ->
        Report.run(["--dir", out_dir])
      end)

    assert output =~ "gn_ten.deploy.report passed"
    assert output =~ "drill_count=5"
    assert output =~ "receipt=cold_deploy"
    assert output =~ "receipt=websocket_reconnect"
  end

  defp temp_dir! do
    dir =
      Path.join(System.tmp_dir!(), "stack_lab_deploy_drill_#{System.unique_integer([:positive])}")

    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
