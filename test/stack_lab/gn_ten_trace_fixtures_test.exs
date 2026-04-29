defmodule StackLab.GnTen.TraceFixturesTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.GnTen.Trace.Export
  alias StackLab.GnTen.TraceFixtures

  test "builds deterministic local quick trace fixture" do
    assert {:ok, first} = TraceFixtures.build(:local_quick)
    assert {:ok, second} = TraceFixtures.build(:local_quick)
    assert first == second

    assert first["schema_version"] == "aitrace.single_node_proof_trace.v1"
    assert first["profile"] == "local_quick"
    assert first["proof_posture"]["authoritative_audit?"] == false
    assert first["proof_posture"]["production_deployment_proven?"] == false

    span_names = Enum.map(first["spans"], & &1["name"])
    assert "workspace_manifest_validated" in span_names
    assert "repo_local_ci" in span_names
    assert "stack_lab_proof" in span_names
    assert "trace_exported" in span_names
    assert :ok = TraceFixtures.validate_export(first)
  end

  test "rejects denied public keys nested inside exported trace" do
    assert {:ok, trace} = TraceFixtures.build(:local_quick)

    unsafe =
      Map.put(trace, "public", %{
        "nested" => [
          %{"provider_payload" => %{"model" => "unsafe"}}
        ]
      })

    assert {:error, failures} = TraceFixtures.validate_export(unsafe)

    assert Enum.any?(
             failures,
             &(&1.code == "trace_public_denied_key" and
                 &1.path == "public.nested.0.provider_payload")
           )
  end

  test "rejects unknown profiles" do
    assert {:error, failures} = TraceFixtures.build(:unknown)
    assert [%{code: "trace_unknown_profile", profile: "unknown"}] = failures
  end

  test "exports deterministic json through mix task" do
    out = Path.join(temp_dir!(), "local_quick.json")

    Export.run(["--profile", "local_quick", "--out", out])

    assert File.exists?(out)
    decoded = out |> File.read!() |> Jason.decode!()
    assert decoded["profile"] == "local_quick"
    assert :ok = TraceFixtures.validate_export(decoded)
  end

  test "deployment profile names every Phase J drill class" do
    assert {:ok, trace} = TraceFixtures.build(:deployment_single_node)

    span_names = Enum.map(trace["spans"], & &1["name"])
    assert "deploy_rehearsal" in span_names
    assert "restore_rehearsal" in span_names
    assert "substrate_health_rehearsal" in span_names
    assert "migration_rehearsal" in span_names
    assert "websocket_reconnect_rehearsal" in span_names
    assert trace["proof_posture"]["production_deployment_proven?"] == false
    assert :ok = TraceFixtures.validate_export(trace)
  end

  defp temp_dir! do
    dir = Path.join(System.tmp_dir!(), "stack_lab_trace_#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
