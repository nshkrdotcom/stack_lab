%{
  release_ref: "release://stack_lab/test-only/execution-plane-node/v1",
  release_mode: "test_only_release_wrapper",
  profile: :execution_plane_node,
  owner_repo: "execution_plane",
  owner_package: "core/execution_plane",
  otp_app: :execution_plane,
  expected_version: "0.1.0",
  facade_module: ExecutionPlane.RemoteFacade.Lane,
  owner_group: {ExecutionPlane.RemoteFacade.Lane, :lane},
  peer_mode_shape_ref: "receipt-shape://stack_lab/node-lab/peer-mode/v1",
  peer_mode_receipt_shape: [
    "facade_hosts",
    "node",
    "node_id",
    "owner_group_membership",
    "profile",
    "ready?",
    "started_apps"
  ]
}
