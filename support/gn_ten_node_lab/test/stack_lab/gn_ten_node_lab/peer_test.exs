defmodule StackLab.GnTenNodeLab.PeerTest do
  use ExUnit.Case, async: false

  alias StackLab.GnTenNodeLab.{Cookie, Peer, Preflight}

  test "generates redacted cookie posture" do
    cookie = Cookie.generate()

    assert :ok = Cookie.validate(cookie)
    assert {:error, failure} = Cookie.validate("short")
    assert failure.code == "invalid_cookie"

    posture = Cookie.posture(cookie)
    assert posture["secret_value_present?"] == false
    refute Map.has_key?(posture, "cookie")
  end

  test "starts a peer, syncs code paths, calls it, and cleans up" do
    assert {:ok, result} =
             Peer.with_peer(fn peer ->
               assert :ok = Peer.sync_code_paths(peer)
               assert {:ok, peer_node} = Peer.remote_call(peer, :erlang, :node, [])
               assert peer_node == peer.peer_node
               :ok
             end)

    assert result == :ok
  end

  test "cleans up a peer when the callback fails" do
    assert {:error, failure} =
             Peer.with_peer(fn _peer ->
               raise "forced failure"
             end)

    assert failure.code == "peer_callback_failed"
    assert failure.cleanup["stopped?"] == true
    assert failure.cleanup["reachable_after_stop?"] == false
  end

  test "runs a package-owned preflight receipt" do
    path =
      Path.join(
        System.tmp_dir!(),
        "stack_lab_gn_ten_node_lab_preflight_#{System.unique_integer([:positive])}.json"
      )

    on_exit(fn -> File.rm(path) end)

    assert {:ok, receipt} = Preflight.run(receipt_path: path)
    assert receipt["schema_version"] == "stack_lab.gn_ten_node_lab.preflight.v1"
    assert receipt["status"] == "pass"
    assert receipt["cookie_posture"]["secret_value_present?"] == false
    assert receipt["peer_probe"]["code_paths_synced?"] == true
    assert receipt["peer_probe"]["stopped?"] == true

    assert {:ok, decoded} = path |> File.read!() |> Jason.decode()
    assert decoded["receipt_ref"] == "receipt://stack_lab/gn_ten_node_lab_preflight/latest"
  end
end
