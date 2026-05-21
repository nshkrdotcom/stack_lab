defmodule StackLab.SkillRoundtrip do
  @moduledoc """
  End-to-end governed skill package proof.
  """

  alias AppKit.SkillSurface
  alias Citadel.AgentRuntimePolicyProjectionCompiler
  alias Citadel.PolicyPacks
  alias Jido.Integration.ConnectorAdmissionEngine
  alias Jido.Integration.V2.SkillContracts

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
    with {:ok, admission_request} <- admission_request("research"),
         {:ok, admission_record} <-
           ConnectorAdmissionEngine.admit_skill_package(admission_request.manifest,
             tenant_ref: "tenant://phase-g",
             trace_ref: "trace://phase-g/skill-admission"
           ),
         {:ok, policy_projection} <- compile_policy(admission_request.manifest),
         {:ok, invocation_request} <- invocation_request("research"),
         {:ok, invocation_envelope} <-
           SkillContracts.invocation_envelope(
             admission_request.manifest,
             invocation_request.intent,
             policy_projection_ref: policy_projection.projection_ref,
             receipt_ledger_ref: "agent-turn-ledger://phase-g/research"
           ),
         {:ok, projection} <- SkillSurface.projection(admission_request.manifest),
         {:ok, trace_projection} <- SkillSurface.trace_projection(admission_request.manifest),
         {:ok, disallowed_skill_result} <- disallowed_skill_result(),
         {:ok, forbidden_path_result} <- forbidden_path_result(),
         {:ok, credential_posture_result} <- credential_posture_result() do
      {:ok,
       %{
         receipt_ref: "skill-roundtrip://phase-g",
         fixture_refs: @fixture_refs,
         admission_ref: admission_record.admission_ref,
         admission_status: admission_record.admission_status,
         policy_projection_ref: policy_projection.projection_ref,
         invocation_ref: invocation_envelope.invocation_ref,
         invocation_entrypoint: invocation_envelope.entrypoint.name,
         raw_material_present?: invocation_envelope.raw_material_present?,
         provider_effect_started?: false,
         disallowed_skill_result: disallowed_skill_result,
         forbidden_path_result: forbidden_path_result,
         credential_posture_result: credential_posture_result,
         projection_redaction: projection.redaction_posture,
         projection_admission_status: projection.admission_status,
         trace_redaction: trace_projection.redaction_posture
       }}
    end
  end

  @spec manifest(String.t(), pos_integer()) :: map()
  def manifest(name, revision) when is_binary(name) and is_integer(revision) do
    attrs = %{
      skill_ref: "skill://phase-g/#{name}",
      package_name: name,
      version: "1.0.#{revision - 1}",
      description: "Governed #{name} skill fixture.",
      entrypoints: [
        %{
          name: "invoke",
          kind: :jido_action,
          schema_ref: "schema://phase-g/#{name}/input",
          capability_ref: "capability://phase-g/#{name}/invoke"
        }
      ],
      allowed_artifact_posture: :claim_checked,
      credential_posture: :lease_required,
      allowed_runtime_families: [:direct, :process],
      policy_refs: ["policy://phase-g/#{name}"],
      docs_ref: "doc://phase-g/#{name}",
      tenant_ref: "tenant://phase-g",
      installation_ref: "installation://phase-g/skills",
      capability_refs: ["capability://phase-g/#{name}/invoke"],
      trace_ref: "trace://phase-g/#{name}",
      release_manifest_ref: "release://phase-g",
      redaction_posture: :refs_only
    }

    Map.put(attrs, :manifest_hash, SkillContracts.canonical_manifest_hash(attrs))
  end

  @spec intent(String.t()) :: map()
  def intent(name) when is_binary(name) do
    %{
      invocation_ref: "skill-invocation://phase-g/#{name}",
      skill_ref: "skill://phase-g/#{name}",
      tenant_ref: "tenant://phase-g",
      authority_ref: "authority://phase-g",
      idempotency_key: "idem-phase-g-#{name}-invoke",
      entrypoint_name: "invoke",
      credential_lease_ref: "credential-lease://phase-g/#{name}",
      target_ref: "target://phase-g/#{name}",
      trace_ref: "trace://phase-g/#{name}/invoke",
      input_ref: "payload://phase-g/#{name}/input"
    }
  end

  defp admission_request(name) do
    SkillSurface.admission_request(%{
      request_ref: "request://phase-g/admit/#{name}",
      operator_ref: "operator://phase-g",
      manifest: manifest(name, 1)
    })
  end

  defp invocation_request(name) do
    SkillSurface.invocation_request(%{
      request_ref: "request://phase-g/invoke/#{name}",
      operator_ref: "operator://phase-g",
      intent: intent(name)
    })
  end

  defp compile_policy(package) do
    package
    |> policy_selection()
    |> AgentRuntimePolicyProjectionCompiler.compile(%{
      projection_ref: "agent-policy-projection://phase-g/research",
      authority_ref: "authority://phase-g",
      tenant_ref: "tenant://phase-g",
      requested_runtime_family: :process,
      requested_capability_class: :skill_invocation,
      skill_ref: package.skill_ref,
      credential_posture: :lease_only,
      budget: %{wall_clock_ms: 60_000, output_bytes: 1_000_000, tool_calls: 20}
    })
  end

  defp policy_selection(package) do
    pack =
      PolicyPacks.generic_substrate_pack!(
        agent_runtime_allowed_runtime_families: ["direct", "process"],
        agent_runtime_allowed_capability_classes: ["skill_invocation"],
        agent_runtime_skill_allowlist_refs: [package.skill_ref],
        agent_runtime_approval_requirements: ["skill_invocation"],
        agent_runtime_budget: %{wall_clock_ms: 60_000, output_bytes: 1_000_000, tool_calls: 20}
      )

    PolicyPacks.select_profile!([pack], %{
      tenant_id: "phase-g",
      scope_kind: "project",
      environment: "prod"
    })
  end

  defp disallowed_skill_result do
    package = SkillContracts.package!(manifest("research", 1))
    selection = policy_selection(package)

    case AgentRuntimePolicyProjectionCompiler.compile(selection, %{
           projection_ref: "agent-policy-projection://phase-g/blocked",
           authority_ref: "authority://phase-g",
           tenant_ref: "tenant://phase-g",
           requested_runtime_family: :process,
           requested_capability_class: :skill_invocation,
           skill_ref: "skill://phase-g/not-admitted",
           credential_posture: :lease_only,
           budget: %{wall_clock_ms: 60_000, output_bytes: 1_000_000, tool_calls: 20}
         }) do
      {:error, {:denied, :unknown_skill_package, _facts}} -> {:ok, :rejected}
      {:error, reason} -> {:error, reason}
      {:ok, _projection} -> {:error, :disallowed_skill_accepted}
    end
  end

  defp forbidden_path_result do
    attrs =
      "script"
      |> manifest(1)
      |> put_in([:entrypoints], [
        %{
          name: "invoke",
          kind: :jido_action,
          schema_ref: "schema://phase-g/script/input",
          script_path: "/tmp/run.sh"
        }
      ])
      |> rehash()

    case SkillContracts.package(attrs) do
      {:error, {:forbidden_skill_package_fields, _fields}} -> {:ok, :rejected}
      {:error, reason} -> {:error, reason}
      {:ok, _package} -> {:error, :forbidden_path_accepted}
    end
  end

  defp credential_posture_result do
    package =
      "public"
      |> manifest(1)
      |> Map.put(:credential_posture, :no_credentials)
      |> rehash()
      |> SkillContracts.package!()

    intent = SkillContracts.invocation_intent!(intent("public"))

    case SkillContracts.invocation_envelope(package, intent,
           policy_projection_ref: "agent-policy-projection://phase-g/public",
           receipt_ledger_ref: "agent-turn-ledger://phase-g/public"
         ) do
      {:error, :credential_lease_not_allowed} -> {:ok, :rejected}
      {:error, reason} -> {:error, reason}
      {:ok, _envelope} -> {:error, :credential_posture_accepted}
    end
  end

  defp rehash(attrs),
    do: Map.put(attrs, :manifest_hash, SkillContracts.canonical_manifest_hash(attrs))
end
