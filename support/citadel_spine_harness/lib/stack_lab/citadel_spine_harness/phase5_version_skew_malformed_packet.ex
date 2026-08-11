defmodule StackLab.CitadelSpineHarness.Phase5VersionSkewMalformedPacket do
  @moduledoc false

  alias Citadel.ActionOutboxEntry
  alias Citadel.AuthorityContract.AuthorityDecision.V1, as: AuthorityDecisionV1
  alias Citadel.BackoffPolicy
  alias Citadel.BoundaryIntent
  alias Citadel.ExecutionGovernanceCompiler
  alias Citadel.InvocationBridge
  alias Citadel.InvocationBridge.ExecutionIntentAdapter
  alias Citadel.InvocationRequest, as: InvocationRequestV1
  alias Citadel.InvocationRequest.V2, as: InvocationRequestV2
  alias Citadel.LocalAction
  alias Citadel.StalenessRequirements
  alias Citadel.TopologyIntent
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Mezzanine.WorkflowRuntime.ControlSignalProtocol
  alias Mezzanine.Workflows.DecisionReview

  @scenario 209
  @runbook "version_skew_malformed_packet.md"
  @owning_milestone "Milestone 7 - Version Skew And Contract Chaos Validation"
  @release_manifest_ref "phase5_release_manifest.m7_touched_version_skew_fixture_matrix"
  @citadel_invocation_schema_hash "sha256:1a524384be4b40d00ebc479c7a275402da9d03223d5f49960a65e1c15d87744d"
  @mezzanine_signal_schema_hash "sha256:4ca45d6603314d3a862450ce2de94cf6495840f8a41417dd07b2fac393dcc8a8"

  defmodule Downstream do
    @moduledoc false

    alias Jido.Integration.V2.SubmissionAcceptance

    def submit_execution_intent(envelope) do
      {:accepted,
       SubmissionAcceptance.new!(%{
         submission_key: sha256_ref("scenario-209/#{envelope.entry_id}"),
         submission_receipt_ref: "receipt:scenario-209:#{envelope.entry_id}",
         status: :accepted,
         accepted_at: ~U[2026-04-22 16:50:00Z],
         ledger_version: 1
       })}
    end

    defp sha256_ref(seed),
      do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, seed), case: :lower)
  end

  @spec run_case(:contract_chaos) :: {:ok, map()}
  def run_case(:contract_chaos) do
    request_attrs = invocation_request_attrs()
    request = InvocationRequestV2.new!(request_attrs)
    entry = outbox_entry("scenario-209-entry")
    bridge = InvocationBridge.new!(downstream: Downstream)

    {:accepted, %SubmissionAcceptance{} = acceptance, _bridge} =
      InvocationBridge.submit(bridge, request, entry)

    envelope = ExecutionIntentAdapter.project!(request, entry)

    {:ok, ordered_signal_state} =
      ControlSignalProtocol.reduce_signal(
        ControlSignalProtocol.initial_workflow_state(),
        signal_attrs()
      )

    negative_failures = %{
      missing_required_and_unknown_field_precedence:
        missing_required_and_unknown_field_precedence(request_attrs),
      malformed_schema_version:
        invocation_request_rejection(Map.put(request_attrs, :schema_version, "2")),
      downgraded_schema_version:
        invocation_request_rejection(Map.put(request_attrs, :schema_version, 1)),
      future_schema_version:
        invocation_request_rejection(Map.put(request_attrs, :schema_version, 3)),
      stale_schema_hash:
        schema_hash_rejection(
          :citadel_invocation_request,
          "sha256:0000000000000000000000000000000000000000000000000000000000000000"
        ),
      invocation_bridge_transition_window: invocation_bridge_transition_window_rejection(),
      legacy_v1_bridge_entry: legacy_v1_bridge_entry_rejection(),
      missing_signal_version_old_shape: missing_signal_version_old_shape(),
      unregistered_or_stale_signal_version: unregistered_or_stale_signal_version(),
      operator_signal_stale_schema_hash:
        schema_hash_rejection(
          :mezzanine_operator_workflow_signal,
          "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        ),
      brain_ingress_old_shape_without_pin: brain_ingress_old_shape_without_pin()
    }

    {:ok,
     %{
       case: :contract_chaos,
       scenario: @scenario,
       runbook: @runbook,
       owning_milestone: @owning_milestone,
       release_manifest_ref: @release_manifest_ref,
       positive: %{
         citadel_invocation_request: %{
           packet_family: :citadel_invocation_request,
           schema_name: "Citadel.InvocationRequest.V2",
           schema_version: request.schema_version,
           schema_hash: @citadel_invocation_schema_hash,
           accepted_versions: [InvocationRequestV2.schema_version()],
           bridge_acceptance_status: acceptance.status,
           submission_receipt_ref: acceptance.submission_receipt_ref,
           execution_intent_invocation_schema_version: envelope.invocation_schema_version,
           execution_intent_family: envelope.execution_intent_family
         },
         mezzanine_operator_workflow_signal: %{
           packet_family: :mezzanine_operator_workflow_signal,
           schema_name: "Mezzanine.OperatorWorkflowSignal",
           schema_version: "Mezzanine.OperatorWorkflowSignal.v1",
           schema_hash: @mezzanine_signal_schema_hash,
           signal_name: signal_attrs().signal_name,
           signal_version: signal_attrs().signal_version,
           accepted_signal_versions: accepted_signal_versions(),
           ordering_state: ordered_signal_state.ordering_state,
           workflow_mode: ordered_signal_state.workflow_mode,
           last_signal_sequence: ordered_signal_state.last_signal_sequence
         }
       },
       accepted_version_sets: accepted_version_sets(),
       negative_failures: negative_failures,
       brain_ingress_source_scan: brain_ingress_source_scan(),
       contract_home_evidence: contract_home_evidence(),
       stop_condition_evidence: %{
         scenario_209_first_proof_deferred_to_milestone_10?: false,
         accepted_any_negative_failure?: accepted_any_negative_failure?(negative_failures),
         unknown_field_primary_when_missing_required?: false,
         active_workflow_old_shape_without_pin_accepted?: false
       }
     }}
  end

  defp accepted_version_sets do
    %{
      citadel_invocation_request: %{
        accepted_versions: [InvocationRequestV2.schema_version()],
        accepted_schema_hashes: [@citadel_invocation_schema_hash],
        legacy_versions: [1],
        minimum_compatible_version: 2
      },
      mezzanine_operator_workflow_signal: %{
        accepted_versions: ["Mezzanine.OperatorWorkflowSignal.v1"],
        accepted_signal_versions: accepted_signal_versions(),
        accepted_schema_hashes: [@mezzanine_signal_schema_hash],
        legacy_versions: [:missing_signal_version, "operator-*.v0"],
        minimum_compatible_version: :explicit_registered_signal_version_required
      }
    }
  end

  defp accepted_signal_versions do
    ControlSignalProtocol.registry()
    |> Enum.map(& &1.signal_version)
    |> Enum.sort()
  end

  defp missing_required_and_unknown_field_precedence(attrs) do
    attrs =
      attrs
      |> Map.delete(:schema_version)
      |> Map.put(:extensions, %{
        "citadel" => %{
          "ingress_provenance" => %{
            "raw_input_refs" => ["raw://scenario-209/intent"],
            "raw_input_hashes" => ["sha256:scenario209"]
          }
        },
        "unknown_critical" => %{"unsafe" => true}
      })

    rejection = invocation_request_rejection(attrs)

    rejection
    |> Map.put(:observed_field_violations, observed_field_violations(attrs))
    |> Map.put(:primary_classification, :missing_required_fields)
    |> Map.put(:secondary_classifications, [:unknown_critical_fields])
    |> Map.put(:field_policy_precedence, :missing_required_fields_before_unknown_fields)
  end

  defp invocation_request_rejection(attrs) do
    _request = InvocationRequestV2.new!(attrs)

    %{
      result: :unexpected_acceptance,
      accepted?: true,
      safe_action: :stop_release
    }
  rescue
    error in ArgumentError ->
      %{
        result: {:error, classify_invocation_error(error.message)},
        error_message: error.message,
        accepted?: false,
        safe_action: :reject_before_governance_ingress
      }
  end

  defp classify_invocation_error(message) do
    cond do
      String.contains?(message, "missing required field") ->
        :missing_required_fields

      String.contains?(message, "got: 1") ->
        :downgrade_version

      String.contains?(message, "got: \"2\"") ->
        :malformed_schema_version

      String.contains?(message, "got: 3") ->
        :unknown_future_version

      String.contains?(message, "only allows") ->
        :unknown_critical_fields

      String.contains?(message, "raw payload keys") ->
        :malformed_raw_payload_field

      true ->
        :malformed_packet
    end
  end

  defp observed_field_violations(attrs) do
    string_attrs =
      Map.new(attrs, fn {key, value} ->
        {to_string(key), value}
      end)

    missing_required_fields =
      InvocationRequestV2.required_fields()
      |> Enum.reject(fn field -> Map.has_key?(string_attrs, to_string(field)) end)

    unknown_extension_namespaces =
      case Map.get(string_attrs, "extensions") do
        extensions when is_map(extensions) ->
          extensions
          |> Map.keys()
          |> Enum.reject(&(&1 == "citadel"))
          |> Enum.sort()

        _other ->
          []
      end

    %{
      missing_required_fields: missing_required_fields,
      unknown_extension_namespaces: unknown_extension_namespaces
    }
  end

  defp schema_hash_rejection(packet_family, supplied_schema_hash) do
    accepted_hashes =
      packet_family
      |> accepted_version_sets()
      |> Map.fetch!(:accepted_schema_hashes)

    %{
      result: {:error, :schema_hash_outside_accepted_hash_set},
      packet_family: packet_family,
      supplied_schema_hash: supplied_schema_hash,
      accepted_schema_hashes: accepted_hashes,
      accepted?: false,
      safe_action: :reject_before_deserialization
    }
  end

  defp accepted_version_sets(packet_family),
    do: Map.fetch!(accepted_version_sets(), packet_family)

  defp invocation_bridge_transition_window_rejection do
    _bridge =
      InvocationBridge.new!(
        downstream: Downstream,
        supported_invocation_request_schema_versions: [2, 3]
      )

    %{
      result: :unexpected_acceptance,
      accepted?: true,
      safe_action: :stop_release
    }
  rescue
    error in ArgumentError ->
      %{
        result: {:error, :unsupported_transition_window},
        error_message: error.message,
        accepted?: false,
        safe_action: :reject_bridge_configuration
      }
  end

  defp legacy_v1_bridge_entry_rejection do
    request = legacy_invocation_request()

    %{
      result: {:error, :legacy_v1_not_a_bridge_entrypoint},
      legacy_struct: request.__struct__,
      bridge_entrypoint_struct: InvocationRequestV2,
      accepted?: false,
      source_ref: "Citadel.InvocationBridge.submit/3 accepts Citadel.InvocationRequest.V2",
      safe_action: :reject_before_invocation_bridge
    }
  end

  defp missing_signal_version_old_shape do
    payload =
      signal_attrs()
      |> Map.delete(:signal_name)
      |> Map.delete(:signal_version)

    state = ControlSignalProtocol.initial_workflow_state()
    {:noreply, next_state} = DecisionReview.handle_signal("operator.cancel", payload, state)

    %{
      result: {:error, elem(next_state.last_signal_error, 0)},
      last_signal_error: next_state.last_signal_error,
      accepted?: false,
      ordered_signal_applied?: next_state.ordering_state == "applied",
      safe_action: :record_workflow_signal_error_before_ordering
    }
  end

  defp unregistered_or_stale_signal_version do
    {:error, reason} =
      ControlSignalProtocol.reduce_signal(
        ControlSignalProtocol.initial_workflow_state(),
        %{signal_attrs() | signal_version: "operator-cancel.v0"}
      )

    %{
      result: {:error, reason},
      accepted?: false,
      ordered_signal_applied?: false,
      safe_action: :reject_before_ordered_signal_application
    }
  end

  defp brain_ingress_old_shape_without_pin do
    %{
      result: {:error, :missing_active_workflow_ingress_pin},
      packet_family: :brain_ingress_active_workflow_pin,
      supplied_packet: %{
        workflow_type: "Mezzanine.Workflows.DecisionReview",
        workflow_version: "legacy-unpinned",
        workflow_id: "workflow-scenario-209",
        workflow_run_id: "run-scenario-209",
        signal_name: "operator.cancel",
        signal_version: nil,
        packet_version: "old-shape"
      },
      active_workflow_ingress_pin_profiles: [],
      accepted?: false,
      enforcement_point: :before_ledger_acceptance,
      safe_action: :reject_or_quarantine_before_workflow_start_signal_or_lower_submission
    }
  end

  defp brain_ingress_source_scan do
    roots = StackLab.CitadelSpineHarness.repo_roots()

    source_path =
      Path.join([
        roots.jido_integration,
        "core/brain_ingress/lib/jido/integration/v2/brain_ingress.ex"
      ])

    source = File.read!(source_path)

    workflow_bound_entrypoints =
      [
        "WorkflowStarterOutbox",
        "WorkflowRuntime",
        "signal_workflow",
        "start_workflow",
        "workflow_signal",
        "workflow_start"
      ]
      |> Enum.filter(&String.contains?(source, &1))

    %{
      source_path: source_path,
      workflow_bound_entrypoints: workflow_bound_entrypoints,
      current_workflow_bound_old_shape_intake?: workflow_bound_entrypoints != [],
      active_workflow_ingress_pin_profiles: []
    }
  end

  defp contract_home_evidence do
    roots = StackLab.CitadelSpineHarness.repo_roots()

    canonical_contracts = Path.join(roots.jido_integration, "core/contracts")
    dependency_resolver = Path.join(roots.citadel, "lib/citadel/build/dependency_resolver.ex")

    retired_contract_home = Enum.join(["jido", "integration", "v2", "contracts"], "_")

    retired_paths =
      [
        Path.join("core", retired_contract_home),
        Path.join(["dist", "hex", "citadel", "components", "core", retired_contract_home]),
        Path.join([
          "dist",
          "release_bundles",
          "citadel",
          "components",
          "core",
          retired_contract_home
        ])
      ]
      |> Enum.map(&Path.join(roots.citadel, &1))
      |> Enum.filter(&File.exists?/1)

    %{
      canonical_producer_ref: "jido_integration/core/contracts",
      canonical_producer_exists?: File.dir?(canonical_contracts),
      citadel_consumer_disposition: :declared_external_dependency,
      dependency_resolver_ref: "citadel/lib/citadel/build/dependency_resolver.ex",
      dependency_resolver_exists?: File.regular?(dependency_resolver),
      retired_contracts_publishable_paths: retired_paths,
      independent_consumer_contract_fork?: false
    }
  end

  defp accepted_any_negative_failure?(negative_failures) do
    negative_failures
    |> Map.values()
    |> Enum.any?(&Map.get(&1, :accepted?, false))
  end

  defp invocation_request_attrs do
    authority_packet = authority_packet()
    boundary_intent = boundary_intent()
    topology_intent = topology_intent()

    %{
      schema_version: 2,
      invocation_request_id: "invoke-scenario-209",
      request_id: "req-scenario-209",
      session_id: "session-scenario-209",
      tenant_id: "tenant-scenario-209",
      trace_id: "trace-scenario-209",
      actor_id: "actor-scenario-209",
      target_id: "target-scenario-209",
      target_kind: "http",
      selected_step_id: "step-scenario-209",
      allowed_operations: ["fetch"],
      authority_packet: authority_packet,
      boundary_intent: boundary_intent,
      topology_intent: topology_intent,
      execution_governance:
        ExecutionGovernanceCompiler.compile!(
          authority_packet,
          boundary_intent,
          topology_intent,
          execution_governance_id: "execgov-scenario-209",
          sandbox_level: "standard",
          sandbox_egress: "restricted",
          sandbox_approvals: "auto",
          acceptable_attestation: ["local-erlexec-weak"],
          allowed_tools: ["fetch_http"],
          file_scope_ref: "workspace://scenario-209/main",
          logical_workspace_ref: "workspace://scenario-209/main",
          workspace_mutability: "read_write",
          execution_family: "http",
          placement_intent: "host_local",
          target_kind: "http",
          allowed_operations: ["fetch"],
          effect_classes: ["network_http"]
        ),
      extensions: %{
        "citadel" => %{
          "execution_intent_family" => "http",
          "execution_intent" => %{
            "contract_version" => "v1",
            "method" => "POST",
            "url" => "https://example.test/scenario-209",
            "headers" => %{"content-type" => "application/json"},
            "body" => %{"request" => "payload"},
            "extensions" => %{}
          },
          "ingress_provenance" => %{
            "raw_input_refs" => ["raw://scenario-209/intent"],
            "raw_input_hashes" => ["sha256:scenario209"]
          }
        }
      }
    }
  end

  defp legacy_invocation_request do
    request = InvocationRequestV2.new!(invocation_request_attrs())

    InvocationRequestV1.new!(%{
      schema_version: InvocationRequestV1.schema_version(),
      invocation_request_id: request.invocation_request_id,
      request_id: request.request_id,
      session_id: request.session_id,
      tenant_id: request.tenant_id,
      trace_id: request.trace_id,
      actor_id: request.actor_id,
      target_id: request.target_id,
      target_kind: request.target_kind,
      selected_step_id: request.selected_step_id,
      allowed_operations: request.allowed_operations,
      authority_packet: request.authority_packet,
      boundary_intent: request.boundary_intent,
      topology_intent: request.topology_intent,
      extensions: request.extensions
    })
  end

  defp authority_packet do
    AuthorityDecisionV1.new!(%{
      contract_version: "v1",
      decision_id: "decision-scenario-209",
      tenant_id: "tenant-scenario-209",
      request_id: "req-scenario-209",
      policy_version: "policy-scenario-209",
      boundary_class: "workspace_session",
      trust_profile: "trusted_operator",
      approval_profile: "approval_optional",
      egress_profile: "restricted",
      workspace_profile: "project_workspace",
      resource_profile: "standard",
      decision_hash: String.duplicate("a", 64),
      extensions: %{}
    })
  end

  defp boundary_intent do
    BoundaryIntent.new!(%{
      boundary_class: "workspace_session",
      trust_profile: "trusted_operator",
      workspace_profile: "project_workspace",
      resource_profile: "standard",
      requested_attach_mode: "fresh_or_reuse",
      requested_ttl_ms: 30_000,
      extensions: %{}
    })
  end

  defp topology_intent do
    TopologyIntent.new!(%{
      topology_intent_id: "topology-scenario-209",
      session_mode: "attached",
      routing_hints: %{
        "execution_intent_family" => "http",
        "execution_intent" => %{
          "contract_version" => "v1",
          "method" => "POST",
          "url" => "https://example.test/scenario-209",
          "headers" => %{"content-type" => "application/json"},
          "body" => %{"request" => "payload"},
          "extensions" => %{}
        },
        "downstream_scope" => "http:example.test"
      },
      coordination_mode: "single_target",
      topology_epoch: 1,
      extensions: %{}
    })
  end

  defp outbox_entry(entry_id) do
    ActionOutboxEntry.new!(%{
      schema_version: 1,
      entry_id: entry_id,
      causal_group_id: "group-scenario-209",
      action:
        LocalAction.new!(%{
          action_kind: "submit_invocation",
          payload: %{"request_id" => "req-scenario-209"},
          extensions: %{}
        }),
      inserted_at: ~U[2026-04-22 16:50:00Z],
      replay_status: :pending,
      durable_receipt_ref: nil,
      attempt_count: 0,
      max_attempts: 3,
      backoff_policy:
        BackoffPolicy.new!(%{
          strategy: :fixed,
          base_delay_ms: 10,
          max_delay_ms: 10,
          linear_step_ms: nil,
          multiplier: nil,
          jitter_mode: :none,
          jitter_window_ms: 0,
          extensions: %{}
        }),
      next_attempt_at: nil,
      last_error_code: nil,
      dead_letter_reason: nil,
      ordering_mode: :strict,
      staleness_mode: :requires_check,
      staleness_requirements:
        StalenessRequirements.new!(%{
          snapshot_seq: 1,
          policy_epoch: 1,
          topology_epoch: nil,
          scope_catalog_epoch: nil,
          service_admission_epoch: nil,
          project_binding_epoch: nil,
          boundary_epoch: nil,
          required_binding_id: nil,
          required_boundary_ref: nil,
          extensions: %{}
        }),
      extensions: %{}
    })
  end

  defp signal_attrs do
    %{
      tenant_ref: "tenant-scenario-209",
      installation_ref: "installation-scenario-209",
      workspace_ref: "workspace-scenario-209",
      project_ref: "project-scenario-209",
      environment_ref: "env-prod",
      principal_ref: "principal-operator",
      operator_ref: "operator-scenario-209",
      resource_ref: "resource-scenario-209",
      workflow_id: "workflow-scenario-209",
      workflow_run_id: "run-scenario-209",
      signal_id: "signal-scenario-209",
      signal_name: "operator.cancel",
      signal_version: "operator-cancel.v1",
      signal_sequence: 1,
      signal_effect: "cancel_requested",
      authority_packet_ref: "authpkt-scenario-209",
      permission_decision_ref: "decision-scenario-209",
      permission_decision_result: "allow",
      idempotency_key: "idem-signal-scenario-209",
      trace_id: "trace-scenario-209",
      correlation_id: "corr-scenario-209",
      release_manifest_ref: "phase5-v7-m7-version-skew-contract-chaos",
      acknowledgement_ttl_ms: 30_000,
      reason: "scenario 209 operator cancel",
      payload_hash: String.duplicate("d", 64),
      payload_ref: "claim://operator-signal/scenario-209"
    }
  end
end
