defmodule StackLab.Examples.SessionLineageDrill do
  @moduledoc """
  Deterministic assembled proof for agent-turn runtime lineage.

  The proof is provider-free. It models the runtime facts that must survive a
  multi-turn agent session: semantic context, authority, dynamic tool manifest
  resolution, lower runtime dispatch, fallback under fault, and AITrace replay
  lineage.
  """

  @schema_version "gn_ten_agent_turn_runtime_patterns_v1"
  @proof_id "agent_turn_runtime_patterns"
  @profile "assembled_offline"
  @named_proof_ref "proof://stack-lab/agent-turn-runtime-patterns/session-lineage-drill/v1"
  @receipt_ref "receipt://stack_lab/agent_turn_runtime_patterns/latest"
  @required_repos ~w(outer_brain citadel jido_integration execution_plane mezzanine AITrace)
  @required_event_kinds ~w(
    turn_started
    semantic_context_restored
    dynamic_tool_manifest_resolved
    authority_checked
    lower_runtime_invoked
    fallback_lane_selected
    operation_receipt_recorded
    trace_replay_exported
  )

  def scenario do
    %{
      name: :session_lineage_drill,
      compose: StackLab.LabCore.compose_file(:multi),
      runbook: StackLab.LabCore.runbook(:up_multi),
      proof: proof()
    }
  end

  def proof do
    %{
      schema_version: @schema_version,
      proof_id: @proof_id,
      profile: @profile,
      named_proof_ref: @named_proof_ref,
      receipt_ref: @receipt_ref,
      provider_free?: true,
      compose: StackLab.LabCore.compose_file(:multi),
      runbook: StackLab.LabCore.runbook(:up_multi),
      repo_evidence: repo_evidence(),
      turns: turns(),
      dynamic_tool_manifest: dynamic_tool_manifest(),
      recovery: recovery(),
      fault_injection: fault_injection(),
      aitrace_lineage: aitrace_lineage(),
      does_not_prove: [
        "live provider behavior",
        "production multi-node runtime behavior",
        "real dynamic tool registry mutation",
        "production AITrace retention policy"
      ]
    }
  end

  def validate_proof(proof) when is_map(proof) do
    failures =
      []
      |> require_equal("agent_turn_bad_schema", proof[:schema_version], @schema_version)
      |> require_equal("agent_turn_bad_id", proof[:proof_id], @proof_id)
      |> require_equal("agent_turn_bad_profile", proof[:profile], @profile)
      |> require_equal("agent_turn_not_provider_free", proof[:provider_free?], true)
      |> require_file("agent_turn_missing_compose", proof[:compose])
      |> require_file("agent_turn_missing_runbook", proof[:runbook])
      |> validate_repo_evidence(proof[:repo_evidence])
      |> validate_turns(proof[:turns])
      |> validate_dynamic_tool_manifest(proof[:dynamic_tool_manifest])
      |> validate_recovery(proof[:recovery])
      |> validate_fault_injection(proof[:fault_injection])
      |> validate_aitrace_lineage(proof[:aitrace_lineage])

    case failures do
      [] -> :ok
      failures -> {:error, Enum.reverse(failures)}
    end
  end

  def validate_proof(_proof), do: {:error, [%{code: "agent_turn_invalid_proof"}]}

  defp repo_evidence do
    [
      %{
        repo: "outer_brain",
        responsibility: "semantic context and memory continuity",
        refs: [
          "outer-brain://session-lineage/semantic-session/demo",
          "outer-brain://session-lineage/context-snapshot/turn-1"
        ]
      },
      %{
        repo: "citadel",
        responsibility: "authority decision and scoped tool admission",
        refs: [
          "citadel://authority/session-lineage/decision/turn-1",
          "citadel://authority/session-lineage/decision/turn-2"
        ]
      },
      %{
        repo: "jido_integration",
        responsibility: "dynamic tool manifest and connector route binding",
        refs: [
          "jido://tool-manifest/session-lineage/v2",
          "jido://connector-binding/session-lineage/provider-free"
        ]
      },
      %{
        repo: "execution_plane",
        responsibility: "lower lane dispatch and fallback lane selection",
        refs: [
          "execution-plane://lane/session-lineage/primary",
          "execution-plane://lane/session-lineage/fallback"
        ]
      },
      %{
        repo: "mezzanine",
        responsibility: "workflow run, checkpoint, and operation receipt",
        refs: [
          "mezzanine://workflow/session-lineage/run/demo",
          "mezzanine://checkpoint/session-lineage/turn-1"
        ]
      },
      %{
        repo: "AITrace",
        responsibility: "lineage event export and replay join",
        refs: [
          "trace://stack-lab/agent-turn-runtime-patterns/demo",
          "replay://stack-lab/agent-turn-runtime-patterns/demo"
        ]
      }
    ]
  end

  defp turns do
    [
      %{
        turn_index: 1,
        turn_ref: "turn://session-lineage/demo/1",
        semantic_context_ref: "outer-brain://session-lineage/context-snapshot/turn-1",
        authority_decision_ref: "citadel://authority/session-lineage/decision/turn-1",
        tool_manifest_ref: "jido://tool-manifest/session-lineage/v2",
        lower_runtime_ref: "execution-plane://lane/session-lineage/primary",
        receipt_ref: "receipt://stack_lab/agent_turn_runtime_patterns/turn-1"
      },
      %{
        turn_index: 2,
        turn_ref: "turn://session-lineage/demo/2",
        restored_from_turn_ref: "turn://session-lineage/demo/1",
        semantic_context_ref: "outer-brain://session-lineage/context-snapshot/turn-1",
        authority_decision_ref: "citadel://authority/session-lineage/decision/turn-2",
        tool_manifest_ref: "jido://tool-manifest/session-lineage/v2",
        lower_runtime_ref: "execution-plane://lane/session-lineage/fallback",
        receipt_ref: "receipt://stack_lab/agent_turn_runtime_patterns/turn-2"
      }
    ]
  end

  defp dynamic_tool_manifest do
    %{
      manifest_ref: "jido://tool-manifest/session-lineage/v2",
      revision: 2,
      resolved_after_recovery?: true,
      allowed_tool_role_refs: [
        "tool-role://session-lineage/context.read",
        "tool-role://session-lineage/change.prepare"
      ],
      selected_tool_role_ref: "tool-role://session-lineage/change.prepare",
      rejected_tool_role_ref: "tool-role://session-lineage/provider.admin",
      unauthorized_tool_rejected?: true
    }
  end

  defp recovery do
    %{
      checkpoint_ref: "mezzanine://checkpoint/session-lineage/turn-1",
      recovered?: true,
      recovered_turn_ref: "turn://session-lineage/demo/2",
      replayed_turn_refs: ["turn://session-lineage/demo/1"],
      semantic_context_restored?: true,
      manifest_revision_preserved?: true
    }
  end

  defp fault_injection do
    %{
      fault_ref: "fault://stack-lab/session-lineage/primary-lane-timeout",
      injected_fault: "primary_lane_timeout",
      fallback_selected?: true,
      fallback_lane_ref: "execution-plane://lane/session-lineage/fallback",
      fallback_authorized_by_ref: "citadel://authority/session-lineage/decision/turn-2",
      unmanifested_tool_failed_closed?: true,
      operation_receipt_ref: "receipt://stack_lab/agent_turn_runtime_patterns/fallback"
    }
  end

  defp aitrace_lineage do
    %{
      trace_ref: "trace://stack-lab/agent-turn-runtime-patterns/demo",
      replay_ref: "replay://stack-lab/agent-turn-runtime-patterns/demo",
      event_kinds: @required_event_kinds,
      event_refs: Enum.map(@required_event_kinds, &"event://stack-lab/agent-turn/#{&1}"),
      source_turn_refs: ["turn://session-lineage/demo/1", "turn://session-lineage/demo/2"],
      replay_causality_verified?: true
    }
  end

  defp validate_repo_evidence(failures, repo_evidence) when is_list(repo_evidence) do
    present = repo_evidence |> Enum.map(& &1.repo) |> Enum.sort()

    failures
    |> require_equal("agent_turn_missing_repo_evidence", present, Enum.sort(@required_repos))
    |> require_all_refs("agent_turn_missing_repo_refs", repo_evidence)
  end

  defp validate_repo_evidence(failures, _repo_evidence) do
    [failure("agent_turn_missing_repo_evidence") | failures]
  end

  defp validate_turns(failures, [first_turn, second_turn | _rest]) do
    failures
    |> require_present("agent_turn_missing_first_receipt", first_turn.receipt_ref)
    |> require_present("agent_turn_missing_second_receipt", second_turn.receipt_ref)
    |> require_equal(
      "agent_turn_missing_restored_turn",
      second_turn.restored_from_turn_ref,
      first_turn.turn_ref
    )
    |> require_equal(
      "agent_turn_manifest_not_preserved",
      second_turn.tool_manifest_ref,
      first_turn.tool_manifest_ref
    )
  end

  defp validate_turns(failures, _turns) do
    [failure("agent_turn_needs_multi_turn_recovery") | failures]
  end

  defp validate_dynamic_tool_manifest(failures, %{} = manifest) do
    failures
    |> require_present("agent_turn_missing_manifest_ref", manifest.manifest_ref)
    |> require_equal("agent_turn_manifest_not_recovered", manifest.resolved_after_recovery?, true)
    |> require_equal(
      "agent_turn_unmanifested_tool_not_rejected",
      manifest.unauthorized_tool_rejected?,
      true
    )
    |> require_nonempty_list("agent_turn_missing_allowed_tools", manifest.allowed_tool_role_refs)
  end

  defp validate_dynamic_tool_manifest(failures, _manifest) do
    [failure("agent_turn_missing_dynamic_tool_manifest") | failures]
  end

  defp validate_recovery(failures, %{} = recovery) do
    failures
    |> require_present("agent_turn_missing_checkpoint", recovery.checkpoint_ref)
    |> require_equal("agent_turn_not_recovered", recovery.recovered?, true)
    |> require_equal("agent_turn_context_not_restored", recovery.semantic_context_restored?, true)
    |> require_equal(
      "agent_turn_manifest_revision_lost",
      recovery.manifest_revision_preserved?,
      true
    )
    |> require_nonempty_list("agent_turn_missing_replayed_turns", recovery.replayed_turn_refs)
  end

  defp validate_recovery(failures, _recovery) do
    [failure("agent_turn_missing_recovery") | failures]
  end

  defp validate_fault_injection(failures, %{} = fault) do
    failures
    |> require_present("agent_turn_missing_fault_ref", fault.fault_ref)
    |> require_equal("agent_turn_fallback_not_selected", fault.fallback_selected?, true)
    |> require_present("agent_turn_missing_fallback_lane", fault.fallback_lane_ref)
    |> require_equal(
      "agent_turn_unmanifested_tool_not_failed_closed",
      fault.unmanifested_tool_failed_closed?,
      true
    )
    |> require_present("agent_turn_missing_fallback_receipt", fault.operation_receipt_ref)
  end

  defp validate_fault_injection(failures, _fault) do
    [failure("agent_turn_missing_fault_injection") | failures]
  end

  defp validate_aitrace_lineage(failures, %{} = lineage) do
    missing_events = @required_event_kinds -- List.wrap(lineage.event_kinds)

    failures
    |> require_present("agent_turn_missing_trace_ref", lineage.trace_ref)
    |> require_present("agent_turn_missing_replay_ref", lineage.replay_ref)
    |> require_equal(
      "agent_turn_replay_causality_not_verified",
      lineage.replay_causality_verified?,
      true
    )
    |> require_equal("agent_turn_missing_aitrace_events", missing_events, [])
    |> require_nonempty_list("agent_turn_missing_event_refs", lineage.event_refs)
  end

  defp validate_aitrace_lineage(failures, _lineage) do
    [failure("agent_turn_missing_aitrace_lineage") | failures]
  end

  defp require_all_refs(failures, code, repo_evidence) do
    if Enum.all?(repo_evidence, &match?([_ | _], &1.refs)) do
      failures
    else
      [failure(code) | failures]
    end
  end

  defp require_file(failures, _code, path) when is_binary(path) do
    if File.exists?(path),
      do: failures,
      else: [failure("agent_turn_missing_file", path: path) | failures]
  end

  defp require_file(failures, code, path), do: [failure(code, actual: inspect(path)) | failures]

  defp require_present(failures, _code, value) when is_binary(value) and value != "", do: failures

  defp require_present(failures, code, value),
    do: [failure(code, actual: inspect(value)) | failures]

  defp require_nonempty_list(failures, _code, [_ | _]), do: failures

  defp require_nonempty_list(failures, code, value),
    do: [failure(code, actual: inspect(value)) | failures]

  defp require_equal(failures, _code, actual, expected) when actual == expected, do: failures

  defp require_equal(failures, code, actual, expected),
    do: [failure(code, expected: inspect(expected), actual: inspect(actual)) | failures]

  defp failure(code, attrs \\ []), do: Map.new([{:code, code} | attrs])
end
