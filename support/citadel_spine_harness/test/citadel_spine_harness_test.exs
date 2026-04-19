defmodule StackLab.CitadelSpineHarnessTest do
  use ExUnit.Case, async: true

  alias StackLab.CitadelSpineHarness
  alias StackLab.CitadelSpineHarness.MixProject
  alias StackLab.CitadelSpineHarness.RemoteSpine
  alias StackLab.CitadelSpineHarness.RemoteSupport

  test "resolves sibling repo roots for harness-owned assembly" do
    roots = CitadelSpineHarness.repo_roots()

    assert File.dir?(roots.stack_lab)
    assert File.dir?(roots.citadel)
    assert File.dir?(roots.jido_integration)
    assert File.dir?(roots.mezzanine)
    assert File.dir?(roots.outer_brain)
    assert File.dir?(roots.app_kit)
    assert File.dir?(roots.extravaganza)
    assert File.dir?(roots.execution_plane)
    assert File.dir?(roots.docs)
  end

  test "describes the same-node proof cases as acceptance, rejection, and duplicate" do
    scenario = CitadelSpineHarness.same_node_scenario()

    assert scenario.name == :single_node_roundtrip

    assert scenario.cases |> Map.keys() |> Enum.sort() == [
             :acceptance,
             :duplicate,
             :scope_rejection
           ]

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the lower-facts proof case as a dedicated Stage-1 scenario" do
    scenario = CitadelSpineHarness.lower_facts_scenario()

    assert scenario.name == :lower_facts_roundtrip

    assert scenario.cases == %{
             generic_readback: %{kind: :generic_readback},
             authorized_mezzanine_readback: %{kind: :authorized_mezzanine_readback},
             unauthorized_mezzanine_readback: %{kind: :unauthorized_mezzanine_readback}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the typed host proof case above the lower seam" do
    scenario = CitadelSpineHarness.typed_host_scenario()

    assert scenario.name == :typed_host_roundtrip

    assert scenario.cases == %{
             command_acceptance: %{kind: :command_acceptance},
             command_duplicate: %{kind: :command_duplicate},
             command_scope_rejection: %{kind: :command_scope_rejection}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the semantic host proof case above the typed boundary" do
    scenario = CitadelSpineHarness.semantic_host_scenario()

    assert scenario.name == :semantic_host_roundtrip

    assert scenario.cases == %{
             turn_acceptance: %{kind: :turn_acceptance},
             turn_replay: %{kind: :turn_replay},
             turn_scope_rejection: %{kind: :turn_scope_rejection}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the outer-brain durability proof case as a Stage-1 durable restart scenario" do
    scenario = CitadelSpineHarness.outer_brain_durability_scenario()

    assert scenario.name == :outer_brain_restart_durability

    assert scenario.cases == %{
             pending_recovery_after_restart: %{kind: :pending_recovery_after_restart},
             final_reply_after_restart: %{kind: :final_reply_after_restart},
             semantic_failure_carrier_after_restart: %{
               kind: :semantic_failure_carrier_after_restart
             },
             duplicate_publication_suppressed_after_restart: %{
               kind: :duplicate_publication_suppressed_after_restart
             }
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "outer-brain durability scenario proves semantic failure carriers survive restart" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_outer_brain_durability(
               :semantic_failure_carrier_after_restart
             )

    assert result.case == :semantic_failure_carrier_after_restart
    assert result.durable.semantic_failure_kind == :semantic_insufficient_context
    assert result.durable.semantic_failure_retry_class == :clarification_required
    assert result.after_restart.semantic_failure_kinds == [:semantic_insufficient_context]
    assert result.after_restart.semantic_failure_retry_classes == [:clarification_required]
    assert result.after_restart.semantic_failure_trace_ids == ["trace-semantic-failure"]
  end

  test "outer-brain durability scenario suppresses duplicate reply publication after restart" do
    assert {:ok, result} =
             CitadelSpineHarness.exercise_outer_brain_durability(
               :duplicate_publication_suppressed_after_restart
             )

    assert result.case == :duplicate_publication_suppressed_after_restart
    assert result.durable.initial_publication_id =~ "publication-"
    assert result.durable.replayed_publication_id == result.durable.initial_publication_id
    assert result.after_restart.publication_ids == [result.durable.initial_publication_id]
    assert result.after_restart.publication_bodies == ["Done after replay"]
    assert result.after_restart.next_action == {:noop, :final_reply_published}
  end

  test "describes the mezzanine restart-recovery proof case as a Stage-2 durable substrate scenario" do
    scenario = CitadelSpineHarness.mezzanine_restart_recovery_scenario()

    assert scenario.name == :mezzanine_restart_recovery

    assert scenario.cases == %{
             dispatching_retry_after_restart: %{kind: :dispatching_retry_after_restart}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the installation-runtime lease proof case as a Stage-3 neutral runtime scenario" do
    scenario = CitadelSpineHarness.installation_runtime_lease_scenario()

    assert scenario.name == :installation_runtime_lease

    assert scenario.cases == %{
             two_owner_fencing: %{kind: :two_owner_fencing}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the Stage-9 orchestration recovery proof cases for scenarios 9, 16, 17, 18, 23, 26, and 27" do
    scenario = CitadelSpineHarness.stage9_orchestration_recovery_scenario()

    assert scenario.name == :stage9_orchestration_recovery

    assert scenario.cases == %{
             operator_pause_during_active_execution: %{
               kind: :operator_pause_during_active_execution,
               scenario: 9
             },
             operator_cancel_during_active_execution: %{
               kind: :operator_cancel_during_active_execution,
               scenario: 16
             },
             decision_sla_expiry: %{kind: :decision_sla_expiry, scenario: 17},
             parallel_join_closure: %{
               kind: :parallel_join_closure,
               scenario: 23
             },
             restart_during_dispatch_ambiguity: %{
               kind: :restart_during_dispatch_ambiguity,
               scenario: 18
             },
             lower_gateway_outage_recovery: %{
               kind: :lower_gateway_outage_recovery,
               scenario: 26
             },
             startup_reconciliation_deduplication: %{
               kind: :startup_reconciliation_deduplication,
               scenario: 27
             }
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the app-kit operational-surface proof case including Scenario 24 leased direct read and stream invalidation" do
    scenario = CitadelSpineHarness.app_kit_operational_surface_scenario()

    assert scenario.name == :app_kit_operational_surface

    assert scenario.cases == %{
             install_ingest_review_trace: %{kind: :install_ingest_review_trace},
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

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the Stage 12 load-readiness drill pack as explicit callback, shared-repo, and compactness cases" do
    scenario = CitadelSpineHarness.stage12_load_readiness_scenario()

    assert scenario.name == :stage12_load_readiness

    assert scenario.cases == %{
             same_subject_callback_storm: %{kind: :same_subject_callback_storm},
             shared_repo_pressure_posture: %{kind: :shared_repo_pressure_posture},
             claim_check_degradation_and_compactness: %{
               kind: :claim_check_degradation_and_compactness
             }
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the Scenario 28 memory-binding proof case through the frozen seams" do
    scenario = CitadelSpineHarness.memory_bindings_through_existing_seams_scenario()

    assert scenario.name == :memory_bindings_through_existing_seams

    assert scenario.cases == %{
             memory_bindings_through_existing_seams: %{
               kind: :memory_bindings_through_existing_seams,
               scenario: 28
             }
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the Scenario 42 reviewable connector automation console as a second synthetic product shape" do
    scenario = CitadelSpineHarness.reviewable_connector_automation_console_scenario()

    assert scenario.name == :reviewable_connector_automation_console

    assert scenario.cases == %{
             reviewable_connector_automation_console: %{
               kind: :reviewable_connector_automation_console,
               scenario: 42,
               whitepaper_use_case: :"18.2_reviewable_connector_automation"
             }
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the Scenario 25 AITrace continuity case plus the Stage 12 degradation companion case" do
    scenario = CitadelSpineHarness.aitrace_claim_check_trace_continuity_scenario()

    assert scenario.name == :aitrace_claim_check_trace_continuity

    assert scenario.cases == %{
             claim_check_trace_continuity: %{
               kind: :claim_check_trace_continuity,
               scenario: 25
             },
             claim_check_degradation: %{kind: :claim_check_degradation}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the Scenario 19 observability and trace-join continuity proof case" do
    scenario = CitadelSpineHarness.observability_trace_join_continuity_scenario()

    assert scenario.name == :observability_trace_join_continuity

    assert scenario.cases == %{
             trace_join_continuity: %{
               kind: :trace_join_continuity,
               scenario: 19
             }
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the governed-run proof case as a non-extravaganza Stage-2 scenario" do
    scenario = CitadelSpineHarness.governed_run_scenario()

    assert scenario.name == :governed_run_roundtrip

    assert scenario.cases == %{
             expense_capture_acceptance: %{kind: :expense_capture_acceptance},
             multi_pack_installation_routing: %{kind: :multi_pack_installation_routing}
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "describes the packet-reconciliation proof case as the Stage-7 boundary scenario" do
    scenario = CitadelSpineHarness.packet_reconciliation_scenario()

    assert scenario.name == :packet_reconciliation_boundaries

    assert scenario.cases == %{
             packet_ownership_freeze: %{kind: :packet_ownership_freeze},
             stack_ir_binding_map_freeze: %{kind: :stack_ir_binding_map_freeze},
             control_path_boundaries: %{kind: :control_path_boundaries},
             stale_reference_absence: %{kind: :stale_reference_absence},
             substrate_origin_no_host_session_path: %{
               kind: :substrate_origin_no_host_session_path
             },
             direct_execution_plane_bypass_absence: %{
               kind: :direct_execution_plane_bypass_absence
             },
             phase3_runbook_drift: %{
               kind: :phase3_runbook_drift,
               scenario: 35
             }
           }

    assert File.exists?(scenario.compose)
    assert File.exists?(scenario.runbook)
  end

  test "harness mix project does not declare or reference the deprecated mezzanine ops_model package" do
    deps = MixProject.project()[:deps]

    refute Enum.any?(deps, fn
             {:mezzanine_ops_model, _opts} -> true
             {:mezzanine_ops_model, _requirement, _opts} -> true
             _other -> false
           end)

    harness_root = Path.expand("..", __DIR__)

    harness_root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      refute File.read!(path) =~ "MezzanineOpsModel", "#{path} still references MezzanineOpsModel"
    end)
  end

  test "harness mix project does not declare or reference the deprecated mezzanine ops_audit package" do
    deps = MixProject.project()[:deps]

    refute Enum.any?(deps, fn
             {:mezzanine_ops_audit, _opts} -> true
             {:mezzanine_ops_audit, _requirement, _opts} -> true
             _other -> false
           end)

    harness_root = Path.expand("..", __DIR__)

    harness_root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      refute File.read!(path) =~ "Mezzanine.WorkAudit",
             "#{path} still references Mezzanine.WorkAudit"
    end)
  end

  test "harness mix project does not declare or reference the deprecated mezzanine ops_control package" do
    deps = MixProject.project()[:deps]

    refute Enum.any?(deps, fn
             {:mezzanine_ops_control, _opts} -> true
             {:mezzanine_ops_control, _requirement, _opts} -> true
             _other -> false
           end)

    harness_root = Path.expand("..", __DIR__)

    harness_root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      refute File.read!(path) =~ "Mezzanine.Control",
             "#{path} still references Mezzanine.Control"
    end)
  end

  test "harness mix project does not declare or reference the deprecated mezzanine ops_assurance package" do
    deps = MixProject.project()[:deps]

    refute Enum.any?(deps, fn
             {:mezzanine_ops_assurance, _opts} -> true
             {:mezzanine_ops_assurance, _requirement, _opts} -> true
             _other -> false
           end)

    harness_root = Path.expand("..", __DIR__)

    harness_root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      refute File.read!(path) =~ "Mezzanine.Assurance",
             "#{path} still references Mezzanine.Assurance"
    end)
  end

  test "harness mix project does not declare or reference the deprecated mezzanine ops_domain package directly" do
    deps = MixProject.project()[:deps]

    refute Enum.any?(deps, fn
             {:mezzanine_ops_domain, _opts} -> true
             {:mezzanine_ops_domain, _requirement, _opts} -> true
             _other -> false
           end)

    harness_root = Path.expand("..", __DIR__)

    harness_root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard(match_dot: true)
    |> Enum.each(fn path ->
      contents = File.read!(path)

      refute contents =~ "Mezzanine.OpsDomain.Repo",
             "#{path} still references Mezzanine.OpsDomain.Repo"

      refute Regex.match?(
               ~r/Mezzanine\.(Programs|Work|Runs|Review|Evidence|Control)\b/,
               contents
             ),
             "#{path} still references direct ops_domain namespaces"
    end)
  end

  test "remote spine startup returns only after the remote service is callable" do
    try do
      remote = RemoteSupport.start_remote_spine!(:startup_probe)

      try do
        assert :ok == RemoteSupport.remote_call!(remote.remote_node, RemoteSpine, :ping, [])

        assert nil ==
                 RemoteSupport.remote_call!(remote.remote_node, RemoteSpine, :fetch_rejection, [
                   "missing"
                 ])
      after
        assert :ok == RemoteSupport.stop_remote_spine(remote)
      end
    rescue
      error in RuntimeError ->
        assert Exception.message(error) =~ "unable to start local distributed node"
        assert Exception.message(error) =~ ":nodistribution"
    end
  end
end
