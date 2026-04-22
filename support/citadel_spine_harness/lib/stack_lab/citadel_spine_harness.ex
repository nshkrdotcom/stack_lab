defmodule StackLab.CitadelSpineHarness do
  @moduledoc """
  Harness-owned configuration and repo resolution for assembled Citadel plus
  Jido Integration proofs.
  """

  alias StackLab.CitadelSpineHarness.{
    AITraceClaimCheckTraceContinuity,
    AppKitOperationalSurface,
    ExtensionAuthoring,
    GovernedRun,
    InstallationRuntimeLease,
    LowerFacts,
    MemoryBindingsThroughExistingSeams,
    MezzanineRestartRecovery,
    MultiNode,
    MultiWriterStateAudit,
    OuterBrainDurability,
    PacketReconciliation,
    Phase5AiNativeMinimalSeams,
    Phase5ArtifactReferenceBoundary,
    Phase5BeamHotPathLoad,
    Phase5LineageContextMissing,
    Phase5SessionLeaseMapEviction,
    Phase5VersionSkewMalformedPacket,
    PrelimEvidenceReport,
    PrelimServiceMode,
    PressureFailover,
    RestartAuthority,
    SameNode,
    SemanticHost,
    Stage12LoadReadiness,
    Stage9OrchestrationRecovery,
    TemporalPostgresProjectionDrift,
    TypedHost
  }

  alias StackLab.LabCore

  @stack_lab_root Path.expand("../../../..", __DIR__)
  @repo_parent Path.expand("..", @stack_lab_root)
  @docs_root Path.expand(
               "../j/jido_brainstorm/nshkrdotcom/docs/20260416/ecosystem_buildout_phase2",
               @repo_parent
             )
  @phase3_docs_root Path.expand(
                      "../j/jido_brainstorm/nshkrdotcom/docs/20260418/ecosystem_buildout_phase3",
                      @repo_parent
                    )

  @type repo_roots :: %{
          required(:stack_lab) => String.t(),
          required(:citadel) => String.t(),
          required(:jido_integration) => String.t(),
          required(:jido_hive) => String.t(),
          required(:mezzanine) => String.t(),
          required(:outer_brain) => String.t(),
          required(:app_kit) => String.t(),
          required(:extravaganza) => String.t(),
          required(:execution_plane) => String.t(),
          required(:docs) => String.t(),
          required(:phase3_docs) => String.t()
        }

  @spec repo_roots() :: repo_roots()
  def repo_roots do
    %{
      stack_lab: @stack_lab_root,
      citadel: Path.expand("../citadel", @stack_lab_root),
      jido_integration: Path.expand("../jido_integration", @stack_lab_root),
      jido_hive: Path.expand("../jido_hive", @stack_lab_root),
      mezzanine: Path.expand("../mezzanine", @stack_lab_root),
      outer_brain: Path.expand("../outer_brain", @stack_lab_root),
      app_kit: Path.expand("../app_kit", @stack_lab_root),
      extravaganza: Path.expand("../extravaganza", @stack_lab_root),
      execution_plane: Path.expand("../execution_plane", @stack_lab_root),
      docs: @docs_root,
      phase3_docs: @phase3_docs_root
    }
  end

  @spec same_node_scenario() :: map()
  def same_node_scenario do
    %{
      name: :single_node_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        acceptance: %{kind: :acceptance},
        duplicate: %{kind: :duplicate},
        scope_rejection: %{kind: :scope_rejection}
      }
    }
  end

  @spec exercise_same_node(:acceptance | :duplicate | :scope_rejection) ::
          {:ok, map()} | {:error, term()}
  def exercise_same_node(case_name)
      when case_name in [:acceptance, :duplicate, :scope_rejection] do
    SameNode.run_case(case_name)
  end

  @spec lower_facts_scenario() :: map()
  def lower_facts_scenario do
    %{
      name: :lower_facts_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        generic_readback: %{kind: :generic_readback},
        authorized_mezzanine_readback: %{kind: :authorized_mezzanine_readback},
        unauthorized_mezzanine_readback: %{kind: :unauthorized_mezzanine_readback}
      }
    }
  end

  @spec exercise_lower_facts(
          :generic_readback
          | :authorized_mezzanine_readback
          | :unauthorized_mezzanine_readback
        ) :: {:ok, map()} | {:error, term()}
  def exercise_lower_facts(case_name)
      when case_name in [
             :generic_readback,
             :authorized_mezzanine_readback,
             :unauthorized_mezzanine_readback
           ] do
    LowerFacts.run_case(case_name)
  end

  @spec outer_brain_durability_scenario() :: map()
  def outer_brain_durability_scenario do
    %{
      name: :outer_brain_restart_durability,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        pending_recovery_after_restart: %{kind: :pending_recovery_after_restart},
        final_reply_after_restart: %{kind: :final_reply_after_restart},
        semantic_failure_carrier_after_restart: %{
          kind: :semantic_failure_carrier_after_restart
        },
        duplicate_publication_suppressed_after_restart: %{
          kind: :duplicate_publication_suppressed_after_restart
        }
      }
    }
  end

  @spec exercise_outer_brain_durability(
          :pending_recovery_after_restart
          | :final_reply_after_restart
          | :semantic_failure_carrier_after_restart
          | :duplicate_publication_suppressed_after_restart
        ) :: {:ok, map()} | {:error, term()}
  def exercise_outer_brain_durability(case_name)
      when case_name in [
             :pending_recovery_after_restart,
             :final_reply_after_restart,
             :semantic_failure_carrier_after_restart,
             :duplicate_publication_suppressed_after_restart
           ] do
    OuterBrainDurability.run_case(case_name)
  end

  @spec mezzanine_restart_recovery_scenario() :: map()
  def mezzanine_restart_recovery_scenario do
    %{
      name: :mezzanine_restart_recovery,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        temporal_replay_after_restart: %{kind: :temporal_replay_after_restart}
      }
    }
  end

  @spec exercise_mezzanine_restart_recovery(:temporal_replay_after_restart) ::
          {:ok, map()} | {:error, term()}
  def exercise_mezzanine_restart_recovery(:temporal_replay_after_restart) do
    MezzanineRestartRecovery.run_case(:temporal_replay_after_restart)
  end

  @spec installation_runtime_lease_scenario() :: map()
  def installation_runtime_lease_scenario do
    %{
      name: :installation_runtime_lease,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        two_owner_fencing: %{kind: :two_owner_fencing}
      }
    }
  end

  @spec exercise_installation_runtime_lease(:two_owner_fencing) ::
          {:ok, map()} | {:error, term()}
  def exercise_installation_runtime_lease(:two_owner_fencing) do
    InstallationRuntimeLease.run_case(:two_owner_fencing)
  end

  @spec extension_authoring_scenario() :: map()
  def extension_authoring_scenario do
    %{
      name: :extension_authoring_activation,
      compose: LabCore.compose_file(:single),
      runbook: "pack_activation_failure.md",
      repo_roots: repo_roots(),
      cases: %{
        activation_failure_matrix: %{kind: :activation_failure_matrix, scenario: 34}
      }
    }
  end

  @spec exercise_extension_authoring(:activation_failure_matrix) ::
          {:ok, map()} | {:error, term()}
  def exercise_extension_authoring(:activation_failure_matrix) do
    ExtensionAuthoring.run_case(:activation_failure_matrix)
  end

  @spec stage9_orchestration_recovery_scenario() :: map()
  def stage9_orchestration_recovery_scenario do
    %{
      name: :stage9_orchestration_recovery,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        operator_pause_during_active_execution: %{
          kind: :operator_pause_during_active_execution,
          scenario: 9
        },
        operator_cancel_during_active_execution: %{
          kind: :operator_cancel_during_active_execution,
          scenario: 16
        },
        decision_sla_expiry: %{kind: :decision_sla_expiry, scenario: 17},
        parallel_join_closure: %{kind: :parallel_join_closure, scenario: 23},
        restart_during_dispatch_ambiguity: %{
          kind: :restart_during_dispatch_ambiguity,
          scenario: 18
        },
        lower_gateway_outage_recovery: %{kind: :lower_gateway_outage_recovery, scenario: 26},
        startup_reconciliation_deduplication: %{
          kind: :startup_reconciliation_deduplication,
          scenario: 27
        }
      }
    }
  end

  @spec exercise_stage9_orchestration_recovery(
          :operator_pause_during_active_execution
          | :operator_cancel_during_active_execution
          | :decision_sla_expiry
          | :parallel_join_closure
          | :restart_during_dispatch_ambiguity
          | :lower_gateway_outage_recovery
          | :startup_reconciliation_deduplication
        ) :: {:ok, map()} | {:error, term()}
  def exercise_stage9_orchestration_recovery(case_name)
      when case_name in [
             :operator_pause_during_active_execution,
             :operator_cancel_during_active_execution,
             :decision_sla_expiry,
             :parallel_join_closure,
             :restart_during_dispatch_ambiguity,
             :lower_gateway_outage_recovery,
             :startup_reconciliation_deduplication
           ] do
    Stage9OrchestrationRecovery.run_case(case_name)
  end

  @spec temporal_postgres_projection_drift_scenario() :: map()
  def temporal_postgres_projection_drift_scenario do
    %{
      name: :temporal_postgres_projection_drift,
      compose: LabCore.compose_file(:single),
      runbook: "temporal_postgres_projection_drift.md",
      repo_roots: repo_roots(),
      cases: %{
        temporal_postgres_projection_drift: %{
          kind: :temporal_postgres_projection_drift,
          scenario: 201
        }
      }
    }
  end

  @spec exercise_temporal_postgres_projection_drift(:temporal_postgres_projection_drift) ::
          {:ok, map()} | {:error, term()}
  def exercise_temporal_postgres_projection_drift(:temporal_postgres_projection_drift) do
    TemporalPostgresProjectionDrift.run_case(:temporal_postgres_projection_drift)
  end

  @spec prelim_service_mode_scenario() :: map()
  def prelim_service_mode_scenario do
    %{
      name: :phase5prelim_service_mode_contract_join,
      compose: LabCore.compose_file(:single),
      runbook: "phase5prelim_service_mode_contract_join.md",
      repo_roots: repo_roots(),
      cases: %{
        m3_contract_join: %{
          kind: :m3_contract_join,
          phase: "5PRELIM",
          milestone: "M3"
        },
        m5_service_profile_bootstrap: %{
          kind: :m5_service_profile_bootstrap,
          phase: "5PRELIM",
          milestone: "M5"
        },
        m5_governed_smoke: %{
          kind: :m5_governed_smoke,
          phase: "5PRELIM",
          milestone: "M5"
        },
        m5_pressure_and_negatives: %{
          kind: :m5_pressure_and_negatives,
          phase: "5PRELIM",
          milestone: "M5"
        },
        m6_evidence_report: %{
          kind: :m6_evidence_report,
          phase: "5PRELIM",
          milestone: "M6"
        }
      }
    }
  end

  @spec exercise_prelim_service_mode(
          :m3_contract_join
          | :m5_service_profile_bootstrap
          | :m5_governed_smoke
          | :m5_pressure_and_negatives
          | :m6_evidence_report,
          keyword()
        ) ::
          {:ok, map()} | {:error, term()}
  def exercise_prelim_service_mode(case_name, opts \\ [])

  def exercise_prelim_service_mode(:m3_contract_join, opts) when is_list(opts) do
    PrelimServiceMode.run_case(:m3_contract_join, opts)
  end

  def exercise_prelim_service_mode(:m5_service_profile_bootstrap, opts) when is_list(opts) do
    PrelimServiceMode.run_case(:m5_service_profile_bootstrap, opts)
  end

  def exercise_prelim_service_mode(:m5_governed_smoke, opts) when is_list(opts) do
    PrelimServiceMode.run_case(:m5_governed_smoke, opts)
  end

  def exercise_prelim_service_mode(:m5_pressure_and_negatives, opts) when is_list(opts) do
    PrelimServiceMode.run_case(:m5_pressure_and_negatives, opts)
  end

  def exercise_prelim_service_mode(:m6_evidence_report, opts) when is_list(opts) do
    PrelimEvidenceReport.run(opts)
  end

  @spec multi_writer_state_audit_scenario() :: map()
  def multi_writer_state_audit_scenario do
    %{
      name: :multi_writer_state_audit,
      compose: LabCore.compose_file(:single),
      runbook: "multi_writer_state_audit.md",
      repo_roots: repo_roots(),
      cases: %{
        multi_writer_state_audit: %{
          kind: :multi_writer_state_audit,
          scenario: "203B"
        }
      }
    }
  end

  @spec exercise_multi_writer_state_audit(:multi_writer_state_audit) ::
          {:ok, map()} | {:error, term()}
  def exercise_multi_writer_state_audit(:multi_writer_state_audit) do
    MultiWriterStateAudit.run_case(:multi_writer_state_audit)
  end

  @spec aitrace_claim_check_trace_continuity_scenario() :: map()
  def aitrace_claim_check_trace_continuity_scenario do
    %{
      name: :aitrace_claim_check_trace_continuity,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        claim_check_trace_continuity: %{
          kind: :claim_check_trace_continuity,
          scenario: 25
        },
        claim_check_degradation: %{
          kind: :claim_check_degradation
        }
      }
    }
  end

  @spec exercise_aitrace_claim_check_trace_continuity(
          :claim_check_trace_continuity
          | :claim_check_degradation
        ) ::
          {:ok, map()} | {:error, term()}
  def exercise_aitrace_claim_check_trace_continuity(case_name)
      when case_name in [:claim_check_trace_continuity, :claim_check_degradation] do
    AITraceClaimCheckTraceContinuity.run_case(case_name)
  end

  @spec observability_trace_join_continuity_scenario() :: map()
  def observability_trace_join_continuity_scenario do
    %{
      name: :observability_trace_join_continuity,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        trace_join_continuity: %{
          kind: :trace_join_continuity,
          scenario: 19
        }
      }
    }
  end

  @spec exercise_observability_trace_join_continuity(:trace_join_continuity) ::
          {:ok, map()} | {:error, term()}
  def exercise_observability_trace_join_continuity(:trace_join_continuity) do
    AppKitOperationalSurface.run_case(:observability_trace_join_continuity)
  end

  @spec app_kit_operational_surface_scenario() :: map()
  def app_kit_operational_surface_scenario do
    %{
      name: :app_kit_operational_surface,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        install_ingest_review_trace: %{kind: :install_ingest_review_trace},
        governed_agent_workload_contract: %{kind: :governed_agent_workload_contract},
        lower_backed_command_trace: %{kind: :lower_backed_command_trace},
        lower_backed_command_terminal_rejection: %{
          kind: :lower_backed_command_terminal_rejection
        },
        lower_backed_command_semantic_failure: %{
          kind: :lower_backed_command_semantic_failure
        },
        leased_direct_read_and_stream_invalidation: %{
          kind: :leased_direct_read_and_stream_invalidation,
          scenario: 24
        },
        unauthorized_lower_trace_read: %{kind: :unauthorized_lower_trace_read}
      }
    }
  end

  @spec exercise_app_kit_operational_surface(
          :install_ingest_review_trace
          | :governed_agent_workload_contract
          | :lower_backed_command_trace
          | :lower_backed_command_terminal_rejection
          | :lower_backed_command_semantic_failure
          | :leased_direct_read_and_stream_invalidation
          | :unauthorized_lower_trace_read
        ) ::
          {:ok, map()} | {:error, term()}
  def exercise_app_kit_operational_surface(case_name)
      when case_name in [
             :install_ingest_review_trace,
             :governed_agent_workload_contract,
             :lower_backed_command_trace,
             :lower_backed_command_terminal_rejection,
             :lower_backed_command_semantic_failure,
             :leased_direct_read_and_stream_invalidation,
             :unauthorized_lower_trace_read
           ] do
    AppKitOperationalSurface.run_case(case_name)
  end

  @spec stage12_load_readiness_scenario() :: map()
  def stage12_load_readiness_scenario do
    %{
      name: :stage12_load_readiness,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        same_subject_callback_storm: %{kind: :same_subject_callback_storm},
        shared_repo_pressure_posture: %{kind: :shared_repo_pressure_posture},
        claim_check_degradation_and_compactness: %{
          kind: :claim_check_degradation_and_compactness
        }
      }
    }
  end

  @spec exercise_stage12_load_readiness(
          :same_subject_callback_storm
          | :shared_repo_pressure_posture
          | :claim_check_degradation_and_compactness
        ) :: {:ok, map()}
  def exercise_stage12_load_readiness(case_name)
      when case_name in [
             :same_subject_callback_storm,
             :shared_repo_pressure_posture,
             :claim_check_degradation_and_compactness
           ] do
    Stage12LoadReadiness.run_case(case_name)
  end

  @spec phase5_beam_hot_path_load_scenario() :: map()
  def phase5_beam_hot_path_load_scenario do
    %{
      name: :phase5_beam_hot_path_load,
      compose: LabCore.compose_file(:single),
      runbook: "beam_hot_path_load.md",
      repo_roots: repo_roots(),
      cases: %{
        snapshot_publish_read_sustained: %{
          kind: :snapshot_publish_read_sustained,
          scenario: 202,
          minimum_duration_ms: 15_000
        },
        snapshot_staleness_classes: %{
          kind: :snapshot_staleness_classes,
          scenario: 202
        },
        partitioned_signal_ingress_sustained: %{
          kind: :partitioned_signal_ingress_sustained,
          scenario: 203,
          minimum_duration_ms: 30_000
        },
        partition_fifo_ordering_scope: %{
          kind: :partition_fifo_ordering_scope,
          scenario: 203
        }
      }
    }
  end

  @spec exercise_phase5_beam_hot_path_load(
          :snapshot_publish_read_sustained
          | :snapshot_staleness_classes
          | :partitioned_signal_ingress_sustained
          | :partition_fifo_ordering_scope
        ) :: {:ok, map()}
  def exercise_phase5_beam_hot_path_load(case_name)
      when case_name in [
             :snapshot_publish_read_sustained,
             :snapshot_staleness_classes,
             :partitioned_signal_ingress_sustained,
             :partition_fifo_ordering_scope
           ] do
    Phase5BeamHotPathLoad.run_case(case_name)
  end

  @spec phase5_artifact_reference_boundary_scenario() :: map()
  def phase5_artifact_reference_boundary_scenario do
    %{
      name: :phase5_artifact_reference_boundary,
      compose: LabCore.compose_file(:single),
      runbook: "artifact_reference_payload_bypass.md",
      repo_roots: repo_roots(),
      cases: %{
        payload_boundary_fault_matrix: %{
          kind: :payload_boundary_fault_matrix,
          scenario: 204
        }
      }
    }
  end

  @spec exercise_phase5_artifact_reference_boundary(:payload_boundary_fault_matrix) ::
          {:ok, map()}
  def exercise_phase5_artifact_reference_boundary(:payload_boundary_fault_matrix) do
    Phase5ArtifactReferenceBoundary.run_case(:payload_boundary_fault_matrix)
  end

  @spec phase5_lineage_context_missing_scenario() :: map()
  def phase5_lineage_context_missing_scenario do
    %{
      name: :phase5_lineage_context_missing,
      compose: LabCore.compose_file(:single),
      runbook: "lineage_context_missing.md",
      repo_roots: repo_roots(),
      cases: %{
        lineage_context_missing: %{
          kind: :lineage_context_missing,
          scenario: 208
        }
      }
    }
  end

  @spec exercise_phase5_lineage_context_missing(:lineage_context_missing) ::
          {:ok, map()}
  def exercise_phase5_lineage_context_missing(:lineage_context_missing) do
    Phase5LineageContextMissing.run_case(:lineage_context_missing)
  end

  @spec phase5_version_skew_malformed_packet_scenario() :: map()
  def phase5_version_skew_malformed_packet_scenario do
    %{
      name: :phase5_version_skew_malformed_packet,
      compose: LabCore.compose_file(:single),
      runbook: "version_skew_malformed_packet.md",
      repo_roots: repo_roots(),
      cases: %{
        contract_chaos: %{
          kind: :contract_chaos,
          scenario: 209
        }
      }
    }
  end

  @spec exercise_phase5_version_skew_malformed_packet(:contract_chaos) ::
          {:ok, map()}
  def exercise_phase5_version_skew_malformed_packet(:contract_chaos) do
    Phase5VersionSkewMalformedPacket.run_case(:contract_chaos)
  end

  @spec phase5_context_budget_exceeded_scenario() :: map()
  def phase5_context_budget_exceeded_scenario do
    %{
      name: :phase5_context_budget_exceeded,
      compose: LabCore.compose_file(:single),
      runbook: "context_budget_exceeded.md",
      repo_roots: repo_roots(),
      cases: %{
        context_budget_exceeded: %{
          kind: :context_budget_exceeded,
          scenario: 210
        }
      }
    }
  end

  @spec exercise_phase5_context_budget_exceeded(:context_budget_exceeded) :: {:ok, map()}
  def exercise_phase5_context_budget_exceeded(:context_budget_exceeded) do
    Phase5AiNativeMinimalSeams.run_case(:context_budget_exceeded)
  end

  @spec phase5_cost_attribution_missing_scenario() :: map()
  def phase5_cost_attribution_missing_scenario do
    %{
      name: :phase5_cost_attribution_missing,
      compose: LabCore.compose_file(:single),
      runbook: "cost_attribution_missing.md",
      repo_roots: repo_roots(),
      cases: %{
        cost_attribution_missing: %{
          kind: :cost_attribution_missing,
          scenario: "210A"
        }
      }
    }
  end

  @spec exercise_phase5_cost_attribution_missing(:cost_attribution_missing) :: {:ok, map()}
  def exercise_phase5_cost_attribution_missing(:cost_attribution_missing) do
    Phase5AiNativeMinimalSeams.run_case(:cost_attribution_missing)
  end

  @spec phase5_semantic_failure_evidence_gap_scenario() :: map()
  def phase5_semantic_failure_evidence_gap_scenario do
    %{
      name: :phase5_semantic_failure_evidence_gap,
      compose: LabCore.compose_file(:single),
      runbook: "semantic_failure_evidence_gap.md",
      repo_roots: repo_roots(),
      cases: %{
        semantic_failure_evidence_gap: %{
          kind: :semantic_failure_evidence_gap,
          scenario: 211
        }
      }
    }
  end

  @spec exercise_phase5_semantic_failure_evidence_gap(:semantic_failure_evidence_gap) ::
          {:ok, map()}
  def exercise_phase5_semantic_failure_evidence_gap(:semantic_failure_evidence_gap) do
    Phase5AiNativeMinimalSeams.run_case(:semantic_failure_evidence_gap)
  end

  @spec phase5_session_lease_map_eviction_scenario() :: map()
  def phase5_session_lease_map_eviction_scenario do
    %{
      name: :phase5_session_lease_map_eviction,
      compose: LabCore.compose_file(:single),
      runbook: "session_lease_map_eviction.md",
      repo_roots: repo_roots(),
      cases: %{
        expiry_first_segmented_lru: %{
          kind: :expiry_first_segmented_lru,
          scenario: "203A"
        }
      }
    }
  end

  @spec exercise_phase5_session_lease_map_eviction(:expiry_first_segmented_lru) ::
          {:ok, map()}
  def exercise_phase5_session_lease_map_eviction(:expiry_first_segmented_lru) do
    Phase5SessionLeaseMapEviction.run_case(:expiry_first_segmented_lru)
  end

  @spec memory_bindings_through_existing_seams_scenario() :: map()
  def memory_bindings_through_existing_seams_scenario do
    %{
      name: :memory_bindings_through_existing_seams,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        memory_bindings_through_existing_seams: %{
          kind: :memory_bindings_through_existing_seams,
          scenario: 28
        }
      }
    }
  end

  @spec exercise_memory_bindings_through_existing_seams(:memory_bindings_through_existing_seams) ::
          {:ok, map()}
  def exercise_memory_bindings_through_existing_seams(:memory_bindings_through_existing_seams) do
    MemoryBindingsThroughExistingSeams.run_case(:memory_bindings_through_existing_seams)
  end

  @spec reviewable_connector_automation_console_scenario() :: map()
  def reviewable_connector_automation_console_scenario do
    %{
      name: :reviewable_connector_automation_console,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        reviewable_connector_automation_console: %{
          kind: :reviewable_connector_automation_console,
          scenario: 42,
          whitepaper_use_case: :"18.2_reviewable_connector_automation"
        }
      }
    }
  end

  @spec exercise_reviewable_connector_automation_console(:reviewable_connector_automation_console) ::
          {:ok, map()} | {:error, term()}
  def exercise_reviewable_connector_automation_console(:reviewable_connector_automation_console) do
    AppKitOperationalSurface.run_case(:reviewable_connector_automation_console)
  end

  @spec governed_run_scenario() :: map()
  def governed_run_scenario do
    %{
      name: :governed_run_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        expense_capture_acceptance: %{kind: :expense_capture_acceptance},
        multi_pack_installation_routing: %{kind: :multi_pack_installation_routing}
      }
    }
  end

  @spec exercise_governed_run(:expense_capture_acceptance | :multi_pack_installation_routing) ::
          {:ok, map()} | {:error, term()}
  def exercise_governed_run(case_name)
      when case_name in [:expense_capture_acceptance, :multi_pack_installation_routing] do
    GovernedRun.run_case(case_name)
  end

  @spec packet_reconciliation_scenario() :: map()
  def packet_reconciliation_scenario do
    %{
      name: :packet_reconciliation_boundaries,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        packet_ownership_freeze: %{kind: :packet_ownership_freeze},
        stack_ir_binding_map_freeze: %{kind: :stack_ir_binding_map_freeze},
        control_path_boundaries: %{kind: :control_path_boundaries},
        stale_reference_absence: %{kind: :stale_reference_absence},
        substrate_origin_no_host_session_path: %{kind: :substrate_origin_no_host_session_path},
        direct_execution_plane_bypass_absence: %{
          kind: :direct_execution_plane_bypass_absence
        },
        phase3_runbook_drift: %{kind: :phase3_runbook_drift, scenario: 35}
      }
    }
  end

  @spec exercise_packet_reconciliation(
          :packet_ownership_freeze
          | :stack_ir_binding_map_freeze
          | :control_path_boundaries
          | :stale_reference_absence
          | :substrate_origin_no_host_session_path
          | :direct_execution_plane_bypass_absence
          | :phase3_runbook_drift
        ) :: {:ok, map()} | {:error, term()}
  def exercise_packet_reconciliation(case_name)
      when case_name in [
             :packet_ownership_freeze,
             :stack_ir_binding_map_freeze,
             :control_path_boundaries,
             :stale_reference_absence,
             :substrate_origin_no_host_session_path,
             :direct_execution_plane_bypass_absence,
             :phase3_runbook_drift
           ] do
    PacketReconciliation.run_case(case_name)
  end

  @spec multi_node_scenario() :: map()
  def multi_node_scenario do
    %{
      name: :multi_node_roundtrip,
      compose: LabCore.compose_file(:multi),
      runbook: LabCore.runbook(:up_multi),
      repo_roots: repo_roots(),
      cases: %{
        acceptance: %{kind: :acceptance},
        scope_rejection: %{kind: :scope_rejection}
      }
    }
  end

  @spec exercise_multi_node(:acceptance | :scope_rejection) :: {:ok, map()} | {:error, term()}
  def exercise_multi_node(case_name) when case_name in [:acceptance, :scope_rejection] do
    MultiNode.run_case(case_name)
  end

  @spec restart_authority_scenario() :: map()
  def restart_authority_scenario do
    %{
      name: :restart_authority_drill,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:faults),
      repo_roots: repo_roots(),
      cases: %{
        delayed_acceptance: %{kind: :delayed_acceptance},
        node_restart_recovery: %{kind: :node_restart_recovery}
      }
    }
  end

  @spec exercise_restart_authority(:delayed_acceptance | :node_restart_recovery) ::
          {:ok, map()} | {:error, term()}
  def exercise_restart_authority(case_name)
      when case_name in [:delayed_acceptance, :node_restart_recovery] do
    RestartAuthority.run_case(case_name)
  end

  @spec pressure_failover_scenario() :: map()
  def pressure_failover_scenario do
    %{
      name: :pressure_failover_drill,
      compose: LabCore.compose_file(:multi),
      runbook: LabCore.runbook(:faults),
      repo_roots: repo_roots(),
      cases: %{
        transport_interruption: %{kind: :transport_interruption},
        duplicate_delivery: %{kind: :duplicate_delivery}
      }
    }
  end

  @spec exercise_pressure_failover(:transport_interruption | :duplicate_delivery) ::
          {:ok, map()} | {:error, term()}
  def exercise_pressure_failover(case_name)
      when case_name in [:transport_interruption, :duplicate_delivery] do
    PressureFailover.run_case(case_name)
  end

  @spec typed_host_scenario() :: map()
  def typed_host_scenario do
    %{
      name: :typed_host_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        command_acceptance: %{kind: :command_acceptance},
        command_duplicate: %{kind: :command_duplicate},
        command_scope_rejection: %{kind: :command_scope_rejection}
      }
    }
  end

  @spec exercise_typed_host(:command_acceptance | :command_duplicate | :command_scope_rejection) ::
          {:ok, map()} | {:error, term()}
  def exercise_typed_host(case_name)
      when case_name in [:command_acceptance, :command_duplicate, :command_scope_rejection] do
    TypedHost.run_case(case_name)
  end

  @spec semantic_host_scenario() :: map()
  def semantic_host_scenario do
    %{
      name: :semantic_host_roundtrip,
      compose: LabCore.compose_file(:single),
      runbook: LabCore.runbook(:up_single),
      repo_roots: repo_roots(),
      cases: %{
        turn_acceptance: %{kind: :turn_acceptance},
        turn_replay: %{kind: :turn_replay},
        turn_scope_rejection: %{kind: :turn_scope_rejection}
      }
    }
  end

  @spec exercise_semantic_host(:turn_acceptance | :turn_replay | :turn_scope_rejection) ::
          {:ok, map()} | {:error, term()}
  def exercise_semantic_host(case_name)
      when case_name in [:turn_acceptance, :turn_replay, :turn_scope_rejection] do
    SemanticHost.run_case(case_name)
  end
end
