defmodule StackLab.CitadelSpineHarness.ExecutionPlaneNodeBoundaryTest do
  use ExUnit.Case, async: false

  alias Citadel.AuthorityContract.ExecutionPlaneAuthorityVerifier
  alias ExecutionPlane.Admission.Rejection
  alias ExecutionPlane.ExecutionRequest
  alias ExecutionPlane.ExecutionResult
  alias ExecutionPlane.Lane.Capabilities
  alias ExecutionPlane.Node.LocalClient
  alias ExecutionPlane.Target.Attestation
  alias ExecutionPlane.Target.Descriptor
  alias Jido.Integration.V2.ExecutionGovernanceProjection
  alias Jido.Integration.V2.RuntimeRouter.ExecutionPlaneBoundary

  defmodule ProcessLane do
    @behaviour ExecutionPlane.Lane.Adapter

    def lane_id, do: :process

    def capabilities do
      Capabilities.new!(
        lane_id: "process",
        protocols: ["process"],
        surfaces: ["local_subprocess"],
        supports_execute: true,
        supports_stream: false
      )
    end

    def validate(%ExecutionRequest{lane_id: "process"}), do: :ok

    def execute(%ExecutionRequest{} = request, _opts) do
      {:ok,
       ExecutionResult.new!(
         execution_ref: request.execution_ref,
         status: "succeeded",
         output: %{"lane" => "process"},
         provenance: request.provenance
       )}
    end

    def stream(_request, _opts), do: {:error, Rejection.new(:stream_not_supported, "stream")}
  end

  defmodule HttpLane do
    @behaviour ExecutionPlane.Lane.Adapter

    def lane_id, do: :http

    def capabilities do
      Capabilities.new!(
        lane_id: "http",
        protocols: ["http"],
        surfaces: ["http"],
        supports_execute: true,
        supports_stream: false
      )
    end

    def validate(%ExecutionRequest{lane_id: "http"}), do: :ok

    def execute(%ExecutionRequest{} = request, _opts) do
      {:ok,
       ExecutionResult.new!(
         execution_ref: request.execution_ref,
         status: "succeeded",
         output: %{"lane" => "http"},
         provenance: request.provenance
       )}
    end

    def stream(_request, _opts), do: {:error, Rejection.new(:stream_not_supported, "stream")}
  end

  defmodule TargetVerifier do
    @behaviour ExecutionPlane.Target.Verifier

    def verifier_id, do: "stacklab-target-verifier"
    def attestation_types, do: ["stacklab-stub"]
    def capability_classes, do: ["local-erlexec-weak", "http-stub"]

    def handles?(attestation) do
      attestation = Attestation.new!(attestation)
      attestation.attestation_type == "stacklab-stub"
    end

    def verify(attestation, _opts) do
      attestation = Attestation.new!(attestation)

      if attestation.evidence["signature"] == "valid" do
        {:ok,
         Descriptor.new!(
           target_id: attestation.evidence["target_id"],
           lane_id: attestation.evidence["lane_id"],
           attested_capability_classes: attestation.evidence["classes"],
           verifier_id: verifier_id(),
           attestation_id: attestation.attestation_id,
           signature: "valid"
         )}
      else
        {:error, Rejection.new(:target_attestation_unverifiable, "invalid target attestation")}
      end
    end
  end

  defmodule Sink do
    @behaviour ExecutionPlane.Evidence.Sink

    def sink_id, do: "stacklab-proof-sink"

    def emit(evidence, _opts) do
      if pid = Process.whereis(:stack_lab_execution_plane_sink) do
        send(pid, {:node_evidence, evidence})
      end

      :ok
    end

    def flush(_opts), do: :ok
  end

  defmodule RemoteRuntimeClient do
    @behaviour ExecutionPlane.Runtime.Client

    def describe(opts), do: LocalClient.describe(opts)
    def admit(request, opts), do: LocalClient.admit(request, opts)

    def execute(request, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:remote_runtime_client_execute, request})
      LocalClient.execute(request, opts)
    end

    def stream(request, opts), do: LocalClient.stream(request, opts)
    def cancel(execution_ref, opts), do: LocalClient.cancel(execution_ref, opts)
  end

  setup do
    Process.register(self(), :stack_lab_execution_plane_sink)

    on_exit(fn ->
      if Process.whereis(:stack_lab_execution_plane_sink) do
        Process.unregister(:stack_lab_execution_plane_sink)
      end
    end)

    :ok
  end

  test "proves local node process and HTTP targets through the runtime-client boundary" do
    server = start_node!()
    register_common!(server)
    register_target!(server, "local-process", "process", ["local-erlexec-weak"])
    register_target!(server, "http-target", "http", ["http-stub"])
    :ok = ExecutionPlane.Node.complete_registration(server: server)

    assert {:ok, process_result} =
             process_projection(["local-erlexec-weak"])
             |> ExecutionPlaneBoundary.admission_request(%{"command" => "echo ok"})
             |> LocalClient.execute(server: server)

    assert process_result.output["lane"] == "process"

    assert {:ok, http_result} =
             http_projection(["http-stub"])
             |> ExecutionPlaneBoundary.admission_request(%{
               "method" => "GET",
               "url" => "https://example.test"
             })
             |> LocalClient.execute(server: server)

    assert http_result.output["lane"] == "http"
    assert_receive {:node_evidence, %{evidence_type: "admission.accepted"}}
    assert_receive {:node_evidence, %{evidence_type: "target.selected"}}
  end

  test "rejects unsigned authority and unattested targets" do
    server = start_node!()
    ExecutionPlane.Node.register_lane(ProcessLane, server: server)
    ExecutionPlane.Node.register_target_verifier(TargetVerifier, server: server)
    ExecutionPlane.Node.register_evidence_sink(Sink, server: server)
    :ok = ExecutionPlane.Node.complete_registration(server: server)

    request =
      process_projection(["local-erlexec-weak"])
      |> ExecutionPlaneBoundary.admission_request(%{"command" => "echo ok"})

    assert {:error, result} = LocalClient.execute(request, server: server)
    assert result.error["reason"] == "authority_verifier_missing"

    unattested =
      attestation("bad-target", "process", ["local-erlexec-weak"], signature: "invalid")

    assert {:error, %Rejection{reason: "target_attestation_unverifiable"}} =
             ExecutionPlane.Node.connect_target(
               unattested,
               ExecutionPlane.Node.TargetClient.Adapter,
               server: server
             )
  end

  test "proves JidoIntegration owns fallback and a remote runtime-client stub can replace local client" do
    server = start_node!()
    register_common!(server)
    register_target!(server, "local-process", "process", ["local-erlexec-weak"])
    :ok = ExecutionPlane.Node.complete_registration(server: server)

    assert {:ok, result, attempts} =
             ExecutionPlaneBoundary.execute_fallback_ladder(
               process_projection(["spiffe://prod/microvm-strict@v1", "local-erlexec-weak"]),
               %{"command" => "echo ok"},
               RemoteRuntimeClient,
               runtime_client_opts: [server: server, test_pid: self()]
             )

    assert result.status == "succeeded"

    assert Enum.map(attempts, &{&1.rung, &1.attestation_class, &1.status}) == [
             {1, "spiffe://prod/microvm-strict@v1", :rejected},
             {2, "local-erlexec-weak", :succeeded}
           ]

    assert_receive {:remote_runtime_client_execute, first_request}
    assert first_request.acceptable_attestation.classes == ["spiffe://prod/microvm-strict@v1"]

    assert_receive {:remote_runtime_client_execute, second_request}
    assert second_request.acceptable_attestation.classes == ["local-erlexec-weak"]
  end

  defp start_node! do
    name = StackLab.CitadelSpineHarness.ExecutionPlaneNodeBoundaryTest.Server
    start_supervised!({ExecutionPlane.Node.Server, name: name, node_id: Atom.to_string(name)})
  end

  defp register_common!(server) do
    ExecutionPlane.Node.register_lane(ProcessLane, server: server)
    ExecutionPlane.Node.register_lane(HttpLane, server: server)
    ExecutionPlane.Node.register_target_verifier(TargetVerifier, server: server)
    ExecutionPlane.Node.register_evidence_sink(Sink, server: server)

    ExecutionPlane.Node.register_authority_verifier(ExecutionPlaneAuthorityVerifier,
      server: server
    )
  end

  defp register_target!(server, target_id, lane_id, classes) do
    {:ok, _descriptor} =
      ExecutionPlane.Node.connect_target(
        attestation(target_id, lane_id, classes),
        ExecutionPlane.Node.TargetClient.Adapter,
        server: server
      )
  end

  defp attestation(target_id, lane_id, classes, opts \\ []) do
    Attestation.new!(
      attestation_id: "attestation-#{target_id}",
      attestation_type: "stacklab-stub",
      evidence: %{
        "target_id" => target_id,
        "lane_id" => lane_id,
        "classes" => classes,
        "signature" => Keyword.get(opts, :signature, "valid")
      },
      claimed_capability_classes: classes
    )
  end

  defp process_projection(classes), do: projection("process", "host_local", "cli", classes)
  defp http_projection(classes), do: projection("http", "remote_scope", "http", classes)

  defp projection(family, placement_intent, target_kind, classes) do
    ExecutionGovernanceProjection.new!(%{
      contract_version: "v1",
      execution_governance_id: "governance-#{family}-#{System.unique_integer([:positive])}",
      authority_ref: %{
        "decision_id" => "decision-1",
        "policy_version" => "policy-2026-04-24",
        "decision_hash" => String.duplicate("a", 64)
      },
      sandbox: %{
        "level" => "strict",
        "egress" => "restricted",
        "approvals" => "manual",
        "acceptable_attestation" => classes,
        "allowed_tools" => ["runtime.execute"],
        "file_scope_ref" => "workspace://stack-lab/proof",
        "file_scope_hint" => "/tmp/stack-lab-proof"
      },
      boundary: %{
        "boundary_class" => "workspace_session",
        "trust_profile" => "trusted_operator",
        "requested_attach_mode" => "fresh_or_reuse",
        "requested_ttl_ms" => 60_000
      },
      topology: %{
        "topology_intent_id" => "topology-1",
        "session_mode" => "attached",
        "coordination_mode" => "single_target",
        "topology_epoch" => 1,
        "routing_hints" => %{}
      },
      workspace: %{
        "workspace_profile" => "project_workspace",
        "logical_workspace_ref" => "workspace://stack-lab/proof",
        "mutability" => "read_write"
      },
      resources: %{
        "resource_profile" => "standard",
        "cpu_class" => nil,
        "memory_class" => nil,
        "wall_clock_budget_ms" => 120_000
      },
      placement: %{
        "execution_family" => family,
        "placement_intent" => placement_intent,
        "target_kind" => target_kind,
        "node_affinity" => "same-node"
      },
      operations: %{
        "allowed_operations" => ["runtime.execute"],
        "effect_classes" => [family]
      },
      extensions: %{}
    })
  end
end
