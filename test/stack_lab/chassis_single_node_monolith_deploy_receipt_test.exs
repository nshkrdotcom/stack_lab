defmodule StackLab.ChassisSingleNodeMonolithDeployReceiptTest do
  use ExUnit.Case, async: true

  alias StackLab.ChassisSingleNodeMonolithDeployReceipt

  test "links the existing Chassis monolith proof to product proof refs" do
    bridge_run = fn :chassis ->
      {:ok,
       %{
         run_ref: "run:stacklab:chassis:test",
         tag: :chassis,
         passed: 1,
         failed: 0,
         skipped: 0,
         proofs: [
           %{
             name: "chassis.deployment.profile_monolith_local",
             status: :pass,
             duration_us: 10,
             evidence: %{
               app_ref: "app:extravaganza:installation:dev:tenant:dev",
               receipt_ref: "receipt:deployment:test",
               node_count: 1,
               profile_ref: "profile:monolith"
             }
           }
         ]
       }}
    end

    assert {:ok, receipt} =
             ChassisSingleNodeMonolithDeployReceipt.run(chassis_bridge_run: bridge_run)

    assert receipt.schema_version ==
             "stack_lab.chassis_single_node_monolith_deploy_receipt.v1"

    assert receipt.status == "pass"
    assert receipt.classification == "local_single_node"
    assert receipt.chassis.deployment_receipt_ref == "receipt:deployment:test"
    assert receipt.chassis.profile_ref == "profile:monolith"
    assert receipt.chassis.node_count == 1

    assert receipt.product_proofs.extravaganza.command ==
             "MIX_ENV=test mix stack_lab.extravaganza.external_acceptance --json"

    assert receipt.product_proofs.synapse_staged_live.command ==
             "MIX_ENV=test mix stack_lab.synapse.staged_live.v1 --json"

    refute inspect(receipt) =~ "PRIVATE"
  end

  test "fails closed when the Chassis monolith proof is absent" do
    bridge_run = fn :chassis -> {:ok, %{tag: :chassis, proofs: []}} end

    assert {:error, %{code: "monolith_chassis_proof_missing"}} =
             ChassisSingleNodeMonolithDeployReceipt.run(chassis_bridge_run: bridge_run)
  end

  test "fails closed when monolith evidence is not single-node" do
    bridge_run = fn :chassis ->
      {:ok,
       %{
         tag: :chassis,
         proofs: [
           %{
             name: "chassis.deployment.profile_monolith_local",
             status: :pass,
             evidence: %{
               app_ref: "app:extravaganza:installation:dev:tenant:dev",
               receipt_ref: "receipt:deployment:test",
               node_count: 2,
               profile_ref: "profile:monolith"
             }
           }
         ]
       }}
    end

    assert {:error, %{code: "bad_node_count", node_count: 2}} =
             ChassisSingleNodeMonolithDeployReceipt.run(chassis_bridge_run: bridge_run)
  end
end
