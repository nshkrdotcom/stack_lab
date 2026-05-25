defmodule StackLab.Examples.TRINITYPlatformRoundtrip.Receipt do
  @moduledoc "Deterministic TRINITY platform roundtrip receipt."
  @enforce_keys [
    :receipt_ref,
    :fixture_refs,
    :status,
    :provider_dependency?,
    :coordination_fabric_scan,
    :appkit_projection,
    :router_decision_ref,
    :selected_role_ref,
    :provider_pool_ref,
    :inference_call_ref,
    :verifier_result_ref,
    :handoff_scope_ref,
    :trace_refs,
    :replay_refs
  ]
  defstruct @enforce_keys
  @type t :: %__MODULE__{}
end

defmodule StackLab.Examples.TRINITYPlatformRoundtrip do
  @moduledoc """
  Deterministic governed TRINITY platform roundtrip proof.
  """

  alias AppKit.CoordinationSurface
  alias StackLab.CoordinationFabricScanner
  alias StackLab.Examples.TRINITYPlatformRoundtrip.Receipt
  alias Trinity.{ProviderPool, Registry, Router}

  @fixture_refs ["AOC-026", "AOC-036", "AOC-039", "AOC-043"]

  @spec run() :: {:ok, Receipt.t()} | {:error, term()}
  def run do
    config = Trinity.Config.compile!(trinity_config())

    with {:ok, decision} <- Router.route(config, route_context()),
         {:ok, role_pack} <- Registry.fetch_role_pack(config.registry, decision.selected_role_ref),
         {:ok, provider_slot} <-
           ProviderPool.slot_for_role(config.provider_pool, role_pack.role_ref),
         appkit_attrs = appkit_attrs(decision, role_pack, provider_slot),
         {:ok, appkit_projection} <- CoordinationSurface.coordination_projection(appkit_attrs),
         {:ok, scan} <- CoordinationFabricScanner.scan(scanner_input()) do
      {:ok,
       %Receipt{
         receipt_ref: "trinity-platform-roundtrip://phase-11/mock",
         fixture_refs: @fixture_refs,
         status: status([scan]),
         provider_dependency?: false,
         coordination_fabric_scan: scan,
         appkit_projection: appkit_projection,
         router_decision_ref: decision.router_decision_ref,
         selected_role_ref: decision.selected_role_ref,
         provider_pool_ref: "provider-pool://mock",
         inference_call_ref: "inference/mock/1",
         verifier_result_ref: "verifier/mock/pass",
         handoff_scope_ref: "handoff-scope://worker/reviewer",
         trace_refs: ["trace/trinity/demo", "trace/router/demo"],
         replay_refs: ["replay/trinity/demo", "replay/router/demo"]
       }}
    end
  end

  defp route_context do
    %{
      coordination_run_ref: "ai_run/trinity/demo",
      preferred_role_ref: "role/worker",
      trace_ref: "trace/router/demo",
      replay_ref: "replay/router/demo"
    }
  end

  defp trinity_config do
    %{
      router_artifact: %{
        router_artifact_ref: "router/mock",
        extractor_ref: "extractor/mock",
        head_ref: "head/mock",
        compatibility_ref: "compat/qwen",
        calibration_ref: "calibration/router/threshold",
        parity_ref: "parity/qwen-sakana",
        hash_ref: "sha256:router"
      },
      role_packs: [
        %{
          role_ref: "role/worker",
          prompt_ref: "prompt/role/worker",
          capability_refs: ["cap/code"],
          allowed_model_profile_refs: ["model/mock/worker"],
          tool_policy_ref: "tool/policy/worker",
          memory_profile_ref: "memory/role/worker",
          guardrail_profile_ref: "guardrail/role/worker",
          verifier_profile_ref: "verifier/role/worker",
          budget_ref: "budget/role/worker",
          context_budget_ref: "context/role/worker",
          handoff_policy_ref: "handoff/role/worker",
          projection_ref: "appkit/coordination/worker",
          gepa_target_refs: ["gepa/target/role_prompt"]
        }
      ],
      provider_pool: [
        %{
          slot_ref: "slot/mock/worker",
          slot_kind: :mock,
          role_refs: ["role/worker"],
          model_profile_ref: "model/mock/worker",
          endpoint_profile_ref: "endpoint/mock/worker",
          operation_policy_ref: "policy/route/mock",
          target_ref: "target/mock/worker",
          credential_ref: "credential/mock/ref",
          per_role_constraints: %{
            "role/worker" => %{max_turns: 3, budget_ref: "budget/role/worker"}
          }
        }
      ]
    }
  end

  defp appkit_attrs(decision, role_pack, provider_slot) do
    %{
      coordination_run_ref: "coordination-run://trinity/demo",
      tenant_ref: "tenant/demo",
      authority_ref: "authority/coordination",
      trace_refs: ["trace/trinity/demo"],
      memory_refs: [role_pack.memory_profile_ref],
      context_budget_refs: [role_pack.context_budget_ref],
      router_decision: %{
        router_decision_ref: decision.router_decision_ref,
        router_artifact_ref: decision.router_artifact_ref,
        selected_role_ref: decision.selected_role_ref,
        confidence_band: decision.confidence_band,
        fallback_reason: decision.fallback_reason,
        trace_ref: decision.trace_ref,
        replay_ref: decision.replay_ref
      },
      role_selection: %{
        role_ref: role_pack.role_ref,
        prompt_ref: role_pack.prompt_ref,
        capability_refs: role_pack.capability_refs,
        model_profile_refs: role_pack.allowed_model_profile_refs,
        tool_policy_ref: role_pack.tool_policy_ref,
        memory_profile_ref: role_pack.memory_profile_ref,
        guardrail_profile_ref: role_pack.guardrail_profile_ref,
        verifier_profile_ref: role_pack.verifier_profile_ref,
        budget_ref: role_pack.budget_ref,
        context_budget_ref: role_pack.context_budget_ref,
        handoff_policy_ref: role_pack.handoff_policy_ref,
        gepa_target_refs: role_pack.gepa_target_refs
      },
      provider_pool: %{
        provider_pool_ref: "provider-pool://mock",
        slot_refs: [provider_slot.slot_ref],
        model_profile_refs: [provider_slot.model_profile_ref],
        endpoint_profile_refs: [provider_slot.endpoint_profile_ref],
        operation_policy_refs: [provider_slot.operation_policy_ref],
        readiness_refs: ["readiness/mock/worker"]
      },
      verifier_state: %{
        verifier_policy_ref: "verifier-policy://worker",
        verifier_result_ref: "verifier/mock/pass",
        score_schema_ref: "score-schema://verifier",
        termination_policy_ref: "termination-policy://complete",
        replay_ref: "replay/verifier/demo",
        trace_ref: "trace/verifier/demo"
      },
      turn_timeline: %{
        turn_refs: ["turn/worker/1"],
        agent_refs: ["agent/worker"],
        inference_call_refs: ["inference/mock/1"],
        verifier_refs: ["verifier/mock/pass"],
        handoff_refs: ["handoff/worker/reviewer"],
        trace_refs: ["trace/turn/worker/1"]
      },
      replay_bundle: %{
        replay_bundle_ref: "replay-bundle://trinity/demo",
        coordination_run_ref: "coordination-run://trinity/demo",
        trace_refs: ["trace/trinity/demo"],
        replay_refs: ["replay/trinity/demo", "replay/router/demo"],
        redaction_posture: :refs_only
      }
    }
  end

  defp scanner_input do
    %{
      owner_repo: "mezzanine",
      package_path: "core/coordination_engine",
      coordination_facts: [
        %{
          router_artifact_refs: ["router/mock"],
          router_eval_refs: ["router-eval/golden"],
          calibration_refs: ["calibration/router/threshold"],
          drift_detection_refs: ["drift/router/window"],
          parity_check_refs: ["parity/qwen-sakana"],
          role_prompt_refs: ["prompt/role/worker"],
          provider_pool_refs: ["provider-pool://mock"],
          governed_inference_boundary_ref: "inference-boundary/governed/mock",
          verifier_refs: ["verifier/mock/pass"],
          handoff_scope_ref: "handoff-scope://worker/reviewer",
          trace_refs: ["trace/trinity/demo"],
          replay_refs: ["replay/trinity/demo"],
          trace_redaction: :redacted
        }
      ]
    }
  end

  defp status(receipts) do
    if Enum.all?(receipts, &(&1.status == :pass)), do: :pass, else: :open_defect
  end
end
