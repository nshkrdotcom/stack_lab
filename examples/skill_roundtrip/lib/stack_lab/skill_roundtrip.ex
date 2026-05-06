defmodule StackLab.SkillRoundtrip do
  @moduledoc """
  End-to-end skill admission and invocation proof for Phase G.
  """

  alias AppKit.SkillSurface
  alias JidoHive.SkillContracts
  alias JidoHive.SkillEngine

  @fixture_refs [
    "SKILL-001",
    "SKILL-002",
    "SKILL-003",
    "SKILL-004",
    "SKILL-005",
    "SKILL-006",
    "SKILL-007",
    "SKILL-008",
    "SKILL-009",
    "SKILL-010"
  ]

  @spec run() :: {:ok, map()} | {:error, term()}
  def run do
    with {:ok, store} <- SkillEngine.new_store(),
         {:ok, durable_store} <- durable_store(),
         {:ok, admission_request} <- admission_request("research", 1),
         {:ok, store, admission_record} <-
           SkillEngine.admit(
             store,
             admission_request.manifest,
             SkillEngine.verification_refs_for(admission_request.manifest)
           ),
         {:ok, duplicate_result} <- duplicate_binding_result(),
         {:ok, missing_ref_result} <- missing_ref_result(),
         {:ok, store, _revision_two} <- admit_revision(store, "research", 2),
         {:ok, store, rollback_record} <-
           SkillEngine.rollback(store, "skill://phase-g/research", 1,
             release_manifest_ref: "release://phase-g/rollback",
             trace_ref: "trace://phase-g/rollback"
           ),
         {:ok, store, _child_record} <- admit_revision(store, "child", 1),
         {:ok, composition_records} <- compose(store),
         {:ok, invocation_request} <- invocation_request("research"),
         gates = SkillEngine.invocation_gate_refs_for(invocation_request.intent),
         {:ok, _store, invocation_record} <-
           SkillEngine.invoke(store, invocation_request.intent, gates),
         {:ok, budget_denial} <- budget_denial(store, invocation_request.intent, gates),
         {:ok, projection} <- SkillSurface.projection(admission_request.manifest),
         {:ok, trace_projection} <- SkillSurface.trace_projection(admission_request.manifest) do
      {:ok,
       %{
         receipt_ref: "skill-roundtrip://phase-g",
         fixture_refs: @fixture_refs,
         admission_ref: admission_record.admission_ref,
         durable_store_mode: durable_store.persistence_mode,
         duplicate_binding_result: duplicate_result,
         missing_ref_result: missing_ref_result,
         rollback_revision: rollback_record.version_ref.revision,
         composition_count: length(composition_records),
         invocation_effect_status: invocation_record.effect_status,
         provider_effect_started?: invocation_record.provider_effect_started?,
         budget_denial: budget_denial,
         projection_redaction: projection.redaction_posture,
         trace_redaction: trace_projection.redaction_posture
       }}
    end
  end

  @spec manifest(String.t(), pos_integer()) :: map()
  def manifest(name, revision) when is_binary(name) and is_integer(revision) do
    skill_ref = "skill://phase-g/#{name}"

    %{
      skill_ref: skill_ref,
      version_ref: %{
        skill_ref: skill_ref,
        version_ref: "skill-version://phase-g/#{name}/#{revision}",
        revision: revision,
        release_manifest_ref: "release://phase-g"
      },
      tenant_ref: "tenant://phase-g",
      authority_ref: "authority://phase-g",
      installation_ref: "installation://phase-g",
      idempotency_key: "idem-phase-g-#{name}-#{revision}",
      trace_ref: "trace://phase-g/#{name}",
      persistence_profile_ref: "persistence://memory/default",
      release_manifest_ref: "release://phase-g",
      prompt_ref: "prompt://phase-g/#{name}",
      tool_refs: ["tool://phase-g/#{name}"],
      memory_profile_ref: "memory://phase-g/default",
      guard_policy_ref: "guard://phase-g/default",
      eval_suite_ref: "eval://phase-g/default",
      budget_profile_ref: "budget://phase-g/default",
      conformance_ref: "conformance://phase-g/#{name}",
      capability_bindings: [capability_binding(name)]
    }
  end

  @spec intent(String.t()) :: map()
  def intent(name) when is_binary(name) do
    %{
      invocation_ref: "skill-invocation://phase-g/#{name}",
      skill_ref: "skill://phase-g/#{name}",
      tenant_ref: "tenant://phase-g",
      authority_ref: "authority://phase-g",
      installation_ref: "installation://phase-g",
      lease_ref: "lease://phase-g",
      target_ref: "target://phase-g",
      prompt_ref: "prompt://phase-g/#{name}",
      memory_profile_ref: "memory://phase-g/default",
      guard_policy_ref: "guard://phase-g/default",
      eval_suite_ref: "eval://phase-g/default",
      budget_profile_ref: "budget://phase-g/default",
      connector_capability_refs: ["capability://phase-g/#{name}"],
      trace_ref: "trace://phase-g/#{name}/invoke",
      idempotency_key: "idem-phase-g-#{name}-invoke",
      release_manifest_ref: "release://phase-g"
    }
  end

  defp durable_store do
    SkillEngine.new_store(%{
      persistence: :durable,
      durable_adapter_ref: "adapter://skill-store",
      durable_preflight_ref: "preflight://skill-store"
    })
  end

  defp admission_request(name, revision) do
    SkillSurface.admission_request(%{
      request_ref: "request://phase-g/admit/#{name}/#{revision}",
      operator_ref: "operator://phase-g",
      manifest: manifest(name, revision)
    })
  end

  defp invocation_request(name) do
    SkillSurface.invocation_request(%{
      request_ref: "request://phase-g/invoke/#{name}",
      operator_ref: "operator://phase-g",
      intent: intent(name)
    })
  end

  defp admit_revision(store, name, revision) do
    with {:ok, request} <- admission_request(name, revision) do
      SkillEngine.admit(
        store,
        request.manifest,
        SkillEngine.verification_refs_for(request.manifest)
      )
    end
  end

  defp duplicate_binding_result do
    duplicate =
      manifest("duplicate", 1)
      |> Map.update!(:capability_bindings, fn [binding] ->
        [binding, Map.put(binding, :binding_ref, "binding://phase-g/duplicate/two")]
      end)

    case SkillContracts.manifest(duplicate) do
      {:error, :duplicate_skill_capability_binding} -> {:ok, :rejected}
      {:error, reason} -> {:error, reason}
      {:ok, _manifest} -> {:error, :duplicate_skill_capability_binding_accepted}
    end
  end

  defp missing_ref_result do
    manifest = SkillContracts.manifest!(manifest("missing-ref", 1))

    refs =
      manifest
      |> SkillEngine.verification_refs_for()
      |> Map.put(:guard_policy_refs, [])

    with {:ok, store} <- SkillEngine.new_store() do
      case SkillEngine.admit(store, manifest, refs) do
        {:error, {:skill_gate_ref_missing, :guard_policy_refs}} -> {:ok, :rejected}
        {:error, reason} -> {:error, reason}
        {:ok, _store, _record} -> {:error, :missing_guard_ref_accepted}
      end
    end
  end

  defp budget_denial(store, intent, gates) do
    gates = Map.put(gates, :budget_decision, :deny_hard_exhausted)

    case SkillEngine.invoke(store, intent, gates) do
      {:error, {:skill_invocation_gate_failed, :budget_profile_ref}} -> {:ok, :rejected}
      {:error, reason} -> {:error, reason}
      {:ok, _store, _record} -> {:error, :budget_denial_accepted}
    end
  end

  defp compose(store) do
    composition = %{
      composition_ref: "composition://phase-g/research/child",
      parent_skill_ref: "skill://phase-g/research",
      child_skill_ref: "skill://phase-g/child",
      tenant_ref: "tenant://phase-g",
      memory_share_ref: "memory-share://phase-g/research-child",
      budget_profile_ref: "budget://phase-g/default",
      max_depth: 2
    }

    with {:ok, _store, records} <-
           SkillEngine.compose(store, [composition],
             shared_memory_refs: ["memory-share://phase-g/research-child"],
             max_depth: 2
           ) do
      {:ok, records}
    end
  end

  defp capability_binding(name) do
    %{
      binding_ref: "binding://phase-g/#{name}",
      capability_ref: "capability://phase-g/#{name}",
      connector_ref: "connector://phase-g/#{name}",
      capability_id: "#{name}.invoke",
      tenant_ref: "tenant://phase-g",
      scope_ref: "scope://phase-g/#{name}",
      contract_version: "connector-sdk.v1"
    }
  end
end
