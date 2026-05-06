defmodule StackLab.HiveRoundtrip do
  @moduledoc """
  Phase H multi-agent coordination proof.
  """

  alias AppKit.HiveSurface
  alias JidoHive.AgentCoordinator
  alias JidoHive.CoordinationPatterns
  alias JidoHive.InterAgentMessaging
  alias JidoHive.SharedMemoryFacade

  @spec run() :: {:ok, map()} | {:error, term()}
  def run do
    with {:ok, writer} <- AgentCoordinator.spawn_agent(spawn_attrs("agent://writer")),
         {:ok, reviewer} <- AgentCoordinator.spawn_agent(spawn_attrs("agent://reviewer")),
         {:ok, handoff} <- AgentCoordinator.handoff(handoff_attrs()),
         {:ok, cancel} <- AgentCoordinator.cancel(cancel_attrs()),
         {:ok, routed_message} <- InterAgentMessaging.route(message_attrs(), message_context()),
         {:ok, memory_decision} <-
           SharedMemoryFacade.authorize(memory_intent(), [memory_grant()], memory_context()),
         {:ok, pattern_spec} <- CoordinationPatterns.spec(pattern_attrs()),
         {:ok, pattern_plan} <- CoordinationPatterns.plan(pattern_attrs()),
         {:ok, projection} <-
           hive_projection([writer, reviewer], [routed_message], [memory_decision], [pattern_spec]),
         {:ok, trace_projection} <- hive_trace_projection(projection),
         {:ok, store} <- AgentCoordinator.store(),
         {:ok, durable_store} <- durable_store() do
      {:ok,
       %{
         fixture_refs: fixture_refs(),
         spawn_records: [writer, reviewer],
         handoff: handoff,
         cancel: cancel,
         routed_message: routed_message,
         memory_decision: memory_decision,
         pattern_plan: pattern_plan,
         projection: projection,
         trace_projection: trace_projection,
         store_mode: store.mode,
         durable_store_mode: durable_store.mode,
         negative_results: negative_results()
       }}
    end
  end

  defp hive_projection(agents, messages, memory_decisions, patterns) do
    HiveSurface.from_records(%{
      agents: agents,
      messages: messages,
      memory_decisions: memory_decisions,
      patterns: patterns
    })
  end

  defp hive_trace_projection(projection) do
    HiveSurface.trace_projection(%{
      projection_ref: projection.projection_ref,
      tenant_ref: projection.tenant_ref,
      installation_ref: projection.installation_ref,
      agent_refs: projection.agent_refs,
      message_refs: projection.message_refs,
      memory_scope_refs: projection.memory_scope_refs,
      pattern_refs: projection.pattern_refs,
      budget_refs: projection.budget_refs,
      trace_refs: projection.trace_refs,
      trace_ref: "trace://hive-roundtrip",
      workflow_lifecycle_ref: "workflow://life-1"
    })
  end

  defp durable_store do
    AgentCoordinator.store(%{
      mode: :durable,
      adapter_ref: "adapter://coordination/postgres",
      preflight_ref: "preflight://coordination/postgres"
    })
  end

  defp negative_results do
    %{
      missing_skill:
        AgentCoordinator.spawn_agent(
          Map.delete(spawn_attrs("agent://blocked"), :skill_admission_ref)
        ),
      cross_tenant_message:
        message_attrs()
        |> Map.put(:recipient_tenant_ref, "tenant-b")
        |> InterAgentMessaging.route(message_context()),
      undeclared_recipient: InterAgentMessaging.route(message_attrs(), %{}),
      missing_shared_memory_grant:
        SharedMemoryFacade.authorize(memory_intent(), [], memory_context()),
      unknown_memory_scope:
        SharedMemoryFacade.authorize(memory_intent(), [memory_grant()], %{
          known_memory_scope_refs: ["memory-scope://other"]
        }),
      side_effecting_replay:
        pattern_attrs()
        |> Map.put(:replay_policy, :live_provider_effects)
        |> CoordinationPatterns.spec(),
      raw_projection:
        HiveSurface.projection(%{
          projection_ref: "hive-projection://raw",
          tenant_ref: "tenant-a",
          installation_ref: "installation://main",
          agent_refs: [],
          message_refs: [],
          memory_scope_refs: [],
          pattern_refs: [],
          budget_refs: [],
          trace_refs: [],
          agent_message_body: "raw"
        })
    }
  end

  defp fixture_refs do
    for number <- 1..10 do
      number
      |> Integer.to_string()
      |> String.pad_leading(3, "0")
      |> then(&("HIVE-" <> &1))
    end
  end

  defp spawn_attrs(agent_ref) do
    %{
      agent_ref: agent_ref,
      tenant_ref: "tenant-a",
      authority_ref: "authority://ops",
      installation_ref: "installation://main",
      idempotency_key: "idem-" <> agent_ref,
      trace_ref: "trace://" <> agent_ref,
      persistence_ref: "persistence://memory-default",
      workflow_lifecycle_ref: "workflow://life-1",
      parent_workflow_ref: "workflow://parent-1",
      skill_ref: "skill://research",
      skill_admission_ref: "skill-admission://research/v1",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      budget_ref: "budget://run-1",
      guard_chain_ref: "guard://chain-1",
      target_ref: "target://local",
      release_manifest_ref: "release://ai-platform/phase-h"
    }
  end

  defp handoff_attrs do
    %{
      handoff_ref: "handoff://writer-reviewer",
      from_agent_ref: "agent://writer",
      to_agent_ref: "agent://reviewer",
      tenant_ref: "tenant-a",
      authority_ref: "authority://ops",
      installation_ref: "installation://main",
      idempotency_key: "idem-handoff",
      trace_ref: "trace://handoff",
      persistence_ref: "persistence://memory-default",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      budget_ref: "budget://run-1",
      workflow_lifecycle_ref: "workflow://life-1",
      release_manifest_ref: "release://ai-platform/phase-h"
    }
  end

  defp cancel_attrs do
    %{
      agent_ref: "agent://reviewer",
      tenant_ref: "tenant-a",
      authority_ref: "authority://ops",
      workflow_lifecycle_ref: "workflow://life-1",
      trace_ref: "trace://cancel"
    }
  end

  defp message_attrs do
    %{
      message_ref: "message://writer-reviewer",
      sender_agent_ref: "agent://writer",
      recipient_agent_ref: "agent://reviewer",
      tenant_ref: "tenant-a",
      installation_ref: "installation://main",
      authority_ref: "authority://ops",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      context_budget_ref: "context-budget://run-1",
      budget_decision_ref: "budget-decision://allow",
      idempotency_key: "idem-message",
      trace_ref: "trace://message",
      message_body_ref: "message-body-ref://hash",
      redaction_posture: "hash_only",
      token_budget: 50,
      byte_budget: 2048,
      turn_budget: 4,
      wall_clock_budget_ms: 1_000,
      max_fanout: 1
    }
  end

  defp message_context do
    %{declared_recipient_refs: ["agent://reviewer"], fanout_count: 1}
  end

  defp memory_grant do
    %{
      grant_ref: "shared-grant://writer",
      tenant_ref: "tenant-a",
      installation_ref: "installation://main",
      agent_ref: "agent://writer",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      operations: [:shared_read, :shared_write, :handoff, :revocation],
      guard_policy_ref: "guard://memory",
      authority_ref: "authority://ops",
      trace_ref: "trace://grant",
      redaction_posture: "refs_only"
    }
  end

  defp memory_intent do
    %{
      intent_ref: "memory-intent://writer",
      tenant_ref: "tenant-a",
      installation_ref: "installation://main",
      agent_ref: "agent://writer",
      memory_scope_ref: "memory-scope://tenant-a/run-1/shared",
      operation: :shared_write,
      memory_ref: "memory://shared/fact-1",
      guard_decision_ref: "guard-decision://allow",
      idempotency_key: "idem-memory",
      trace_ref: "trace://memory",
      redaction_posture: "hash_only"
    }
  end

  defp memory_context do
    %{known_memory_scope_refs: ["memory-scope://tenant-a/run-1/shared"]}
  end

  defp pattern_attrs do
    %{
      pattern_ref: "coordination-pattern://orchestrator-worker",
      pattern_name: :orchestrator_worker,
      tenant_ref: "tenant-a",
      installation_ref: "installation://main",
      authority_ref: "authority://ops",
      budget_profile_ref: "budget-profile://run-1",
      trace_ref: "trace://pattern",
      max_agents: 4,
      max_turns: 8,
      max_messages: 16,
      max_tokens: 4_000,
      cancellation_policy_ref: "cancel-policy://bounded",
      memory_policy_ref: "memory-policy://shared-grants",
      replay_policy: :suppress_provider_effects,
      connector_policy_ref: "connector-policy://approved",
      approved_connector_refs: ["connector://search"],
      redaction_posture: "refs_only"
    }
  end
end
