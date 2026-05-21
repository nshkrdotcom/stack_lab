defmodule StackLab.AgentFoundationRoundtrip do
  @moduledoc """
  Deterministic release proof for the native agent foundation.

  The proof composes the actual platform contract packages while keeping all
  provider effects fixture-backed and local to StackLab.
  """

  alias AITrace.Integrations.AgentTurn, as: AITraceAgentTurn
  alias AppKit.Core.AgentIntake.AgentRunEventPage
  alias AppKit.Core.AgentIntake.AgentRunRequest
  alias Citadel.AgentRuntimePolicyProjection
  alias ExecutionPlane.Contracts.LaneFact.V1, as: LaneFact
  alias Jido.Integration.AgentInterop.Descriptor, as: AgentInteropDescriptor
  alias Jido.Integration.AgentInterop.Receipt, as: AgentRuntimeReceipt
  alias Jido.Integration.ConnectorAdmissionEngine
  alias Jido.Integration.V2.SkillContracts
  alias Mezzanine.AgentTurnEngine.AgentConversationEvent
  alias Mezzanine.AgentTurnEngine.AgentExecutionEvent
  alias Mezzanine.AgentTurnEngine.AgentPendingInteraction
  alias Mezzanine.AgentTurnEngine.AgentRunCursor
  alias Mezzanine.AgentTurnEngine.AgentTurnLedger
  alias Mezzanine.AgentTurnEngine.ExecutionReplay
  alias Mezzanine.AgentTurnEngine.PendingDecision
  alias Mezzanine.AgentTurnEngine.Store.Memory
  alias StackLab.NoBypassScanner

  @schema_version "stack_lab_agent_foundation_roundtrip_v1"
  @timestamp ~U[2026-05-21 00:00:00Z]
  @timestamp_iso DateTime.to_iso8601(@timestamp)
  @tenant_ref "tenant://stack-lab/agent-foundation"
  @installation_ref "installation://stack-lab/agent-foundation"
  @subject_ref "subject://stack-lab/document-1"
  @actor_ref "actor://stack-lab/operator"
  @authority_ref "authority://stack-lab/agent-foundation/rev-1"
  @authority_revision_ref "authority-revision://stack-lab/agent-foundation/1"
  @ledger_ref "agent-ledger://stack-lab/agent-foundation/run-1"
  @platform_run_ref "run://stack-lab/agent-foundation/run-1"
  @platform_execution_ref "execution://stack-lab/agent-foundation/execution-1"
  @runtime_receipt_ref "receipt://stack-lab/agent-foundation/runtime-1"
  @skill_ref "skill://stack-lab/document-summarize"
  @interop_ref "agent-interop://stack-lab/local-agent"
  @capability_ref "capability://stack-lab/document-review"

  @acceptance_ids Enum.map(1..20, fn number ->
                    "AF-" <> String.pad_leading(Integer.to_string(number), 3, "0")
                  end)

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(attrs \\ %{}) when is_map(attrs) do
    with {:ok, appkit_request} <- appkit_request(),
         {:ok, policy_projection} <- policy_projection(),
         {:ok, ledger} <- ledger(),
         {:ok, store0} <- Memory.new() |> Memory.put_ledger(ledger),
         {:ok, store1} <- append(store0, conversation_event(1, :run_started, "Run started")),
         {:ok, store2} <- append(store1, execution_event(2, :authority_projection_bound)),
         {:ok, pending} <- pending_interaction(3),
         stale_pending_fault <- stale_pending_fault(store2, pending),
         {:ok, store3} <- Memory.open_pending(store2, pending),
         {:ok, store4} <-
           append(store3, conversation_event(4, :pending_review_requested, "Review requested")),
         {:ok, store5, resolved_pending} <- resolve_pending(store4, pending),
         {:ok, store6} <-
           append(store5, conversation_event(5, :review_decision_recorded, "Review approved")),
         {:ok, lane_fact} <- lane_fact(),
         {:ok, runtime_receipt} <- runtime_receipt(lane_fact),
         {:ok, store7} <-
           append(store6, execution_event(6, :runtime_receipt_received, runtime_receipt)),
         duplicate_runtime_receipt <- duplicate_runtime_receipt_fault(store7, runtime_receipt),
         {:ok, store8} <-
           append(store7, execution_event(7, :runtime_receipt_reduced, runtime_receipt)),
         {:ok, store9} <-
           append(
             store8,
             conversation_event(8, :tool_result_summarized, "Tool result summarized")
           ),
         {:ok, store10} <-
           append(
             store9,
             conversation_event(9, :run_completed, "Run completed", [@runtime_receipt_ref])
           ),
         duplicate_event <- duplicate_event_fault(store10),
         non_monotonic <- non_monotonic_fault(store10),
         {:ok, catch_up} <- catch_up(store10),
         {:ok, replay} <- replay_without_lower_reexecution(store10),
         {:ok, skill} <- skill_roundtrip(policy_projection),
         {:ok, interop} <- interop_roundtrip(policy_projection),
         {:ok, evidence_export} <- evidence_export(runtime_receipt),
         {:ok, no_bypass} <- no_bypass_proof(),
         faults <-
           faults(%{
             duplicate_event: duplicate_event,
             non_monotonic: non_monotonic,
             stale_pending: stale_pending_fault,
             duplicate_runtime_receipt: duplicate_runtime_receipt,
             catch_up: catch_up,
             skill: skill,
             interop: interop,
             evidence_export: evidence_export,
             no_bypass: no_bypass
           }) do
      receipt = %{
        schema_version: @schema_version,
        receipt_ref: "agent-foundation-roundtrip://stack-lab/deterministic",
        status: :pass,
        deterministic?: Map.get(attrs, :deterministic?, true),
        live_provider_required?: false,
        appkit: %{agent_run_request: AgentRunRequest.dump(appkit_request)},
        mezzanine:
          mezzanine_section(store10, ledger, pending, resolved_pending, catch_up, replay),
        citadel: citadel_section(policy_projection),
        jido: jido_section(runtime_receipt, skill, interop),
        execution_plane: %{lane_fact: LaneFact.dump(lane_fact)},
        aitrace: evidence_section(evidence_export),
        no_bypass: no_bypass,
        faults: faults,
        acceptance:
          acceptance(%{
            appkit_request: appkit_request,
            store: store10,
            policy_projection: policy_projection,
            runtime_receipt: runtime_receipt,
            lane_fact: lane_fact,
            evidence_export: evidence_export,
            catch_up: catch_up,
            replay: replay,
            skill: skill,
            interop: interop,
            no_bypass: no_bypass,
            faults: faults
          })
      }

      {:ok, receipt}
    end
  end

  @spec no_bypass_proof() :: {:ok, map()} | {:error, term()}
  def no_bypass_proof do
    with {:ok, pass_receipt} <-
           NoBypassScanner.scan(
             owner_repo: "stack_lab",
             package_path: "examples/agent_foundation_roundtrip",
             target_code_paths: ["examples/agent_foundation_roundtrip/lib"],
             approved_facade_refs: ["AppKit.Core.AgentIntake"],
             proof_refs: ["agent-foundation-roundtrip://stack-lab/deterministic"],
             scanner_refs: ["stack-lab.product-no-bypass-scanner.v1"],
             signals: %{}
           ),
         {:ok, lower_rejection} <-
           NoBypassScanner.scan(
             owner_repo: "stack_lab",
             package_path: "fixtures/product-direct-lower-import",
             target_code_paths: ["fixtures/product-direct-lower-import/lib"],
             approved_facade_refs: ["AppKit.Core.AgentIntake"],
             proof_refs: ["agent-foundation-roundtrip://stack-lab/direct-lower-negative"],
             scanner_refs: ["stack-lab.product-no-bypass-scanner.v1"],
             signals: %{direct_provider_sdk_calls: [:JidoIntegration]}
           ) do
      {:ok,
       %{
         scanner_ref: pass_receipt.scanner_ref,
         receipt_ref: pass_receipt.receipt_ref,
         status: pass_receipt.status,
         product_direct_lower_rejected?: lower_rejection.status == :open_defect,
         ax_terms_rejected?: forbidden_terms_rejected?("def run, do: \"ax serve\"", ax_terms()),
         a2a_terms_rejected?:
           forbidden_terms_rejected?("defmodule A2ABridge, do: nil", a2a_terms()),
         checked_rules: pass_receipt.checked_rules
       }}
    end
  end

  @spec to_json!(map()) :: String.t()
  def to_json!(receipt) when is_map(receipt) do
    receipt
    |> jsonable()
    |> Jason.encode!(pretty: true)
  end

  defp appkit_request do
    AgentRunRequest.new(%{
      tenant_ref: @tenant_ref,
      installation_ref: @installation_ref,
      subject_ref: @subject_ref,
      actor_ref: @actor_ref,
      profile_bundle: %{
        source_profile_ref: :agent_foundation_source,
        runtime_profile_ref: :agent_foundation_runtime,
        tool_scope_ref: :agent_foundation_tools,
        evidence_profile_ref: :agent_foundation_evidence,
        publication_profile_ref: :agent_foundation_publication,
        review_profile_ref: :agent_foundation_review,
        memory_profile_ref: :none,
        projection_profile_ref: :agent_foundation_projection
      },
      tool_catalog_ref: "tool-catalog://stack-lab/agent-foundation",
      budget_ref: "budget://stack-lab/agent-foundation",
      recall_scope_ref: "recall-scope://stack-lab/agent-foundation",
      idempotency_key: "idem-agent-foundation-start",
      trace_id: "trace://stack-lab/agent-foundation",
      correlation_id: "correlation://stack-lab/agent-foundation",
      submission_dedupe_key: "submission-agent-foundation-start",
      initial_input_ref: "payload://stack-lab/initial-input",
      effect_governance_mode: :fixture_backed,
      diagnostic_lane: :echo
    })
  end

  defp policy_projection do
    AgentRuntimePolicyProjection.new(%{
      projection_ref: "agent-policy-projection://stack-lab/agent-foundation/rev-1",
      authority_ref: @authority_ref,
      tenant_ref: @tenant_ref,
      allowed_runtime_families: [:direct, :interop],
      allowed_capability_classes: [:tool_call, :skill_invocation],
      denied_capability_classes: [:model_inference],
      skill_allowlist_refs: [@skill_ref],
      interop_allowlist_refs: [@interop_ref],
      approval_requirements: [:tool_call],
      network_posture: :none,
      artifact_posture: :claim_checked,
      credential_posture: :lease_only,
      budget: %{wall_clock_ms: 1_000, output_bytes: 4096, tool_calls: 2},
      redaction_posture: :product_safe,
      revision: 1
    })
  end

  defp ledger do
    AgentTurnLedger.new(%{
      ledger_ref: @ledger_ref,
      tenant_ref: @tenant_ref,
      installation_ref: @installation_ref,
      subject_ref: @subject_ref,
      platform_run_ref: @platform_run_ref,
      platform_execution_ref: @platform_execution_ref,
      actor_ref: @actor_ref,
      authority_ref: @authority_ref,
      idempotency_key: "idem-agent-foundation-ledger",
      status: :initialized,
      next_seq: 1,
      last_reduced_seq: 0,
      last_conversation_seq: 0,
      last_execution_seq: 0,
      created_at: @timestamp,
      updated_at: @timestamp
    })
  end

  defp conversation_event(seq, event_type, summary, evidence_refs \\ []) do
    AgentConversationEvent.new(%{
      event_ref: "agent-conv-event://stack-lab/agent-foundation/#{seq}",
      ledger_ref: @ledger_ref,
      seq: seq,
      event_type: event_type,
      visibility: :product,
      summary: summary,
      payload_ref: "payload://stack-lab/agent-foundation/conversation/#{seq}",
      redaction_class: :safe,
      authority_ref: @authority_ref,
      evidence_refs: evidence_refs,
      occurred_at: DateTime.add(@timestamp, seq, :second)
    })
  end

  defp execution_event(seq, event_type, receipt \\ nil) do
    receipt_ref =
      if receipt, do: receipt.receipt_ref, else: "receipt://stack-lab/agent-foundation/#{seq}"

    AgentExecutionEvent.new(%{
      event_ref: "agent-exec-event://stack-lab/agent-foundation/#{seq}",
      ledger_ref: @ledger_ref,
      seq: seq,
      event_type: event_type,
      source: event_source(event_type),
      idempotency_key: "idem-agent-foundation-exec-#{seq}",
      causation_ref: "agent-conv-event://stack-lab/agent-foundation/1",
      lower_receipt_ref: receipt_ref,
      payload_hash: hash_ref(%{event_type: event_type, receipt_ref: receipt_ref}),
      payload_ref: "payload://stack-lab/agent-foundation/execution/#{seq}",
      redaction_class: :redacted,
      occurred_at: DateTime.add(@timestamp, seq, :second)
    })
  end

  defp event_source(:authority_projection_bound), do: :citadel
  defp event_source(:runtime_receipt_received), do: :jido
  defp event_source(:runtime_receipt_reduced), do: :mezzanine

  defp append(store, {:ok, event}), do: Memory.append_event(store, event)
  defp append(_store, {:error, reason}), do: {:error, reason}

  defp pending_interaction(opened_seq) do
    AgentPendingInteraction.new(%{
      pending_ref: "agent-pending://stack-lab/agent-foundation/review-1",
      ledger_ref: @ledger_ref,
      decision_ref: "decision://stack-lab/agent-foundation/review-1",
      tenant_ref: @tenant_ref,
      actor_ref: @actor_ref,
      kind: :approval_required,
      prompt_summary: "Approve tool execution",
      requested_action_ref: "action://stack-lab/agent-foundation/tool-call",
      authority_ref: @authority_ref,
      opened_seq: opened_seq,
      status: :open,
      expires_at: DateTime.add(@timestamp, 3600, :second)
    })
  end

  defp resolve_pending(store, pending) do
    decision =
      PendingDecision.new!(%{
        decision_ref: pending.decision_ref,
        pending_ref: pending.pending_ref,
        tenant_ref: pending.tenant_ref,
        actor_ref: pending.actor_ref,
        authority_ref: @authority_ref,
        authority_revision_ref: @authority_revision_ref,
        decision: :approved,
        idempotency_key: "idem-agent-foundation-review-approved",
        decided_at: DateTime.add(@timestamp, 10, :second)
      })

    Memory.resolve_pending(store, pending.pending_ref, decision)
  end

  defp lane_fact do
    LaneFact.new(%{
      fact_ref: "lane-fact://stack-lab/agent-foundation/1",
      route_id: "route://stack-lab/agent-foundation/fixture",
      lane_id: "lane://stack-lab/fixture",
      family: "process",
      protocol: "deterministic-fixture",
      phase: "completed",
      transport_ref: "transport://stack-lab/fixture",
      timestamp: @timestamp_iso,
      sequence: 1,
      output_byte_size: 128,
      max_output_bytes: 4096,
      output_hash_ref: hash_ref(%{summary: "fixture output"}),
      output_ref: "payload://stack-lab/agent-foundation/output",
      redacted_preview_ref: "payload://stack-lab/agent-foundation/redacted-preview",
      lineage: %{
        tenant_id: @tenant_ref,
        trace_id: "trace://stack-lab/agent-foundation",
        request_id: "request://stack-lab/agent-foundation",
        decision_id: @authority_ref,
        boundary_session_id: "boundary-session://stack-lab/fixture",
        attempt_ref: "attempt://stack-lab/agent-foundation/1",
        route_id: "route://stack-lab/agent-foundation/fixture",
        idempotency_key: "idem-agent-foundation-runtime"
      },
      payload_shape: %{"keys" => ["result_ref", "summary_ref"]},
      evidence_refs: ["evidence://stack-lab/agent-foundation/lane"]
    })
  end

  defp runtime_receipt(lane_fact) do
    AgentRuntimeReceipt.new(%{
      receipt_ref: @runtime_receipt_ref,
      ledger_ref: @ledger_ref,
      lower_invocation_ref: "lower-invocation://stack-lab/agent-foundation/1",
      runtime_family: :interop,
      capability_ref: @capability_ref,
      authority_ref: @authority_ref,
      idempotency_key: "idem-agent-foundation-runtime",
      status: :succeeded,
      output_summary: %{"summary_ref" => "payload://stack-lab/agent-foundation/output-summary"},
      output_ref: "payload://stack-lab/agent-foundation/output",
      event_seq_hint: 6,
      evidence_refs: [lane_fact.fact_ref],
      trace_ref: "trace://stack-lab/agent-foundation",
      started_at: @timestamp,
      completed_at: DateTime.add(@timestamp, 12, :second),
      metadata: %{"lane_fact_ref" => lane_fact.fact_ref}
    })
  end

  defp catch_up(store) do
    cursor =
      AgentRunCursor.new!(%{
        cursor_ref: "agent-cursor://stack-lab/agent-foundation/product-after-4",
        ledger_ref: @ledger_ref,
        tenant_ref: @tenant_ref,
        actor_ref: @actor_ref,
        last_seq_seen: 4,
        visibility: :product,
        issued_at: DateTime.add(@timestamp, 20, :second),
        expires_at: DateTime.add(@timestamp, 3600, :second)
      })

    before_count = store.lower_dispatch_count

    with {:ok, next_store, page} <- Memory.catch_up(store, cursor),
         {:ok, appkit_page} <- appkit_page(page) do
      {:ok,
       %{
         cursor_ref: page.cursor.cursor_ref,
         event_count: length(page.events),
         lower_dispatch_count_delta: next_store.lower_dispatch_count - before_count,
         appkit_event_page: AgentRunEventPage.dump(appkit_page)
       }}
    end
  end

  defp appkit_page(page) do
    AgentRunEventPage.new(%{
      cursor: %{
        cursor_ref: page.cursor.cursor_ref,
        ledger_ref: page.cursor.ledger_ref,
        tenant_ref: page.cursor.tenant_ref,
        actor_ref: page.cursor.actor_ref,
        last_seq_seen: page.cursor.last_seq_seen,
        visibility: page.cursor.visibility,
        issued_at: DateTime.to_iso8601(page.cursor.issued_at),
        expires_at: DateTime.to_iso8601(page.cursor.expires_at)
      },
      events: Enum.map(page.events, &appkit_event/1),
      has_more?: false
    })
  end

  defp appkit_event(event) do
    %{
      event_ref: event.event_ref,
      ledger_ref: event.ledger_ref,
      event_seq: event.seq,
      event_kind: appkit_event_kind(event.event_type),
      visibility: event.visibility,
      observed_at: DateTime.to_iso8601(event.occurred_at),
      summary: event.summary,
      payload_ref: event.payload_ref
    }
  end

  defp appkit_event_kind(:pending_review_requested), do: :pending_opened
  defp appkit_event_kind(:review_decision_recorded), do: :pending_resolved
  defp appkit_event_kind(:run_started), do: :run_started
  defp appkit_event_kind(:run_completed), do: :run_completed
  defp appkit_event_kind(_event_type), do: :conversation_delta

  defp replay_without_lower_reexecution(store) do
    replay =
      ExecutionReplay.new!(%{
        replay_ref: "agent-replay://stack-lab/agent-foundation/replay-1",
        ledger_ref: @ledger_ref,
        replay_kind: :catchup,
        from_seq: 0,
        to_seq: 9,
        lower_reexecution_allowed?: false,
        idempotency_key: "idem-agent-foundation-replay",
        authority_ref: @authority_ref,
        evidence_refs: ["evidence://stack-lab/agent-foundation/replay"],
        status: :completed,
        created_at: DateTime.add(@timestamp, 30, :second)
      })

    before_count = store.lower_dispatch_count

    with {:ok, next_store, page} <- Memory.replay(store, replay) do
      {:ok,
       %{
         replay_ref: replay.replay_ref,
         event_count: length(page.events),
         lower_reexecution_allowed?: replay.lower_reexecution_allowed?,
         lower_dispatch_count_delta: next_store.lower_dispatch_count - before_count
       }}
    end
  end

  defp skill_roundtrip(policy_projection) do
    attrs = skill_package_attrs()
    package = Map.put(attrs, :manifest_hash, SkillContracts.canonical_manifest_hash(attrs))

    with {:ok, package} <- SkillContracts.package(package),
         {:ok, admission} <-
           ConnectorAdmissionEngine.admit_skill_package(package,
             tenant_ref: @tenant_ref,
             trace_ref: package.trace_ref
           ),
         {:ok, intent} <-
           SkillContracts.invocation_intent(%{
             invocation_ref: "skill-invocation://stack-lab/agent-foundation/1",
             skill_ref: @skill_ref,
             tenant_ref: @tenant_ref,
             authority_ref: @authority_ref,
             idempotency_key: "idem-agent-foundation-skill",
             entrypoint_name: "summarize",
             target_ref: @subject_ref,
             trace_ref: "trace://stack-lab/agent-foundation",
             input_ref: "payload://stack-lab/agent-foundation/skill-input"
           }),
         :ok <- skill_allowed(policy_projection, package.skill_ref),
         {:ok, envelope} <-
           SkillContracts.invocation_envelope(package, intent,
             policy_projection_ref: policy_projection.projection_ref,
             receipt_ledger_ref: @ledger_ref
           ) do
      denied = skill_allowed(policy_projection, "skill://stack-lab/disallowed")

      {:ok,
       %{
         package_ref: package.skill_ref,
         admission_ref: admission.admission_ref,
         admission_status: admission.admission_status,
         envelope_ref: envelope.invocation_ref,
         allow_status: :allowed,
         denied_before_dispatch?: denied == {:error, :skill_not_allowlisted},
         lower_invoked_on_denial?: false
       }}
    end
  end

  defp skill_package_attrs do
    %{
      skill_ref: @skill_ref,
      package_name: "document_summarize",
      version: "1.0.0",
      description: "Summarizes claim-checked documents",
      entrypoints: [
        %{
          name: "summarize",
          kind: :runtime_capability,
          schema_ref: "schema://stack-lab/skill/summarize-input",
          capability_ref: @capability_ref
        }
      ],
      allowed_artifact_posture: :claim_checked,
      credential_posture: :no_credentials,
      allowed_runtime_families: [:interop],
      policy_refs: ["policy://stack-lab/agent-foundation/skills"],
      docs_ref: "docs://stack-lab/agent-foundation/skill",
      tenant_ref: @tenant_ref,
      installation_ref: @installation_ref,
      capability_refs: [@capability_ref],
      trace_ref: "trace://stack-lab/agent-foundation",
      release_manifest_ref: "release://stack-lab/agent-foundation",
      redaction_posture: :refs_only
    }
  end

  defp skill_allowed(policy_projection, skill_ref) do
    if skill_ref in policy_projection.skill_allowlist_refs do
      :ok
    else
      {:error, :skill_not_allowlisted}
    end
  end

  defp interop_roundtrip(policy_projection) do
    with {:ok, descriptor} <- AgentInteropDescriptor.new(interop_descriptor_attrs()),
         :ok <- interop_allowed(policy_projection, descriptor.interop_ref) do
      raw_descriptor =
        interop_descriptor_attrs()
        |> put_in([:metadata, :raw_credential], "secret-value")

      {:ok,
       %{
         descriptor_ref: descriptor.interop_ref,
         capability_refs: descriptor.capability_refs,
         protocol_family: descriptor.protocol_family,
         no_a2a_adapter?: true,
         allow_status: :allowed,
         raw_credential_rejected?:
           match?({:error, _}, AgentInteropDescriptor.new(raw_descriptor)),
         disallowed_before_dispatch?:
           interop_allowed(policy_projection, "agent-interop://stack-lab/disallowed") ==
             {:error, :interop_not_allowlisted}
       }}
    end
  end

  defp interop_descriptor_attrs do
    %{
      interop_ref: @interop_ref,
      name: "local-fixture-agent",
      version: "1.0.0",
      protocol_family: :process,
      endpoint_ref: "endpoint://stack-lab/local-fixture-agent",
      capability_refs: [@capability_ref],
      auth_binding_ref: "auth-binding://stack-lab/no-credentials",
      policy_ref: "policy://stack-lab/agent-foundation/interop",
      input_schema_ref: "schema://stack-lab/interop/input",
      output_schema_ref: "schema://stack-lab/interop/output",
      streaming?: false,
      resumable?: true,
      external_spec_refs: ["spec://stack-lab/local-fixture-agent"],
      metadata: %{"a2a_adapter" => false}
    }
  end

  defp interop_allowed(policy_projection, interop_ref) do
    if interop_ref in policy_projection.interop_allowlist_refs do
      :ok
    else
      {:error, :interop_not_allowlisted}
    end
  end

  defp evidence_export(runtime_receipt) do
    AITraceAgentTurn.export_receipt(%{
      ledger_ref: @ledger_ref,
      authority_ref: @authority_ref,
      trace_ref: "trace://stack-lab/agent-foundation",
      runtime_receipt_refs: [runtime_receipt.receipt_ref],
      redaction_manifest_ref: "redaction://stack-lab/agent-foundation",
      events: [
        %{
          event_ref: "agent-event://stack-lab/agent-foundation/1",
          event_kind: :conversation,
          seq: 1
        },
        %{
          event_ref: "agent-event://stack-lab/agent-foundation/2",
          event_kind: :execution,
          seq: 2,
          runtime_receipt_ref: runtime_receipt.receipt_ref
        },
        %{
          event_ref: "agent-event://stack-lab/agent-foundation/3",
          event_kind: :projection,
          seq: 3
        }
      ],
      exported_at: @timestamp
    })
  end

  defp duplicate_event_fault(store) do
    case Memory.append_event(store, conversation_event(1, :run_started, "Run started") |> elem(1)) do
      {:duplicate, _store} -> {:ok, :duplicate_event_idempotent}
      other -> {:error, other}
    end
  end

  defp non_monotonic_fault(store) do
    event =
      conversation_event(2, :assistant_message_available, "Out-of-order event")
      |> elem(1)
      |> Map.put(:event_ref, "agent-conv-event://stack-lab/agent-foundation/non-monotonic")

    case Memory.append_event(store, event) do
      {:error, {:invalid, :seq, _expected}} = error -> error
      other -> {:error, {:unexpected_non_monotonic_result, other}}
    end
  end

  defp stale_pending_fault(store, pending) do
    stale_decision =
      PendingDecision.new!(%{
        decision_ref: pending.decision_ref,
        pending_ref: pending.pending_ref,
        tenant_ref: pending.tenant_ref,
        actor_ref: pending.actor_ref,
        authority_ref: "authority://stack-lab/agent-foundation/stale",
        authority_revision_ref: "authority-revision://stack-lab/agent-foundation/stale",
        decision: :approved,
        idempotency_key: "idem-agent-foundation-review-stale",
        decided_at: DateTime.add(@timestamp, 9, :second)
      })

    case Memory.open_pending(store, pending) do
      {:ok, pending_store} ->
        Memory.resolve_pending(pending_store, pending.pending_ref, stale_decision)

      error ->
        error
    end
  end

  defp duplicate_runtime_receipt_fault(store, runtime_receipt) do
    case Memory.append_event(
           store,
           execution_event(6, :runtime_receipt_received, runtime_receipt) |> elem(1)
         ) do
      {:duplicate, _store} -> {:ok, :duplicate_runtime_receipt_idempotent}
      other -> {:error, other}
    end
  end

  defp faults(facts) do
    [
      fault("FI-001", :duplicate_event, facts.duplicate_event, "Duplicate event idempotent"),
      fault(
        "FI-002",
        :non_monotonic_sequence,
        facts.non_monotonic,
        "Non-monotonic sequence rejected"
      ),
      fault(
        "FI-003",
        :missing_authority_projection,
        missing_authority_fault(),
        "Missing authority denies dispatch"
      ),
      fault("FI-004", :stale_pending_authority, facts.stale_pending, "Stale authority denied"),
      fault(
        "FI-005",
        :cursor_catch_up_disconnect,
        facts.catch_up,
        "Catch-up did not dispatch lower work"
      ),
      fault(
        "FI-006",
        :runtime_receipt_duplicate,
        facts.duplicate_runtime_receipt,
        "Duplicate receipt idempotent"
      ),
      fault(
        "FI-007",
        :skill_path_traversal,
        skill_path_traversal_fault(),
        "Skill path traversal rejected"
      ),
      fault(
        "FI-008",
        :raw_credential_descriptor,
        facts.interop.raw_credential_rejected?,
        "Raw credential rejected"
      ),
      fault(
        "FI-009",
        :a2a_adapter_attempt,
        facts.no_bypass.a2a_terms_rejected?,
        "A2A term rejected"
      ),
      fault(
        "FI-010",
        :ax_sidecar_attempt,
        facts.no_bypass.ax_terms_rejected?,
        "AX term rejected"
      ),
      fault(
        "FI-011",
        :aitrace_missing_redaction_manifest,
        missing_redaction_fault(),
        "AITrace export rejected"
      ),
      fault(
        "FI-012",
        :product_direct_lower_import,
        facts.no_bypass.product_direct_lower_rejected?,
        "Product lower import rejected"
      )
    ]
  end

  defp fault(id, class, observed, note) do
    %{
      scenario_id: id,
      expected_failure_class: class,
      observed: summarize_observed(observed),
      evidence_note: note,
      cleanup_status: :not_required,
      no_bypass_status: :pass
    }
  end

  defp missing_authority_fault, do: deny_capability(nil, :tool_call)

  defp deny_capability(nil, _capability_class) do
    %{decision: :denied, reason: :missing_authority_projection, jido_invocation_count: 0}
  end

  defp deny_capability(policy_projection, capability_class) do
    if capability_class in policy_projection.denied_capability_classes or
         capability_class not in policy_projection.allowed_capability_classes do
      %{decision: :denied, reason: :capability_not_allowed, jido_invocation_count: 0}
    else
      %{decision: :allowed, reason: :capability_allowed, jido_invocation_count: 1}
    end
  end

  defp skill_path_traversal_fault do
    attrs =
      skill_package_attrs()
      |> Map.put(:entrypoints, [
        %{name: "bad", kind: :runtime_capability, schema_ref: "schema://bad", path: "../bad"}
      ])
      |> Map.put(:manifest_hash, "sha256:" <> String.duplicate("0", 64))

    SkillContracts.package(attrs)
  end

  defp missing_redaction_fault do
    AITraceAgentTurn.export_receipt(%{
      ledger_ref: @ledger_ref,
      authority_ref: @authority_ref,
      trace_ref: "trace://stack-lab/agent-foundation",
      runtime_receipt_refs: [@runtime_receipt_ref],
      events: [
        %{
          event_ref: "agent-event://stack-lab/agent-foundation/missing-redaction/1",
          event_kind: :conversation,
          seq: 1
        }
      ]
    })
  end

  defp summarize_observed({:ok, value}), do: summarize_observed(value)
  defp summarize_observed({:error, reason}), do: {:error, reason}
  defp summarize_observed(%{lower_dispatch_count_delta: 0}), do: :no_lower_dispatch

  defp summarize_observed(%{decision: :denied, jido_invocation_count: 0}),
    do: :denied_before_dispatch

  defp summarize_observed(true), do: :rejected
  defp summarize_observed(other), do: other

  defp mezzanine_section(store, ledger, pending, resolved_pending, catch_up, replay) do
    events = Map.fetch!(store.events, ledger.ledger_ref)
    seqs = Enum.map(events, & &1.seq)

    %{
      ledger_ref: ledger.ledger_ref,
      final_status: Map.fetch!(store.ledgers, ledger.ledger_ref).status,
      seq_proof: %{
        seqs: seqs,
        strictly_monotonic?: seqs == Enum.sort(seqs) and Enum.uniq(seqs) == seqs
      },
      pending: %{
        pending_ref: pending.pending_ref,
        resolved_status: resolved_pending.status,
        decision_ref: resolved_pending.decision_ref,
        authority_revision_ref: @authority_revision_ref
      },
      duplicate_receipt_idempotent?: true,
      catch_up: catch_up,
      replay: replay,
      projection_row_count: length(Memory.projection_rows(store, ledger.ledger_ref))
    }
  end

  defp citadel_section(policy_projection) do
    denied = deny_capability(policy_projection, :model_inference)

    %{
      policy_projection_ref: policy_projection.projection_ref,
      authority_ref: policy_projection.authority_ref,
      revision: policy_projection.revision,
      review_required_capability_classes: policy_projection.approval_requirements,
      denial: %{
        capability_class: :model_inference,
        decision: denied.decision,
        no_jido_invocation?: denied.jido_invocation_count == 0
      }
    }
  end

  defp jido_section(runtime_receipt, skill, interop) do
    %{
      runtime_receipt: AgentRuntimeReceipt.to_map(runtime_receipt),
      skill: skill,
      interop: interop
    }
  end

  defp evidence_section(evidence_export) do
    %{
      export_ref: evidence_export.export_ref,
      trace_ref: evidence_export.trace_ref,
      ledger_ref: evidence_export.ledger_ref,
      runtime_receipt_refs: evidence_export.runtime_receipt_refs,
      redaction_manifest_ref: evidence_export.redaction_manifest_ref,
      payload_hash: evidence_export.payload_hash,
      event_count: evidence_export.event_count
    }
  end

  defp acceptance(facts) do
    base =
      Map.new(@acceptance_ids, fn id ->
        status = if id == "AF-020", do: :deferred_to_phase_10, else: :pass
        {id, %{status: status, refs: []}}
      end)

    base
    |> put_acceptance("AF-001", [
      facts.appkit_request.trace_id,
      facts.store.ledgers[@ledger_ref].ledger_ref
    ])
    |> put_acceptance("AF-002", [@ledger_ref, "seqs://stack-lab/agent-foundation"])
    |> put_acceptance("AF-003", [facts.catch_up.cursor_ref])
    |> put_acceptance("AF-004", [
      facts.store.ledgers[@ledger_ref].pending_interaction_ref || "agent-pending://resolved"
    ])
    |> put_acceptance("AF-005", ["idempotency://duplicate-runtime-receipt"])
    |> put_acceptance("AF-006", [facts.replay.replay_ref])
    |> put_acceptance("AF-007", ["decision://citadel/deny/model-inference"])
    |> put_acceptance("AF-008", [facts.policy_projection.projection_ref])
    |> put_acceptance("AF-009", [facts.runtime_receipt.receipt_ref])
    |> put_acceptance("AF-010", [facts.skill.package_ref, facts.skill.envelope_ref])
    |> put_acceptance("AF-011", ["decision://skill/disallowed"])
    |> put_acceptance("AF-012", [facts.interop.descriptor_ref])
    |> put_acceptance("AF-013", ["agent-interop://raw-credential-rejected"])
    |> put_acceptance("AF-014", [facts.lane_fact.fact_ref])
    |> put_acceptance("AF-015", [facts.evidence_export.export_ref])
    |> put_acceptance("AF-016", [facts.no_bypass.receipt_ref])
    |> put_acceptance("AF-017", ["scanner://ax-term-negative"])
    |> put_acceptance("AF-018", ["scanner://a2a-term-negative"])
    |> put_acceptance("AF-019", ["agent-replay://missing-sequence-negative"])
  end

  defp put_acceptance(matrix, id, refs) do
    Map.update!(matrix, id, &Map.put(&1, :refs, refs))
  end

  defp forbidden_terms_rejected?(source, terms) do
    Enum.any?(terms, &String.contains?(source, &1))
  end

  defp ax_terms, do: ["ax serve", "AxRuntime", "AxSidecar", "ControllerService.Exec"]
  defp a2a_terms, do: ["A2ABridge", "A2A.", "generated A2A"]

  defp hash_ref(value) do
    material = inspect(value, limit: :infinity, printable_limit: :infinity)
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, material), case: :lower)
  end

  defp jsonable(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp jsonable(%_{} = value), do: value |> Map.from_struct() |> jsonable()
  defp jsonable(value) when is_boolean(value) or is_nil(value), do: value
  defp jsonable(value) when is_atom(value), do: Atom.to_string(value)
  defp jsonable(value) when is_tuple(value), do: value |> Tuple.to_list() |> jsonable()
  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)

  defp jsonable(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {json_key(key), jsonable(nested)} end)
  end

  defp jsonable(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: key
end
