defmodule StackLab.GnTenDistributionPreflightTest do
  use ExUnit.Case, async: false

  alias StackLab.GnTen.DistributionPreflight

  test "runs the local distribution preflight and writes a bounded receipt" do
    path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_distribution_preflight_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, receipt} = DistributionPreflight.run(receipt_path: path)

    assert receipt["schema_version"] == "stack_lab.gn_ten.distribution_preflight.v1"
    assert receipt["status"] == "pass"
    assert receipt["cookie_posture"]["secret_value_present?"] == false
    assert receipt["epmd"]["executable_found?"] == true
    assert receipt["distribution"]["node_alive?"] == true
    assert receipt["peer_probe"]["started?"] == true
    assert receipt["peer_probe"]["stopped?"] == true
    assert receipt["peer_probe"]["reachable_after_stop?"] == false

    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["receipt_ref"] == DistributionPreflight.receipt_ref()
    refute encoded_contains_cookie?(decoded)
  end

  test "reports a missing epmd executable as a structured failure" do
    assert {:error, failure} = DistributionPreflight.ensure_epmd_started(nil)
    assert failure.code == "epmd_not_found"
  end

  test "validates generated node names and rejects duplicate names" do
    assert {:ok, controller_name} = DistributionPreflight.generated_node_name(:controller)
    assert {:ok, peer_name} = DistributionPreflight.generated_node_name(:peer)

    assert controller_name
           |> Atom.to_string()
           |> String.starts_with?("stack_lab_preflight_controller_")

    assert peer_name |> Atom.to_string() |> String.starts_with?("stack_lab_preflight_peer_")

    assert :ok = DistributionPreflight.validate_node_name_available(:not_currently_started_node)

    if Node.alive?() do
      assert {:error, failure} = DistributionPreflight.validate_node_name_available(Node.self())
      assert failure.code == "duplicate_node_name"
    end
  end

  test "validates generated cookies without leaking the cookie value" do
    assert {:ok, cookie} = DistributionPreflight.generate_cookie()
    assert is_binary(cookie)

    assert :ok = DistributionPreflight.validate_cookie(cookie)
    assert {:error, failure} = DistributionPreflight.validate_cookie("short")
    assert failure.code == "invalid_cookie"

    posture = DistributionPreflight.cookie_posture(cookie)
    assert posture["posture"] == "generated_redacted_not_applied_in_phase2"
    assert posture["secret_value_present?"] == false
    refute Map.has_key?(posture, "cookie")
  end

  test "validates distribution port ranges and produces VM args" do
    assert {:ok, range} = DistributionPreflight.validate_port_range(43_000..43_100)
    assert range["min"] == 43_000
    assert range["max"] == 43_100
    assert "-kernel" in range["vm_args"]

    assert {:error, failure} = DistributionPreflight.validate_port_range(43_100..43_000//-1)
    assert failure.code == "invalid_dist_port_range"

    assert {:error, failure} = DistributionPreflight.validate_port_range(0..10)
    assert failure.code == "invalid_dist_port_range"
  end

  test "cleans up a probe peer when the probe callback fails" do
    assert {:error, failure} =
             DistributionPreflight.with_probe_peer(fn _peer ->
               raise "forced probe failure"
             end)

    assert failure.code == "peer_probe_failed"
    assert failure.cleanup["stopped?"] == true
    assert failure.cleanup["reachable_after_stop?"] == false
  end

  defp encoded_contains_cookie?(receipt) do
    receipt
    |> Jason.encode!()
    |> String.contains?("cookie_value")
  end
end
