defmodule StackLab.ReplayRoundtrip do
  @moduledoc """
  Replay roundtrip proof.
  """

  alias AITrace.Integrations.AgentTurn
  alias AITrace.{ReplayEngine, Span, Trace}
  alias AppKit.ReplaySurface
  alias StackLab.Support.DriftDetector

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(attrs \\ %{}) when is_map(attrs) do
    trace = source_trace(attrs)
    request = request_attrs(attrs)

    with {:ok, replay} <-
           ReplayEngine.replay(request,
             trace_store: %{request.source_trace_id => trace},
             inject_divergences: Map.get(attrs, :inject_divergences, [])
           ),
         {:ok, bundle_projection} <-
           ReplaySurface.bundle_projection(Map.from_struct(replay.bundle)),
         {:ok, drift_signals} <- drift_signals(replay),
         {:ok, evidence_export} <- agent_evidence_export(replay, attrs) do
      {:ok,
       %{
         receipt_ref: "replay-roundtrip://#{hash(replay.bundle.replay_trace_ref)}",
         fixture_refs: ["EVAL-001", "EVAL-002", "EVAL-003", "EVAL-004", "EVAL-008", "EVAL-011"],
         side_effects_invoked?: replay.side_effects_invoked?,
         bundle_projection: bundle_projection,
         agent_evidence_export: Map.from_struct(evidence_export),
         divergence_count: length(replay.divergences),
         drift_signals: Enum.map(drift_signals, &DriftDetector.project/1)
       }}
    end
  end

  defp agent_evidence_export(replay, attrs) do
    ledger_ref = "agent-ledger://stack-lab/replay/#{hash(replay.bundle.trace_ref)}"

    runtime_receipt_ref =
      "agent-runtime-receipt://stack-lab/replay/#{hash(replay.bundle.replay_trace_ref)}"

    AgentTurn.export_receipt(%{
      ledger_ref: ledger_ref,
      authority_ref: replay.bundle.authority_ref,
      trace_ref: replay.bundle.replay_trace_ref,
      runtime_receipt_refs: [runtime_receipt_ref],
      redaction_manifest_ref: "redaction://stack-lab/replay-roundtrip/default",
      events: Map.get(attrs, :agent_events, agent_events(runtime_receipt_ref)),
      exported_at: Map.get(attrs, :exported_at, ~U[2026-05-21 00:00:00Z])
    })
  end

  defp agent_events(runtime_receipt_ref) do
    [
      %{event_ref: "agent-event://stack-lab/replay/10", event_kind: :conversation, seq: 10},
      %{
        event_ref: "agent-event://stack-lab/replay/11",
        event_kind: :execution,
        seq: 11,
        runtime_receipt_ref: runtime_receipt_ref
      },
      %{event_ref: "agent-event://stack-lab/replay/12", event_kind: :projection, seq: 12}
    ]
  end

  defp drift_signals(replay) do
    DriftDetector.detect([
      %{
        run_ref: "source-run",
        trace_ref: replay.bundle.source_trace_ref,
        tenant_ref: replay.bundle.tenant_ref,
        installation_ref: replay.bundle.installation_ref,
        guard_decision_drift: "source"
      },
      %{
        run_ref: "replay-run",
        trace_ref: replay.bundle.replay_trace_ref,
        tenant_ref: replay.bundle.tenant_ref,
        installation_ref: replay.bundle.installation_ref,
        guard_decision_drift: replay.bundle.decision_class
      }
    ])
  end

  defp source_trace(attrs) do
    span =
      "provider.response"
      |> Span.new()
      |> Span.with_attributes(%{decision_ref: "guard://source"})
      |> Span.finish()

    attrs
    |> Map.get(:source_trace_id, "trace-source-roundtrip")
    |> Trace.new()
    |> Trace.add_span(span)
    |> Trace.with_metadata(%{tenant_ref: Map.get(attrs, :tenant_ref, "tenant://a")})
  end

  defp request_attrs(attrs) do
    %{
      tenant_ref: Map.get(attrs, :tenant_ref, "tenant://a"),
      authority_ref: Map.get(attrs, :authority_ref, "authority://a"),
      installation_ref: Map.get(attrs, :installation_ref, "installation://a"),
      idempotency_key: Map.get(attrs, :idempotency_key, "idem-replay-roundtrip"),
      trace_ref: Map.get(attrs, :trace_ref, "replay-bundle://roundtrip"),
      source_trace_id: Map.get(attrs, :source_trace_id, "trace-source-roundtrip"),
      replay_mode: Map.get(attrs, :replay_mode, :exact),
      variant_overrides: Map.get(attrs, :variant_overrides, %{}),
      side_effect_policy: :suppress,
      divergence_thresholds: %{},
      persistence_ref: "persistence://memory/default",
      release_manifest_ref: "release://phase-c"
    }
  end

  defp hash(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
