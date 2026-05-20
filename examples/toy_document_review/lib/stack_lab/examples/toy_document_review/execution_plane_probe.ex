defmodule StackLab.Examples.ToyDocumentReview.ExecutionPlaneProbe do
  @moduledoc false

  alias ExecutionPlane.Contracts.ExecutionIntentEnvelope.V1, as: ExecutionIntentEnvelope
  alias ExecutionPlane.Contracts.ExecutionRoute.V1, as: ExecutionRoute
  alias ExecutionPlane.Contracts.HttpExecutionIntent.V1, as: HttpExecutionIntent
  alias ExecutionPlane.Contracts.NoEgressPolicy.V1, as: NoEgressPolicy
  alias ExecutionPlane.Kernel, as: ExecutionKernel
  alias StackLab.Examples.ToyDocumentReview.LocalHttpService

  def run do
    route = execution_route()
    intent = http_intent()

    case ExecutionKernel.build_dispatch(intent, route) do
      {:ok, plan} ->
        {:ok,
         %{
           accepted?: true,
           route_id: plan.route_id,
           family: plan.family,
           protocol: plan.protocol,
           timeout_ms: plan.timeout_ms,
           lower_simulation_configured?:
             not is_nil(plan.route.resolved_target["lower_simulation"])
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execution_route do
    ExecutionRoute.new!(%{
      route_id: "route-toy-document-review-http",
      family: "http",
      protocol: "http",
      transport_family: "http",
      placement_family: "local",
      resolved_target: %{
        "target_id" => "toy-document-review-local-http",
        "method" => "post",
        "url" => "http://127.0.0.1/toy-document-review",
        "lower_simulation" => %{
          "scenario_ref" => "lower-simulation://toy-document-review/http",
          "status" => "succeeded",
          "side_effect_policy" => "deny_external_egress",
          "raw_payload" => %{"status" => "simulated"},
          "no_egress_policy" =>
            NoEgressPolicy.dump(NoEgressPolicy.default_lower_boundary_policy!())
        }
      },
      resolved_budget: %{"timeout_ms" => 5_000},
      lineage: execution_lineage("route-toy-document-review-http")
    })
  end

  defp http_intent do
    HttpExecutionIntent.new!(%{
      envelope:
        ExecutionIntentEnvelope.new!(%{
          intent_id: "intent-toy-document-review-http",
          family: "http",
          protocol: "http",
          trace_id: "trace://toy-document-review/execution-plane",
          idempotency_key: "toy-document-review-execution-plane",
          boundary_session_id: "boundary-session-toy-document-review",
          decision_id: "decision-toy-document-review",
          lease_ref: LocalHttpService.default_lease_ref(),
          target_ref: "target://toy-document-review/local-http",
          attach_grant_ref: "attach-grant://toy-document-review/local-http",
          target_auth_posture_ref: "target-posture://toy-document-review/local-http",
          workspace_ref: "workspace://toy-document-review/local",
          no_egress_posture_ref: "no-egress-posture://toy-document-review/local-http",
          credential_handle_refs: ["credential-handle://toy-document-review/local-http"],
          attempt_ref: "attempt://toy-document-review/execution-plane",
          requested_capabilities: ["http.unary"],
          extensions: %{proof_app: "toy_document_review"}
        }),
      request_shape: "request_response",
      stream_mode: "unary",
      headers: %{"accept" => "application/json"},
      body: %{"document_id" => "doc-001"},
      egress_surface: %{"surface_kind" => "local_http_fixture"},
      timeouts: %{"request_timeout_ms" => 5_000},
      retry_class: "safe_idempotent"
    })
  end

  defp execution_lineage(route_id) do
    %{
      tenant_id: "tenant-toy-document-review",
      trace_id: "trace://toy-document-review/execution-plane",
      request_id: "request-toy-document-review-execution-plane",
      decision_id: "decision-toy-document-review",
      boundary_session_id: "boundary-session-toy-document-review",
      attempt_ref: "attempt://toy-document-review/execution-plane",
      route_id: route_id,
      idempotency_key: "toy-document-review-execution-plane"
    }
  end
end
