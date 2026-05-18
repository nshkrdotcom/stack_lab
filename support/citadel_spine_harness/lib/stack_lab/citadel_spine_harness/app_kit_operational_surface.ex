defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface do
  @moduledoc false

  alias AppKit.Bridges.MezzanineBridge
  alias AppKit.RunGovernance
  alias Ash
  alias Citadel.InvocationBridge
  alias Citadel.Kernel.TracePublisher
  alias Citadel.TraceEnvelope
  alias Jido.Integration.V2.BrainIngress.StaticScopeResolver
  alias Jido.Integration.V2.ControlPlane.ClaimCheckTelemetry
  alias Jido.Integration.V2.LowerFacts
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.Server, as: StoreLocalServer
  alias Jido.Integration.V2.StoreLocal.SubmissionLedger
  alias Jido.Integration.V2.SubmissionAcceptance
  alias Jido.Integration.V2.TenantScope
  alias StackLab.CitadelSpineHarness.RuntimeProcesses

  alias AppKit.Core.{
    ExecutionRef,
    InstallTemplate,
    OperatorActionRequest,
    PageRequest,
    ReadLease,
    RequestContext,
    RunRequest,
    SurfaceError,
    Telemetry,
    TraceIdentity
  }

  alias AppKit.{
    InstallationSurface,
    OperatorSurface,
    ReviewSurface,
    WorkControl,
    WorkSurface
  }

  alias Mezzanine.AppKitBridge.OperatorQueryService
  alias Mezzanine.AppKitBridge.SemanticFailureRecoveryService

  alias Mezzanine.Archival.Scheduler
  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.Citadel.SubstrateIngress
  alias Mezzanine.ConfigRegistry.Installation
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Decisions.Repo, as: DecisionsRepo
  alias Mezzanine.EvidenceLedger.Repo, as: EvidenceRepo
  alias Mezzanine.Execution.ExecutionRecord
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.Installations
  alias Mezzanine.IntegrationBridge
  alias Mezzanine.Intent.{ReadIntent, RunIntent}
  alias Mezzanine.Leasing
  alias Mezzanine.Leasing.AuthorizationScope
  alias Mezzanine.Objects.Repo, as: ObjectsRepo
  alias Mezzanine.OperatorCommands
  alias Mezzanine.StreamAttachHost
  alias OuterBrain.Contracts.SemanticFailure

  alias Mezzanine.Pack.{
    Compiler,
    DecisionSpec,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    ProjectionSpec,
    SubjectKindSpec
  }

  alias StackLab.CitadelSpineHarness.{
    AITraceClaimCheckTraceContinuity,
    DispatchProbe,
    InProcessInvocationDownstream,
    LowerGatewayStub,
    MezzanineOperationalStack,
    ProfileSlots,
    RoundtripRuntime,
    TransportRuntime
  }

  @scenario_24_disconnect_window_ms 10_000
  @scenario_24_poll_interval_ms 250
  @scenario_24_burst_count 100
  @scenario_24_burst_concurrency 10
  @scenario_24_reconnect_timeout_ms 4_000
  @scenario_19_archive_now ~U[2026-04-16 12:00:00Z]
  @scenario_19_terminal_at ~U[2026-03-01 09:00:00Z]
  @scenario_19_execution_plane_required_keys [
    :tenant_id,
    :trace_id,
    :request_id,
    :decision_id,
    :boundary_session_id,
    :attempt_ref,
    :route_id,
    :idempotency_key
  ]
  @bounded_lookup_atom_keys %{
    "carrier" => :carrier,
    "error" => :error,
    "kind" => :kind,
    "last_dispatch_error_payload" => :last_dispatch_error_payload,
    "request_trace_id" => :request_trace_id,
    "retry_class" => :retry_class
  }

  defmodule LowerFactsStub do
    @moduledoc false

    def operation_supported?(operation),
      do:
        operation in [
          :fetch_submission_receipt,
          :fetch_run,
          :events,
          :attempts,
          :fetch_attempt,
          :fetch_artifact,
          :run_artifacts,
          :resolve_trace
        ]

    def fetch_submission_receipt(%TenantScope{} = scope, submission_key) do
      send(self(), {:lower_fetch_submission_receipt, scope.tenant_id, submission_key})

      {:ok,
       %{
         submission_key: submission_key,
         submission_receipt_ref: "submission://stub/#{submission_key}",
         occurred_at: ~U[2026-04-16 11:09:00Z]
       }}
    end

    def fetch_run(%TenantScope{} = scope, run_id) do
      send(self(), {:lower_fetch_run, scope.tenant_id, run_id})

      {:ok,
       %{
         run_id: run_id,
         status: :running,
         occurred_at: ~U[2026-04-16 11:10:00Z]
       }}
    end

    def events(%TenantScope{} = scope, run_id) do
      send(self(), {:lower_events, scope.tenant_id, run_id})

      [
        %{
          event_id: "lower-event-#{run_id}",
          run_id: run_id,
          event_kind: "attempt.started",
          occurred_at: ~U[2026-04-16 11:11:00Z]
        }
      ]
    end

    def attempts(%TenantScope{} = scope, run_id) do
      send(self(), {:lower_attempts, scope.tenant_id, run_id})

      [
        %{
          attempt_id: "attempt-#{run_id}",
          run_id: run_id,
          status: :running,
          occurred_at: ~U[2026-04-16 11:12:00Z]
        }
      ]
    end

    def fetch_attempt(%TenantScope{} = scope, attempt_id) do
      send(self(), {:lower_fetch_attempt, scope.tenant_id, attempt_id})

      {:ok,
       %{
         attempt_id: attempt_id,
         run_id: "run-#{attempt_id}",
         status: :running,
         occurred_at: ~U[2026-04-16 11:12:00Z]
       }}
    end

    def fetch_artifact(%TenantScope{} = scope, artifact_id) do
      send(self(), {:lower_fetch_artifact, scope.tenant_id, artifact_id})

      {:ok,
       %{
         artifact_id: artifact_id,
         run_id: "run-#{artifact_id}",
         kind: :log,
         occurred_at: ~U[2026-04-16 11:13:00Z]
       }}
    end

    def run_artifacts(%TenantScope{} = scope, run_id) do
      send(self(), {:lower_run_artifacts, scope.tenant_id, run_id})

      [
        %{
          artifact_id: "artifact-#{run_id}",
          run_id: run_id,
          kind: :log,
          occurred_at: ~U[2026-04-16 11:13:00Z]
        }
      ]
    end

    def resolve_trace(%TenantScope{} = scope, trace_id) do
      send(self(), {:lower_resolve_trace, scope.tenant_id, trace_id})

      {:ok,
       %{
         trace_id: trace_id,
         run: %{run_id: "run-#{trace_id}"},
         attempts: [],
         events: [],
         artifacts: []
       }}
    end
  end

  defmodule FailingTracePort do
    @moduledoc false

    def publish_trace(_envelope), do: {:error, :backend_rejected}
    def publish_traces(_envelopes), do: {:error, :backend_rejected}
  end

  @spec run_case(
          :install_ingest_review_trace
          | :governed_agent_workload_contract
          | :lower_backed_command_trace
          | :lower_backed_command_terminal_rejection
          | :lower_backed_command_semantic_failure
          | :reviewable_connector_automation_console
          | :leased_direct_read_and_stream_invalidation
          | :observability_trace_join_continuity
          | :unauthorized_lower_trace_read
        ) :: {:ok, map()}
  def run_case(:install_ingest_review_trace) do
    MezzanineOperationalStack.with_store(:app_kit_operational_surface, fn _repo_config ->
      tenant_id = "tenant-app-kit-operational"

      activate_fixture_registration!("1.0.0")

      %{program: program, work_class: work_class} = operational_fixture_stack(tenant_id)

      {:ok, page_request} = PageRequest.new(%{limit: 10})

      install_context =
        request_context(
          tenant_id,
          "trace/app-kit/install/#{System.unique_integer([:positive])}",
          %{program_id: program.id, work_class_id: work_class.id}
        )

      {:ok, install_template} =
        InstallTemplate.new(%{
          template_key: "expense-default",
          pack_slug: "expense_approval",
          pack_version: "1.0.0",
          default_bindings: %{
            "execution_bindings" => %{
              "expense_capture" => %{
                "placement_ref" => "local_docker"
              }
            }
          },
          metadata: %{"managed_by" => "stack_lab"}
        })

      surface_opts = surface_opts()

      {:ok, install_result} =
        InstallationSurface.create_installation(install_context, install_template, surface_opts)

      installation_ref = install_result.installation_ref

      with_installation_context =
        request_context(
          tenant_id,
          "trace/app-kit/work/#{System.unique_integer([:positive])}",
          %{program_id: program.id, work_class_id: work_class.id},
          installation_ref
        )

      {:ok, listed_installations} =
        InstallationSurface.list_installations(
          with_installation_context,
          page_request,
          surface_opts
        )

      {:ok, fetched_installation} =
        InstallationSurface.get_installation(
          with_installation_context,
          installation_ref,
          surface_opts
        )

      {:ok, subject_ref} =
        WorkSurface.ingest_subject(
          with_installation_context,
          %{
            external_ref: "linear:ENG-701",
            title: "Operational flow subject",
            payload: %{"issue_id" => "ENG-701"},
            source_kind: "linear"
          },
          surface_opts
        )

      {:ok, pre_run_detail} =
        WorkSurface.get_subject(with_installation_context, subject_ref, surface_opts)

      {:ok, listed_subjects} =
        WorkSurface.list_subjects(with_installation_context, page_request, surface_opts)

      {:ok, run_request} =
        RunRequest.new(%{
          subject_ref: subject_ref,
          recipe_ref: "expense_capture",
          params: %{"priority" => "high"}
        })

      {:ok, run_result} =
        WorkControl.start_run(with_installation_context, run_request, surface_opts)

      {:ok, subject_detail} =
        WorkSurface.get_subject(with_installation_context, subject_ref, surface_opts)

      {:ok, operator_projection} =
        OperatorSurface.subject_status(with_installation_context, subject_ref, surface_opts)

      {:ok, timeline} =
        OperatorSurface.timeline(with_installation_context, subject_ref, surface_opts)

      {:ok, actions} =
        OperatorSurface.available_actions(with_installation_context, subject_ref, surface_opts)

      chosen_action = choose_operator_action(actions)

      {:ok, action_request} =
        OperatorActionRequest.new(%{
          action_ref: chosen_action.action_ref,
          params: %{"reason" => "pause for review"}
        })

      {:ok, action_result} =
        OperatorSurface.apply_action(
          with_installation_context,
          subject_ref,
          action_request,
          surface_opts
        )

      {:ok, pending_reviews_before} =
        ReviewSurface.list_pending(with_installation_context, page_request, surface_opts)

      decision_ref = hd(pending_reviews_before.entries).decision_ref

      {:ok, review_detail_before} =
        ReviewSurface.get_review(with_installation_context, decision_ref, surface_opts)

      {:ok, review_action} =
        ReviewSurface.record_decision(
          with_installation_context,
          decision_ref,
          %{decision: :accept, reason: "approved by operator"},
          surface_opts
        )

      {:ok, pending_reviews_after} =
        ReviewSurface.list_pending(with_installation_context, page_request, surface_opts)

      {:ok, review_detail_after} =
        ReviewSurface.get_review(with_installation_context, decision_ref, surface_opts)

      {:ok, operator_projection_after_review} =
        OperatorSurface.subject_status(with_installation_context, subject_ref, surface_opts)

      trace_id = "trace/app-kit/unified/#{System.unique_integer([:positive])}"

      %{execution_id: execution_id} =
        seed_trace_ledger(installation_ref.id, subject_ref.id, trace_id)

      trace_context =
        request_context(
          tenant_id,
          trace_id,
          %{program_id: program.id, work_class_id: work_class.id},
          installation_ref
        )

      {:ok, execution_ref} =
        ExecutionRef.new(%{
          id: execution_id,
          subject_ref: subject_ref,
          recipe_ref: "expense_capture",
          dispatch_state: :accepted
        })

      {:ok, unified_trace} =
        OperatorSurface.get_unified_trace(
          trace_context,
          execution_ref,
          Keyword.put(surface_opts, :lower_facts, LowerFactsStub)
        )

      {:ok,
       %{
         case: :install_ingest_review_trace,
         tenant_id: tenant_id,
         installation: %{
           created_status: install_result.status,
           installation_id: installation_ref.id,
           pack_slug: installation_ref.pack_slug,
           fetched_status: fetched_installation.status,
           listed_ids: Enum.map(listed_installations.entries, & &1.id)
         },
         work: %{
           subject_id: subject_ref.id,
           listed_ids: Enum.map(listed_subjects.entries, & &1.subject_ref.id),
           pre_run_pending_obligation_ids:
             Enum.map(pre_run_detail.pending_obligations, & &1.obligation_id),
           pre_run_pending_decision_ref_ids:
             pre_run_detail.pending_obligations
             |> Enum.map(& &1.decision_ref_id)
             |> Enum.reject(&is_nil/1),
           pre_run_blocker_kinds: Enum.map(pre_run_detail.blocking_conditions, & &1.blocker_kind),
           pre_run_next_step_kind:
             pre_run_detail.next_step_preview && pre_run_detail.next_step_preview.step_kind,
           detail_active_run_id: payload_value(subject_detail, :active_run_id),
           detail_pending_reviews: Enum.map(subject_detail.pending_decision_refs, & &1.id),
           detail_pending_obligation_ids:
             Enum.map(subject_detail.pending_obligations, & &1.obligation_id),
           detail_pending_decision_ref_ids:
             subject_detail.pending_obligations
             |> Enum.map(& &1.decision_ref_id)
             |> Enum.reject(&is_nil/1),
           detail_blocker_kinds: Enum.map(subject_detail.blocking_conditions, & &1.blocker_kind),
           detail_next_step_kind:
             subject_detail.next_step_preview && subject_detail.next_step_preview.step_kind
         },
         control: %{
           state: run_result.state,
           run_id: run_result.payload.run_ref.run_id,
           review_unit_id: run_result.payload.review_unit_id
         },
         operator: %{
           lifecycle_state: operator_projection.lifecycle_state,
           current_run_id: payload_value(subject_detail, :active_run_id),
           current_execution_ref:
             operator_projection.current_execution_ref &&
               operator_projection.current_execution_ref.id,
           chosen_action: chosen_action.action_ref.action_kind,
           applied_action: action_result.action_ref.action_kind,
           timeline_kinds: Enum.map(timeline, & &1.event_kind),
           pending_obligation_ids:
             Enum.map(operator_projection.pending_obligations, & &1.obligation_id),
           pending_decision_ref_ids:
             operator_projection.pending_obligations
             |> Enum.map(& &1.decision_ref_id)
             |> Enum.reject(&is_nil/1),
           blocker_kinds: Enum.map(operator_projection.blocking_conditions, & &1.blocker_kind),
           next_step_kind:
             operator_projection.next_step_preview &&
               operator_projection.next_step_preview.step_kind
         },
         review: %{
           pending_ids_before: Enum.map(pending_reviews_before.entries, & &1.decision_ref.id),
           pending_ids_after: Enum.map(pending_reviews_after.entries, & &1.decision_ref.id),
           status_before: review_detail_before.status,
           status_after: review_detail_after.status,
           action_kind: review_action.action_ref.action_kind,
           blocker_kinds_after:
             Enum.map(operator_projection_after_review.blocking_conditions, & &1.blocker_kind),
           next_step_kind_after:
             operator_projection_after_review.next_step_preview &&
               operator_projection_after_review.next_step_preview.step_kind
         },
         trace: %{
           execution_id: execution_id,
           trace_id: unified_trace.trace_id,
           step_sources: Enum.map(unified_trace.steps, & &1.source)
         }
       }}
    end)
  end

  def run_case(:governed_agent_workload_contract) do
    MezzanineOperationalStack.with_store(:app_kit_governed_agent_workload, fn _repo_config ->
      tenant_id = "tenant-app-kit-governed-workload"

      activate_governed_workload_registration!()

      %{program: program, work_class: work_class} = governed_workload_fixture_stack(tenant_id)

      {:ok, page_request} = PageRequest.new(%{limit: 10})
      {:ok, workload} = RunGovernance.governed_agent_workload(governed_workload_attrs())

      install_context =
        request_context(
          tenant_id,
          "trace/app-kit/governed/install/#{System.unique_integer([:positive])}",
          %{program_id: program.id, work_class_id: work_class.id}
        )

      surface_opts = surface_opts()

      {:ok, install_result} =
        InstallationSurface.create_installation(
          install_context,
          governed_workload_install_template!(),
          surface_opts
        )

      installation_ref = install_result.installation_ref

      context =
        request_context(
          tenant_id,
          "trace/app-kit/governed/work/#{System.unique_integer([:positive])}",
          %{program_id: program.id, work_class_id: work_class.id},
          installation_ref
        )

      {:ok, subject_ref} =
        WorkSurface.ingest_subject(
          context,
          %{
            external_ref: "linear:ENG-901",
            title: "Governed coding operation",
            payload: %{"issue_id" => "ENG-901"},
            source_kind: "linear"
          },
          surface_opts
        )

      {:ok, run_request} =
        RunRequest.new(%{
          subject_ref: subject_ref,
          recipe_ref: "service_operations",
          params: %{"priority" => "high"}
        })

      {:ok, run_result} = WorkControl.start_run(context, run_request, surface_opts)
      {:ok, subject_detail} = WorkSurface.get_subject(context, subject_ref, surface_opts)

      {:ok, operator_projection} =
        OperatorSurface.subject_status(context, subject_ref, surface_opts)

      {:ok, pending_reviews_before} =
        ReviewSurface.list_pending(context, page_request, surface_opts)

      decision_ref = hd(pending_reviews_before.entries).decision_ref

      {:ok, review_detail_before} =
        ReviewSurface.get_review(context, decision_ref, surface_opts)

      {:ok, review_action} =
        ReviewSurface.record_decision(
          context,
          decision_ref,
          %{decision: :accept, reason: "approved by operator"},
          surface_opts
        )

      {:ok, pending_reviews_after} =
        ReviewSurface.list_pending(context, page_request, surface_opts)

      {:ok, review_detail_after} = ReviewSurface.get_review(context, decision_ref, surface_opts)

      {:error, bare_asm_substitute_rejection} =
        RunGovernance.governed_agent_workload(bare_asm_substitute_attrs())

      {:ok,
       %{
         case: :governed_agent_workload_contract,
         tenant_id: tenant_id,
         governed_workload: governed_workload_summary(workload),
         installation: %{
           created_status: install_result.status,
           installation_id: installation_ref.id,
           pack_slug: installation_ref.pack_slug
         },
         work: %{
           subject_id: subject_ref.id,
           detail_active_run_id: payload_value(subject_detail, :active_run_id),
           detail_pending_reviews: Enum.map(subject_detail.pending_decision_refs, & &1.id),
           detail_blocker_kinds: Enum.map(subject_detail.blocking_conditions, & &1.blocker_kind),
           detail_next_step_kind:
             subject_detail.next_step_preview && subject_detail.next_step_preview.step_kind
         },
         control: %{
           state: run_result.state,
           run_id: run_result.payload.run_ref.run_id,
           review_unit_id: run_result.payload.review_unit_id
         },
         operator: %{
           lifecycle_state: operator_projection.lifecycle_state,
           blocker_kinds: Enum.map(operator_projection.blocking_conditions, & &1.blocker_kind),
           pending_decision_ref_ids:
             operator_projection.pending_obligations
             |> Enum.map(& &1.decision_ref_id)
             |> Enum.reject(&is_nil/1)
         },
         review: %{
           pending_ids_before: Enum.map(pending_reviews_before.entries, & &1.decision_ref.id),
           pending_ids_after: Enum.map(pending_reviews_after.entries, & &1.decision_ref.id),
           status_before: review_detail_before.status,
           status_after: review_detail_after.status,
           action_kind: review_action.action_ref.action_kind
         },
         lifecycle: %{
           states: workload.lifecycle_states,
           transition_paths: RunGovernance.lifecycle_transition_paths(workload)
         },
         scale_pressure_seed: RunGovernance.scale_pressure_seed(workload),
         bare_asm_substitute_rejection: bare_asm_substitute_rejection,
         task_async_stream_substitute?: false
       }}
    end)
  end

  def run_case(:lower_backed_command_trace) do
    with_lower_backed_runtime(
      :app_kit_lower_backed_command_trace,
      "tenant-app-kit-lower-backed",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        receipt_proof =
          lower_receipt_proof!(
            env.context,
            env.installation_ref.id,
            lower_dispatch.execution.id,
            lower_dispatch.acceptance.submission_key
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(
            env.context,
            execution_ref,
            Keyword.merge(
              env.surface_opts,
              lower_operations: [:fetch_submission_receipt]
            )
          )

        {:ok,
         %{
           case: :lower_backed_command_trace,
           tenant_id: env.tenant_id,
           installation: %{
             created_status: env.install_result.status,
             installation_id: env.installation_ref.id,
             pack_slug: env.installation_ref.pack_slug
           },
           work: %{
             subject_id: env.subject_ref.id,
             run_id: env.run_result.payload.run_ref.run_id,
             state: env.run_result.state
           },
           dispatch: %{
             execution_id: lower_dispatch.execution.id,
             classification: lower_dispatch.classification,
             job_status: lower_dispatch.job_status,
             submission_status: lower_dispatch.execution.submission_ref["status"],
             submission_key: lower_dispatch.acceptance.submission_key,
             submission_receipt_ref: lower_dispatch.acceptance.submission_receipt_ref
           },
           receipt_proof: receipt_proof,
           trace: %{
             trace_id: unified_trace.trace_id,
             step_sources: Enum.map(unified_trace.steps, & &1.source),
             join_keys: unified_trace.join_keys
           }
         }}
      end
    )
  end

  def run_case(:observability_trace_join_continuity) do
    with_lower_backed_runtime(
      :observability_trace_join_continuity,
      "tenant-observability-trace-join",
      fn env ->
        telemetry_handler_id = "stack-lab-scenario19-#{System.unique_integer([:positive])}"

        attach_observability_telemetry!(telemetry_handler_id, self())

        try do
          :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

          {:ok, lower_dispatch} =
            lower_backed_dispatch(
              env.context,
              env.installation_ref,
              env.subject_ref,
              env.run_result
            )

          trace_id = lower_dispatch.execution.trace_id
          execution_id = lower_dispatch.execution.id

          trace_graph =
            enrich_subject_trace_graph!(
              env.installation_ref.id,
              env.subject_ref.id,
              execution_id,
              trace_id
            )

          {:ok, execution_ref} =
            ExecutionRef.new(%{
              id: execution_id,
              subject_ref: env.subject_ref,
              recipe_ref: "expense_capture",
              dispatch_state: :completed
            })

          trace_opts = Keyword.put(env.surface_opts, :lower_facts, LowerFactsStub)

          {:ok, live_trace} =
            OperatorSurface.get_unified_trace(
              env.context,
              execution_ref,
              trace_opts
            )

          live_lower_fetches = collect_lower_fetch_messages!()

          {:ok, trace_surfaces} =
            AITraceClaimCheckTraceContinuity.prove_trace_surfaces(
              trace_id,
              env.tenant_id,
              execution_id,
              label: :observability_trace_join_continuity
            )

          execution_plane_backfill =
            emit_execution_plane_backfill!(trace_id, env.tenant_id)

          :ok = emit_citadel_trace_failure!(trace_id, env.tenant_id, execution_id)

          {:ok, archival_result} =
            Scheduler.archive_subject(
              env.installation_ref.id,
              env.subject_ref.id,
              now: @scenario_19_archive_now
            )

          archived_hot_reads =
            assert_archived_hot_reads!(
              env.context,
              env.subject_ref,
              env.surface_opts,
              archival_result.manifest_ref
            )

          {:ok, archived_trace} =
            OperatorSurface.get_unified_trace(
              env.context,
              execution_ref,
              trace_opts
            )

          archived_pivot_traces =
            archived_pivot_summaries!(
              env.installation_ref.id,
              %{
                trace_id: trace_id,
                subject_id: env.subject_ref.id,
                execution_id: execution_id,
                decision_id: trace_graph.decision_id,
                run_id: "run-#{execution_id}",
                attempt_id: "attempt-#{execution_id}",
                artifact_id: "artifact-#{execution_id}",
                manifest_ref: archival_result.manifest_ref
              }
            )

          archived_lower_fetches = collect_lower_fetch_messages!()
          Process.sleep(50)
          telemetry_events = collect_observability_telemetry!()
          telemetry = summarize_observability_telemetry!(telemetry_events)

          {:ok,
           %{
             case: :observability_trace_join_continuity,
             scenario: 19,
             tenant_id: env.tenant_id,
             installation_id: env.installation_ref.id,
             subject_id: env.subject_ref.id,
             execution_id: execution_id,
             trace_id: trace_id,
             live_path: %{
               request_edge_trace_id: env.context.trace_id,
               mezzanine_trace_id: lower_dispatch.execution.trace_id,
               lower_gateway_trace_id: lower_dispatch.gateway.trace_id,
               classification: lower_dispatch.classification,
               submission_key: lower_dispatch.acceptance.submission_key,
               step_sources: Enum.map(live_trace.steps, & &1.source),
               join_keys: live_trace.join_keys
             },
             telemetry: telemetry,
             execution_plane_backfill: execution_plane_backfill,
             claim_check: trace_surfaces.claim_check,
             execution_plane: trace_surfaces.execution_plane,
             aitrace: trace_surfaces.aitrace,
             archival: %{
               manifest_ref: archival_result.manifest_ref,
               hot_read_errors: archived_hot_reads,
               trace_id: archived_trace.trace_id,
               archived_manifest_ref: archived_trace.metadata.archived_manifest_ref,
               step_sources: Enum.map(archived_trace.steps, & &1.source),
               staleness_classes:
                 archived_trace.steps
                 |> Enum.map(& &1.staleness_class)
                 |> Enum.uniq()
                 |> Enum.sort(),
               join_keys: archived_trace.join_keys,
               live_lower_fetches: live_lower_fetches,
               archived_lower_fetches: archived_lower_fetches,
               pivot_traces: archived_pivot_traces,
               wrong_installation_pivot_error:
                 archived_pivot_error!(
                   Ecto.UUID.generate(),
                   :trace_id,
                   trace_id
                 )
             }
           }}
        after
          :telemetry.detach(telemetry_handler_id)
        end
      end
    )
  end

  def run_case(:lower_backed_command_terminal_rejection) do
    with_lower_backed_runtime(
      :app_kit_lower_backed_command_terminal_rejection,
      "tenant-app-kit-lower-backed-reject",
      fn env ->
        :ok =
          TransportRuntime.put!(
            lower_transport_config(self(), env.subject_ref.id, :scope_rejection)
          )

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(env.context, execution_ref, env.surface_opts)

        rejected_execution = execution_trace_step!(unified_trace, lower_dispatch.execution.id)

        {:ok,
         %{
           case: :lower_backed_command_terminal_rejection,
           tenant_id: env.tenant_id,
           installation: %{
             created_status: env.install_result.status,
             installation_id: env.installation_ref.id,
             pack_slug: env.installation_ref.pack_slug
           },
           work: %{
             subject_id: env.subject_ref.id,
             run_id: env.run_result.payload.run_ref.run_id,
             state: env.run_result.state
           },
           dispatch: %{
             execution_id: lower_dispatch.execution.id,
             classification: lower_dispatch.classification,
             execution_state: lower_dispatch.execution.dispatch_state,
             job_status: lower_dispatch.job_status,
             terminal_rejection_reason: lower_dispatch.execution.terminal_rejection_reason,
             rejection_reason: rejection_reason(lower_dispatch.rejection),
             rejection_family:
               if lower_dispatch.rejection do
                 to_string(lower_dispatch.rejection.rejection_family)
               end
           },
           trace: %{
             trace_id: unified_trace.trace_id,
             step_sources: Enum.map(unified_trace.steps, & &1.source),
             rejected_execution: rejected_execution
           }
         }}
      end
    )
  end

  def run_case(:lower_backed_command_semantic_failure) do
    with_lower_backed_runtime(
      :app_kit_lower_backed_command_semantic_failure,
      "tenant-app-kit-lower-backed-semantic-failure",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        semantic_failure_carrier =
          semantic_failure_carrier!(
            env.tenant_id,
            lower_dispatch.execution.trace_id,
            lower_dispatch.execution.id
          )

        {:ok, failed_execution} =
          ExecutionRecord.record_semantic_failure(lower_dispatch.execution, %{
            lower_receipt: lower_dispatch.execution.lower_receipt,
            last_dispatch_error_payload: %{
              "error" => %{
                "kind" => "semantic_failure",
                "carrier" => SemanticFailure.to_payload(semantic_failure_carrier)
              }
            },
            trace_id: lower_dispatch.execution.trace_id,
            causation_id: "semantic-failure:#{lower_dispatch.execution.id}",
            actor_ref: %{kind: :reconciler}
          })

        {:ok, recovery} =
          SemanticFailureRecoveryService.recover_execution(env.tenant_id, failed_execution.id)

        {:ok, page_request} = PageRequest.new(%{limit: 10})

        {:ok, subject_detail} =
          WorkSurface.get_subject(env.context, env.subject_ref, env.surface_opts)

        {:ok, operator_projection} =
          OperatorSurface.subject_status(env.context, env.subject_ref, env.surface_opts)

        {:ok, pending_reviews} =
          ReviewSurface.list_pending(env.context, page_request, env.surface_opts)

        decision_ref = hd(pending_reviews.entries).decision_ref

        {:ok, review_detail} =
          ReviewSurface.get_review(env.context, decision_ref, env.surface_opts)

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: failed_execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: failed_execution.dispatch_state
          })

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(env.context, execution_ref, env.surface_opts)

        failed_execution_step = execution_trace_step!(unified_trace, failed_execution.id)

        {:ok,
         %{
           case: :lower_backed_command_semantic_failure,
           tenant_id: env.tenant_id,
           installation: %{
             created_status: env.install_result.status,
             installation_id: env.installation_ref.id,
             pack_slug: env.installation_ref.pack_slug
           },
           work: %{
             subject_id: env.subject_ref.id,
             run_id: env.run_result.payload.run_ref.run_id,
             state: env.run_result.state
           },
           dispatch: %{
             execution_id: failed_execution.id,
             classification: :semantic_failure,
             execution_state: failed_execution.dispatch_state,
             failure_kind: failed_execution.failure_kind,
             job_status: :completed
           },
           recovery: %{
             work_state: subject_detail.lifecycle_state,
             active_run_state: subject_detail.payload.active_run_status,
             pending_review_ids: Enum.map(subject_detail.pending_decision_refs, & &1.id),
             operator_lifecycle_state: operator_projection.lifecycle_state,
             operator_pending_decision_ids:
               Enum.map(operator_projection.pending_decision_refs, & &1.id),
             review_id: decision_ref.id,
             review_status: review_detail.status,
             review_recovery_kind:
               review_detail.payload.review_unit.decision_profile["recovery_kind"],
             timeline_kinds: Enum.map(operator_projection.payload.timeline, & &1.event_kind),
             recovery_review_created?: recovery.review_created?
           },
           trace: %{
             trace_id: unified_trace.trace_id,
             step_sources: Enum.map(unified_trace.steps, & &1.source),
             failed_execution:
               Map.merge(failed_execution_step, %{
                 semantic_failure_kind: semantic_failure_carrier_value(failed_execution, "kind"),
                 semantic_failure_retry_class:
                   semantic_failure_carrier_value(failed_execution, "retry_class"),
                 semantic_failure_trace_id:
                   semantic_failure_carrier_value(failed_execution, "request_trace_id")
               })
           }
         }}
      end
    )
  end

  def run_case(:reviewable_connector_automation_console) do
    with_lower_backed_runtime(
      :reviewable_connector_automation_console,
      "tenant-reviewable-connector-automation",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:ok, page_request} = PageRequest.new(%{limit: 10})

        {:ok, listed_subjects} =
          WorkSurface.list_subjects(env.context, page_request, env.surface_opts)

        {:ok, read_lease} =
          OperatorSurface.issue_read_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              allowed_operations: [:fetch_submission_receipt],
              scope: %{"mode" => "connector_console_receipt"}
            )
          )

        {:ok, live_stream_lease} =
          OperatorSurface.issue_stream_attach_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              poll_interval_ms: @scenario_24_poll_interval_ms,
              scope: %{"mode" => "connector_console_live_stream"}
            )
          )

        live_stream_lease_id = live_stream_lease.lease_ref.id

        {:ok, live_host} =
          StreamAttachHost.start_link(
            lease_id: live_stream_lease_id,
            token: live_stream_lease.attach_token,
            authorization_scope: authorization_scope!(live_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        live_attach_cursor = await_stream_attached!(live_stream_lease_id)

        direct_receipt =
          direct_submission_receipt_read!(
            read_lease,
            lower_dispatch.acceptance.submission_key
          )

        {:ok, failed_execution} =
          ExecutionRecord.record_semantic_failure(lower_dispatch.execution, %{
            lower_receipt: lower_dispatch.execution.lower_receipt,
            last_dispatch_error_payload: %{
              "error" => %{
                "kind" => "semantic_failure",
                "reason" => "connector_schema_mismatch"
              }
            },
            trace_id: lower_dispatch.execution.trace_id,
            causation_id: "connector-console-semantic-failure:#{lower_dispatch.execution.id}",
            actor_ref: %{kind: :reconciler}
          })

        {:ok, recovery} =
          SemanticFailureRecoveryService.recover_execution(env.tenant_id, failed_execution.id)

        {:ok, case_file_before_pause} =
          connector_console_case_file(env.context, env.subject_ref, env.surface_opts)

        {:ok, pending_reviews_before} =
          ReviewSurface.list_pending(env.context, page_request, env.surface_opts)

        decision_ref = hd(pending_reviews_before.entries).decision_ref

        {:ok, review_detail_before} =
          ReviewSurface.get_review(env.context, decision_ref, env.surface_opts)

        {:ok, failed_execution_ref} =
          ExecutionRef.new(%{
            id: failed_execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: failed_execution.dispatch_state
          })

        trace_opts = Keyword.put(env.surface_opts, :lower_facts, LowerFactsStub)

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(env.context, failed_execution_ref, trace_opts)

        failed_execution_step = execution_trace_step!(unified_trace, failed_execution.id)

        {:ok, actions} =
          OperatorSurface.available_actions(env.context, env.subject_ref, env.surface_opts)

        chosen_action = choose_operator_action(actions, "pause")

        {:ok, action_request} =
          OperatorActionRequest.new(%{
            action_ref: chosen_action.action_ref,
            params: %{"reason" => "connector case triage"}
          })

        {:ok, pause_result} =
          OperatorSurface.apply_action(
            env.context,
            env.subject_ref,
            action_request,
            env.surface_opts
          )

        post_pause_read_error =
          Leasing.authorize_read(
            authorization_scope!(read_lease),
            read_lease.lease_ref.id,
            read_lease.lease_token,
            :fetch_submission_receipt,
            repo: ExecutionRepo
          )

        post_pause_stream_error =
          Leasing.authorize_stream_attach(
            authorization_scope!(live_stream_lease),
            live_stream_lease_id,
            live_stream_lease.attach_token,
            repo: ExecutionRepo
          )

        if Process.alive?(live_host) do
          GenServer.stop(live_host, :normal)
        end

        {:ok, review_action} =
          ReviewSurface.record_decision(
            env.context,
            decision_ref,
            %{decision: :accept, reason: "connector recovery approved"},
            env.surface_opts
          )

        {:ok, pending_reviews_after} =
          ReviewSurface.list_pending(env.context, page_request, env.surface_opts)

        {:ok, review_detail_after} =
          ReviewSurface.get_review(env.context, decision_ref, env.surface_opts)

        {:ok, case_file_after_review} =
          connector_console_case_file(env.context, env.subject_ref, env.surface_opts)

        {:ok,
         %{
           case: :reviewable_connector_automation_console,
           scenario: 42,
           tenant_id: env.tenant_id,
           whitepaper_use_case: :"18.2_reviewable_connector_automation",
           synthetic_shape: %{
             surface_kind: :connector_automation_console,
             differs_from: :single_product_operator_shell,
             product_posture: :reviewable_connector_automation
           },
           console: %{
             listed_subject_ids: Enum.map(listed_subjects.entries, & &1.subject_ref.id),
             pending_review_ids_before:
               Enum.map(pending_reviews_before.entries, & &1.decision_ref.id),
             pending_review_ids_after:
               Enum.map(pending_reviews_after.entries, & &1.decision_ref.id),
             recovery_review_created?: recovery.review_created?
           },
           automation_case: %{
             subject_id: env.subject_ref.id,
             run_id: env.run_result.payload.run_ref.run_id,
             lifecycle_state_before_pause: case_file_before_pause.lifecycle_state,
             lifecycle_state_after_review: case_file_after_review.lifecycle_state,
             blocker_kinds_before_pause: case_file_before_pause.blocker_kinds,
             blocker_kinds_after_review: case_file_after_review.blocker_kinds,
             next_step_kind_before_pause: case_file_before_pause.next_step_kind,
             next_step_kind_after_review: case_file_after_review.next_step_kind,
             current_execution_ref_before_pause: case_file_before_pause.current_execution_ref,
             current_execution_ref_after_review: case_file_after_review.current_execution_ref,
             lineage_execution_ref_before_pause: case_file_before_pause.lineage_execution_ref,
             lineage_execution_ref_after_review: case_file_after_review.lineage_execution_ref,
             pending_review_ids_before: case_file_before_pause.pending_review_ids,
             pending_review_ids_after: case_file_after_review.pending_review_ids
           },
           operator: %{
             available_action_kinds: Enum.map(actions, & &1.action_ref.action_kind),
             applied_action: pause_result.action_ref.action_kind,
             action_status: pause_result.status,
             invalidated_live_leases?:
               leases_invalidated?([post_pause_read_error, post_pause_stream_error])
           },
           review: %{
             decision_id: decision_ref.id,
             status_before: review_detail_before.status,
             status_after: review_detail_after.status,
             recovery_kind:
               review_detail_before.payload.review_unit.decision_profile["recovery_kind"],
             action_kind: review_action.action_ref.action_kind
           },
           lower_access: %{
             submission_key: direct_receipt.submission_key,
             submission_receipt_ref: direct_receipt.submission_receipt_ref,
             stream_attached_cursor: live_attach_cursor,
             live_stream_lease_id: live_stream_lease_id,
             post_pause_read: normalize_read_error(post_pause_read_error),
             post_pause_stream: normalize_read_error(post_pause_stream_error)
           },
           trace: %{
             trace_id: unified_trace.trace_id,
             step_sources: Enum.map(unified_trace.steps, & &1.source),
             failed_execution: failed_execution_step
           }
         }}
      end
    )
  end

  def run_case(:leased_direct_read_and_stream_invalidation) do
    with_lower_backed_runtime(
      :app_kit_leased_direct_read_and_stream_invalidation,
      "tenant-app-kit-leased-read-stream",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:ok, disconnected_stream_lease} =
          OperatorSurface.issue_stream_attach_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              poll_interval_ms: @scenario_24_poll_interval_ms,
              scope: %{"mode" => "disconnect_catchup"}
            )
          )

        disconnected_stream_lease_id = disconnected_stream_lease.lease_ref.id

        {:ok, disconnected_host} =
          StreamAttachHost.start_link(
            lease_id: disconnected_stream_lease_id,
            token: disconnected_stream_lease.attach_token,
            authorization_scope: authorization_scope!(disconnected_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        disconnected_attach_cursor = await_stream_attached!(disconnected_stream_lease_id)

        disconnect_started_at_ms = System.monotonic_time(:millisecond)
        :ok = GenServer.stop(disconnected_host, :normal)

        burst_rows =
          emit_stream_invalidation_burst!(
            disconnected_stream_lease_id,
            @scenario_24_burst_count,
            @scenario_24_burst_concurrency
          )

        ensure_disconnect_window_elapsed!(
          disconnect_started_at_ms,
          @scenario_24_disconnect_window_ms
        )

        {:ok, reconnect_host} =
          StreamAttachHost.start_link(
            lease_id: disconnected_stream_lease_id,
            token: disconnected_stream_lease.attach_token,
            authorization_scope: authorization_scope!(disconnected_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        reconnect_invalidation =
          await_stream_invalidated!(
            disconnected_stream_lease_id,
            @scenario_24_reconnect_timeout_ms
          )

        ensure_no_stream_attached!(disconnected_stream_lease_id)
        wait_for_stream_host_shutdown!(reconnect_host)

        {:ok, read_lease} =
          OperatorSurface.issue_read_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              allowed_operations: [:fetch_submission_receipt],
              scope: %{"mode" => "direct_receipt_read"}
            )
          )

        {:ok, live_stream_lease} =
          OperatorSurface.issue_stream_attach_lease(
            env.context,
            execution_ref,
            Keyword.merge(env.surface_opts,
              poll_interval_ms: @scenario_24_poll_interval_ms,
              scope: %{"mode" => "live_stream"}
            )
          )

        live_stream_lease_id = live_stream_lease.lease_ref.id

        {:ok, live_host} =
          StreamAttachHost.start_link(
            lease_id: live_stream_lease_id,
            token: live_stream_lease.attach_token,
            authorization_scope: authorization_scope!(live_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        live_attach_cursor = await_stream_attached!(live_stream_lease_id)

        direct_read_before =
          direct_submission_receipt_read!(
            read_lease,
            lower_dispatch.acceptance.submission_key
          )

        pause_started_at_ms = System.monotonic_time(:millisecond)

        {:ok, pause_result} =
          OperatorCommands.pause(env.subject_ref.id,
            reason: "leased stream shutdown",
            trace_id: "trace-stage24-pause",
            causation_id: "cause-stage24-pause",
            actor_ref: %{kind: :operator}
          )

        live_stream_invalidation =
          await_stream_invalidated!(
            live_stream_lease_id,
            @scenario_24_reconnect_timeout_ms
          )

        live_stream_invalidated_after_ms =
          System.monotonic_time(:millisecond) - pause_started_at_ms

        wait_for_stream_host_shutdown!(live_host)

        post_pause_read_error =
          Leasing.authorize_read(
            authorization_scope!(read_lease),
            read_lease.lease_ref.id,
            read_lease.lease_token,
            :fetch_submission_receipt,
            repo: ExecutionRepo
          )

        {:ok, refused_live_host} =
          StreamAttachHost.start_link(
            lease_id: live_stream_lease_id,
            token: live_stream_lease.attach_token,
            authorization_scope: authorization_scope!(live_stream_lease),
            repo: ExecutionRepo,
            poll_interval_ms: @scenario_24_poll_interval_ms,
            notify: self()
          )

        refused_live_invalidation =
          await_stream_invalidated!(
            live_stream_lease_id,
            @scenario_24_reconnect_timeout_ms
          )

        ensure_no_stream_attached!(live_stream_lease_id)
        wait_for_stream_host_shutdown!(refused_live_host)

        burst_sequence_numbers = Enum.map(burst_rows, & &1.sequence_number)
        pause_invalidated_ids = Map.get(pause_result.details, :invalidated_lease_ids, [])

        {:ok,
         %{
           case: :leased_direct_read_and_stream_invalidation,
           scenario: 24,
           tenant_id: env.tenant_id,
           installation_id: env.installation_ref.id,
           execution_id: lower_dispatch.execution.id,
           disconnect_window_ms: @scenario_24_disconnect_window_ms,
           direct_read: %{
             submission_key: direct_read_before.submission_key,
             submission_receipt_ref: direct_read_before.submission_receipt_ref
           },
           disconnected_stream: %{
             lease_id: disconnected_stream_lease_id,
             attached_cursor: disconnected_attach_cursor,
             reconnect_invalidation_reason: reconnect_invalidation.reason,
             reconnect_invalidation_sequence: reconnect_invalidation.sequence_number
           },
           concurrent_burst: %{
             invalidation_count: length(burst_rows),
             requested_connection_count: @scenario_24_burst_concurrency,
             repo_pool_size: ExecutionRepo.config()[:pool_size],
             sequence_numbers: burst_sequence_numbers,
             contiguous_sequences?:
               burst_sequence_numbers
               |> Enum.sort()
               |> contiguous_sequence?()
           },
           live_stream: %{
             lease_id: live_stream_lease_id,
             attached_cursor: live_attach_cursor,
             invalidation_reason: live_stream_invalidation.reason,
             invalidated_after_ms: live_stream_invalidated_after_ms,
             post_pause_refusal_reason: refused_live_invalidation.reason
           },
           control_write: %{
             result_status: pause_result.status,
             invalidated_lease_ids: pause_invalidated_ids,
             invalidated_live_leases?:
               Enum.all?(
                 [read_lease.lease_ref.id, live_stream_lease_id],
                 &(&1 in pause_invalidated_ids)
               )
           },
           post_pause_read: normalize_read_error(post_pause_read_error)
         }}
      end
    )
  end

  def run_case(:unauthorized_lower_trace_read) do
    with_lower_backed_runtime(
      :app_kit_unauthorized_lower_trace_read,
      "tenant-app-kit-lower-backed-authz",
      fn env ->
        :ok = TransportRuntime.put!(lower_transport_config(self(), env.subject_ref.id))

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            env.context,
            env.installation_ref,
            env.subject_ref,
            env.run_result
          )

        unauthorized_context =
          request_context(
            env.tenant_id,
            env.context.trace_id,
            %{program_id: env.program.id, work_class_id: env.work_class.id},
            %{
              id: "inst-other",
              pack_slug: env.installation_ref.pack_slug,
              status: :active
            }
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: env.subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:error, error} =
          OperatorSurface.get_unified_trace(
            unauthorized_context,
            execution_ref,
            env.surface_opts
          )

        {:ok,
         %{
           case: :unauthorized_lower_trace_read,
           tenant_id: env.tenant_id,
           installation_id: env.installation_ref.id,
           execution_id: lower_dispatch.execution.id,
           error: %{
             code: error.code,
             kind: error.kind,
             retryable: error.retryable
           }
         }}
      end
    )
  end

  defp with_lower_backed_runtime(case_name, tenant_id, fun) when is_function(fun, 1) do
    MezzanineOperationalStack.with_store(case_name, fn _repo_config ->
      store_local_dir = store_local_dir(case_name)

      RoundtripRuntime.flush_transport_messages()
      ensure_store_local_ready!(store_local_dir)

      try do
        activate_fixture_registration!("1.0.1")

        %{program: program, work_class: work_class} =
          operational_fixture_stack(tenant_id, review_required?: false)

        surface_opts = surface_opts()

        install_context =
          request_context(
            tenant_id,
            "trace/app-kit/lower/install/#{System.unique_integer([:positive])}",
            %{program_id: program.id, work_class_id: work_class.id}
          )

        {:ok, install_result} =
          InstallationSurface.create_installation(
            install_context,
            lower_backed_install_template!(),
            surface_opts
          )

        installation_ref = install_result.installation_ref

        runtime_trace_id = "trace/app-kit/lower/runtime/#{System.unique_integer([:positive])}"

        context =
          request_context(
            tenant_id,
            runtime_trace_id,
            %{program_id: program.id, work_class_id: work_class.id},
            installation_ref
          )

        {:ok, subject_ref} =
          WorkSurface.ingest_subject(
            context,
            %{
              external_ref: "linear:ENG-801",
              title: "Lower-backed operational flow subject",
              payload: %{"issue_id" => "ENG-801"},
              source_kind: "linear"
            },
            surface_opts
          )

        :ok = seed_mezzanine_subject!(installation_ref.id, subject_ref)

        {:ok, run_request} =
          RunRequest.new(%{
            subject_ref: subject_ref,
            recipe_ref: "expense_capture",
            params: %{"priority" => "high"}
          })

        {:ok, run_result} = WorkControl.start_run(context, run_request, surface_opts)

        fun.(%{
          tenant_id: tenant_id,
          program: program,
          work_class: work_class,
          surface_opts: surface_opts,
          install_result: install_result,
          installation_ref: installation_ref,
          context: context,
          subject_ref: subject_ref,
          run_result: run_result
        })
      after
        :ok = TransportRuntime.reset!()
        stop_store_local()
        File.rm_rf!(store_local_dir)
      end
    end)
  end

  defp lower_backed_install_template! do
    {:ok, template} =
      InstallTemplate.new(%{
        template_key: "expense-lower-backed",
        pack_slug: "expense_approval",
        pack_version: "1.0.1",
        default_bindings: %{
          "execution_bindings" => %{
            "expense_capture" => %{
              "placement_ref" => "workspace_runtime",
              "execution_params" => %{"timeout_ms" => 300_000}
            }
          }
        },
        metadata: %{"managed_by" => "stack_lab"}
      })

    template
  end

  defp seed_mezzanine_subject!(installation_id, subject_ref) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    ObjectsRepo.query!(
      """
      INSERT INTO subject_records (
        id,
        installation_id,
        source_ref,
        subject_kind,
        lifecycle_state,
        status,
        payload,
        schema_version,
        opened_at,
        status_updated_at,
        row_version,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2, $3, $4, $5, 'active', $6, 1, $7, $7, 1, $7, $7)
      """,
      [
        dump_uuid!(subject_ref.id),
        installation_id,
        "app-kit:#{subject_ref.id}",
        "expense_request",
        "submitted",
        %{},
        now
      ]
    )

    :ok
  end

  defp surface_opts do
    [
      installation_backend: MezzanineBridge,
      operator_backend: MezzanineBridge,
      review_backend: MezzanineBridge,
      work_backend: MezzanineBridge,
      work_query_backend: MezzanineBridge
    ]
  end

  defp request_context(tenant_id, trace_id, metadata, installation_ref \\ nil) do
    {:ok, context} =
      RequestContext.new(%{
        trace_id: normalize_trace_id(trace_id),
        actor_ref: %{id: "ops_lead", kind: :human},
        tenant_ref: %{id: tenant_id},
        installation_ref: installation_ref,
        metadata: revision_epoch_metadata(metadata, installation_ref)
      })

    context
  end

  defp revision_epoch_metadata(metadata, nil), do: metadata

  defp revision_epoch_metadata(metadata, installation_ref) do
    revision = Map.get(installation_ref, :compiled_pack_revision) || 1

    metadata
    |> Map.put_new(:installation_revision, revision)
    |> Map.put_new(:activation_epoch, 1)
    |> Map.put_new(:lease_epoch, 1)
  end

  defp choose_operator_action(actions, preferred_action_kind \\ "pause") do
    Enum.find(actions, &(&1.action_ref.action_kind == preferred_action_kind)) || hd(actions)
  end

  defp connector_console_case_file(context, subject_ref, surface_opts) do
    with {:ok, subject_detail} <- WorkSurface.get_subject(context, subject_ref, surface_opts),
         {:ok, operator_projection} <-
           OperatorSurface.subject_status(context, subject_ref, surface_opts) do
      current_execution_ref =
        operator_projection.current_execution_ref &&
          operator_projection.current_execution_ref.id

      {:ok,
       %{
         lifecycle_state: subject_detail.lifecycle_state,
         blocker_kinds: Enum.map(operator_projection.blocking_conditions, & &1.blocker_kind),
         next_step_kind:
           operator_projection.next_step_preview &&
             operator_projection.next_step_preview.step_kind,
         current_execution_ref: current_execution_ref,
         lineage_execution_ref:
           current_execution_ref || latest_execution_id(subject_detail, operator_projection),
         pending_review_ids: Enum.map(subject_detail.pending_decision_refs, & &1.id)
       }}
    end
  end

  defp latest_execution_id(subject_detail, operator_projection) do
    payload_value(subject_detail, :latest_execution_id) ||
      payload_value(operator_projection, :latest_execution_id)
  end

  defp payload_value(struct_or_map, key) when is_atom(key) do
    payload = Map.get(struct_or_map, :payload, %{})

    if is_map(payload) do
      Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
    end
  end

  defp normalize_trace_id(trace_id) do
    case TraceIdentity.ensure(trace_id) do
      {:ok, normalized_trace_id} ->
        normalized_trace_id

      {:error, :invalid_trace_id} when is_binary(trace_id) ->
        trace_id
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)
        |> binary_part(0, 32)

      {:error, :invalid_trace_id} ->
        TraceIdentity.mint()
    end
  end

  defp activate_fixture_registration!(version) do
    manifest = %Manifest{
      pack_slug: "expense_approval",
      version: version,
      migration_strategy: :additive,
      profile_slots: ProfileSlots.default(),
      subject_kind_specs: [%SubjectKindSpec{name: "expense_request"}],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: "expense_request",
          initial_state: :submitted,
          terminal_states: [:approved],
          transitions: [
            %{
              from: :submitted,
              to: :processing,
              trigger: {:execution_requested, "expense_capture"}
            },
            %{
              from: :processing,
              to: :approved,
              trigger: {:execution_completed, "expense_capture"}
            }
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: "expense_capture",
          placement_ref: :local_runner,
          runtime_class: :session,
          workspace_policy: %{
            strategy: :per_subject,
            root_ref: "expense_capture_workspaces"
          },
          sandbox_policy_ref: "expense_capture_sandbox",
          prompt_refs: ["expense_capture_prompt"]
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: "expense_queue", subject_kinds: ["expense_request"]}
      ]
    }

    compiled_pack =
      case Compiler.compile(manifest) do
        {:ok, compiled_pack} ->
          compiled_pack

        {:error, errors} ->
          raise "failed to compile app-kit operational proof pack: #{inspect(errors)}"
      end

    compiled_pack
    |> MezzanineConfigRegistry.register_pack!()
    |> PackRegistration.activate()
    |> case do
      {:ok, registration} ->
        registration

      {:error, error} ->
        raise "failed to activate app-kit operational proof pack: #{inspect(error)}"
    end
  end

  defp activate_governed_workload_registration! do
    manifest = %Manifest{
      pack_slug: "stack_lab_service_ops",
      version: "1",
      migration_strategy: :additive,
      profile_slots:
        ProfileSlots.default(
          source_profile_ref: :linear_service_task,
          runtime_profile_ref: :codex_session,
          tool_scope_ref: :coding_ops_v1,
          evidence_profile_ref: :github_pr_plus_workpad,
          publication_profile_ref: :service_publication,
          review_profile_ref: :human_operator,
          projection_profile_ref: :coding_ops_projection_v1
        ),
      subject_kind_specs: [%SubjectKindSpec{name: "service_task"}],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: "service_task",
          initial_state: :submitted,
          terminal_states: [:completed, :rejected, :expired],
          transitions: [
            %{
              from: :submitted,
              to: :awaiting_review,
              trigger: {:execution_completed, "service_operations"}
            },
            %{
              from: :submitted,
              to: :retry_submission,
              trigger: {:execution_failed, "service_operations"}
            },
            %{from: :retry_submission, to: :submitted, trigger: :auto},
            %{
              from: :awaiting_review,
              to: :completed,
              trigger: {:decision_made, "operator_review", :accept}
            },
            %{
              from: :awaiting_review,
              to: :rejected,
              trigger: {:decision_made, "operator_review", :reject}
            },
            %{
              from: :awaiting_review,
              to: :expired,
              trigger: {:decision_made, "operator_review", :expired}
            }
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: "service_operations",
          placement_ref: :local_default,
          runtime_class: :session,
          workspace_policy: %{
            strategy: :per_subject,
            root_ref: "service_operations_workspaces"
          },
          sandbox_policy_ref: "service_operations_sandbox",
          prompt_refs: ["service_operations_prompt"]
        }
      ],
      decision_specs: [
        %DecisionSpec{
          decision_kind: :operator_review,
          description: "Operator review gate for governed coding operations",
          trigger: {:after_execution_completed, "service_operations"},
          authorized_actors: [:operator],
          allowed_decisions: [:accept, :reject, :expired],
          required_within_hours: 24
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: "operator_queue", subject_kinds: ["service_task"]}
      ]
    }

    compiled_pack =
      case Compiler.compile(manifest) do
        {:ok, compiled_pack} ->
          compiled_pack

        {:error, errors} ->
          raise "failed to compile governed workload proof pack: #{inspect(errors)}"
      end

    compiled_pack
    |> MezzanineConfigRegistry.register_pack!()
    |> PackRegistration.activate()
    |> case do
      {:ok, registration} ->
        registration

      {:error, error} ->
        raise "failed to activate governed workload proof pack: #{inspect(error)}"
    end
  end

  defp governed_workload_fixture_stack(tenant_id) do
    {:ok, bootstrap} =
      Installations.ensure_runtime_profile(tenant_id, %{
        program: %{
          slug: "stack_lab_service_ops",
          name: "StackLab Service Ops",
          product_family: "stack_lab",
          configuration: %{},
          metadata: %{}
        },
        policy_bundle: %{
          name: "default_coding_ops",
          version: "1.0.0",
          policy_kind: :workflow_md,
          source_ref: "WORKFLOW.md",
          body: workflow_body(true),
          metadata: %{}
        },
        work_class: %{
          name: "service_operations",
          kind: "service_task",
          intake_schema: %{"required" => ["title"]},
          default_review_profile: %{"required" => true},
          default_run_profile: %{"runtime" => "session"}
        },
        placement_profile: %{
          profile_id: "local_default",
          strategy: "affinity",
          target_selector: %{"runtime_driver" => "jido_session"},
          runtime_preferences: %{"locality" => "same_region"},
          workspace_policy: %{},
          metadata: %{}
        }
      })

    %{program: bootstrap.program, work_class: bootstrap.work_class}
  end

  defp governed_workload_install_template! do
    {:ok, template} =
      InstallTemplate.new(%{
        template_key: "stack-lab-service-ops",
        pack_slug: "stack_lab_service_ops",
        pack_version: "1",
        default_bindings: %{
          "execution_bindings" => %{
            "service_operations" => %{"placement_ref" => "local_default"}
          }
        },
        metadata: %{"managed_by" => "stack_lab", "contract" => "GovernedAgentWorkloadContract.v1"}
      })

    template
  end

  defp governed_workload_attrs do
    %{
      workload_ref: "workloads/stack-lab-service-ops",
      profile_id: "profiles/stack_lab/local_default",
      ingress_ref: "app_kit_operator_surface_via_mezzanine_bridge",
      work_class_ref: "stack_lab/work_classes/service_operations",
      pack_ref: "mezzanine/packs/stack_lab_service_ops@1",
      subject_kind: "service_task",
      lifecycle_states: [
        :submitted,
        :retry_submission,
        :awaiting_review,
        :completed,
        :rejected,
        :expired
      ],
      review_gate_ref: "stack_lab/review_gates/operator_review",
      tenant_count: 1,
      agent_count: 1,
      runs_per_agent: 1,
      max_concurrency: 1,
      synthetic_operator_driver_ref: "operator_script_in_app_kit"
    }
  end

  defp bare_asm_substitute_attrs do
    Map.merge(governed_workload_attrs(), %{
      synthetic_operator_driver_ref: "task_async_stream_of_asm_calls",
      driver: :task_async_stream,
      execution_mode: :bare_asm_calls
    })
  end

  defp governed_workload_summary(workload) do
    %{
      contract_name: workload.contract_name,
      ingress_ref: workload.ingress_ref,
      synthetic_operator_driver_ref: workload.synthetic_operator_driver_ref,
      work_class_ref: workload.work_class_ref,
      pack_ref: workload.pack_ref,
      subject_kind: workload.subject_kind,
      lifecycle_states: workload.lifecycle_states,
      review_gate_ref: workload.review_gate_ref,
      script_surfaces: Enum.map(RunGovernance.operator_script(workload), & &1.surface)
    }
  end

  defp operational_fixture_stack(tenant_id, opts \\ []) do
    review_required? = Keyword.get(opts, :review_required?, true)

    {:ok, bootstrap} =
      Installations.ensure_runtime_profile(tenant_id, %{
        program: %{
          slug: "app-kit-operational-#{System.unique_integer([:positive])}",
          name: "AppKit Operational Program",
          product_family: "operator_stack",
          configuration: %{},
          metadata: %{}
        },
        policy_bundle: %{
          name: "default",
          version: "1.0.0",
          policy_kind: :workflow_md,
          source_ref: "WORKFLOW.md",
          body: workflow_body(review_required?),
          metadata: %{}
        },
        work_class: %{
          name: "service_task_#{System.unique_integer([:positive])}",
          kind: "service_task",
          intake_schema: %{"required" => ["title"]},
          default_review_profile: %{"required" => review_required?},
          default_run_profile: %{"runtime" => "session"}
        },
        placement_profile: %{
          profile_id: "local_default",
          strategy: "affinity",
          target_selector: %{"runtime_driver" => "jido_session"},
          runtime_preferences: %{"locality" => "same_region"},
          workspace_policy: %{},
          metadata: %{}
        }
      })

    %{program: bootstrap.program, work_class: bootstrap.work_class}
  end

  defp seed_trace_ledger(installation_id, subject_id, trace_id) do
    installation = fetch_installation!(installation_id)
    execution_id = Ecto.UUID.generate()
    now = ~U[2026-04-16 11:00:00Z]
    trace_id = normalize_trace_id(trace_id)

    {1, _} =
      ExecutionRepo.insert_all("execution_records", [
        %{
          id: dump_uuid!(execution_id),
          tenant_id: installation.tenant_id,
          installation_id: installation_id,
          subject_id: dump_uuid!(subject_id),
          recipe_ref: "expense_capture",
          compiled_pack_revision: installation.compiled_pack_revision || 1,
          binding_snapshot: %{"placement_ref" => "local_docker"},
          dispatch_envelope: %{"capability" => "finance.expense.capture"},
          intent_snapshot: %{
            "recipe_ref" => "expense_capture",
            "subject_id" => subject_id,
            "trace_id" => trace_id
          },
          submission_dedupe_key: "submission-key-#{execution_id}",
          trace_id: trace_id,
          causation_id: execution_id,
          dispatch_state: "accepted",
          dispatch_attempt_count: 0,
          next_dispatch_at: now,
          submission_ref: %{"id" => "submission-#{execution_id}"},
          lower_receipt: %{"run_id" => "lower-run-#{execution_id}"},
          last_dispatch_error_payload: %{},
          row_version: 1,
          inserted_at: now,
          updated_at: now
        }
      ])

    {1, _} =
      AuditRepo.insert_all("audit_facts", [
        %{
          id: dump_uuid!(Ecto.UUID.generate()),
          installation_id: installation_id,
          subject_id: subject_id,
          execution_id: execution_id,
          trace_id: trace_id,
          causation_id: execution_id,
          fact_kind: "execution_dispatched",
          actor_ref: %{kind: :scheduler},
          payload: %{dispatch_state: "accepted"},
          occurred_at: now,
          inserted_at: now,
          updated_at: now
        }
      ])

    {1, _} =
      AuditRepo.insert_all("execution_lineage_records", [
        %{
          id: dump_uuid!(Ecto.UUID.generate()),
          trace_id: trace_id,
          causation_id: execution_id,
          tenant_id: installation.tenant_id,
          installation_id: installation_id,
          subject_id: subject_id,
          execution_id: execution_id,
          ji_submission_key: "submission-#{execution_id}",
          lower_run_id: "lower-run-#{execution_id}",
          lower_attempt_id: "attempt-#{execution_id}",
          artifact_refs: ["artifact-#{execution_id}"],
          inserted_at: now,
          updated_at: now
        }
      ])

    {1, _} =
      DecisionsRepo.insert_all("decision_records", [
        %{
          id: dump_uuid!(Ecto.UUID.generate()),
          installation_id: installation_id,
          subject_id: dump_uuid!(subject_id),
          execution_id: dump_uuid!(execution_id),
          decision_kind: "human_review_required",
          lifecycle_state: "pending",
          required_by: ~U[2026-04-20 00:00:00Z],
          trace_id: trace_id,
          causation_id: execution_id,
          row_version: 1,
          inserted_at: ~U[2026-04-16 11:01:00Z],
          updated_at: ~U[2026-04-16 11:01:00Z]
        }
      ])

    {1, _} =
      EvidenceRepo.insert_all("evidence_records", [
        %{
          id: dump_uuid!(Ecto.UUID.generate()),
          installation_id: installation_id,
          subject_id: dump_uuid!(subject_id),
          execution_id: dump_uuid!(execution_id),
          evidence_kind: "run_log",
          collector_ref: "jido_run_output",
          content_ref: "artifact://#{execution_id}",
          status: "collected",
          metadata: %{"size" => 128},
          collected_at: ~U[2026-04-16 11:02:00Z],
          trace_id: trace_id,
          causation_id: execution_id,
          row_version: 1,
          inserted_at: ~U[2026-04-16 11:02:00Z],
          updated_at: ~U[2026-04-16 11:02:00Z]
        }
      ])

    %{execution_id: execution_id}
  end

  defp lower_backed_dispatch(
         %RequestContext{} = context,
         installation_ref,
         subject_ref,
         run_result
       ) do
    recipe_ref = "expense_capture"
    installation = fetch_installation!(installation_ref.id)
    run_intent = hydrate_run_intent!(run_result.payload.run_intent)
    binding_snapshot = binding_snapshot_for(installation, recipe_ref)

    if run_result.payload.review_required do
      raise "app_kit lower-backed proof unexpectedly required review"
    end

    {:ok, dispatched_execution} =
      ExecutionRecord.dispatch(%{
        tenant_id: installation.tenant_id,
        installation_id: installation.id,
        subject_id: subject_ref.id,
        recipe_ref: recipe_ref,
        compiled_pack_revision: installation.compiled_pack_revision,
        binding_snapshot: binding_snapshot,
        dispatch_envelope: %{
          "capability" => run_intent.capability,
          "run_request_id" => run_intent.intent_id
        },
        submission_dedupe_key:
          "#{installation.id}:#{subject_ref.id}:#{recipe_ref}:#{installation.compiled_pack_revision}",
        trace_id: context.trace_id,
        causation_id: "cause:#{context.trace_id}",
        actor_ref: %{kind: :scheduler}
      })

    bridge = InvocationBridge.new!(downstream: InProcessInvocationDownstream)

    dispatch =
      LowerGatewayStub.with_handlers(
        %{
          dispatch: fn [claimed] ->
            validate_lower_backed_claim!(
              claimed,
              installation,
              subject_ref.id,
              recipe_ref,
              binding_snapshot
            )

            dispatch_through_citadel!(bridge, run_intent, context, claimed, binding_snapshot)
          end
        },
        fn ->
          dispatch = DispatchProbe.perform_dispatch!(dispatched_execution.id)

          if dispatch.classification not in [:accepted, :terminal_rejection] do
            raise "unexpected lower-backed dispatch classification: #{inspect(dispatch)}"
          end

          dispatch
        end
      )

    transport_result = await_transport_result!()

    {:ok,
     %{
       classification: dispatch.classification,
       execution: dispatch.execution,
       job_status: dispatch.job_status,
       gateway: Map.get(transport_result, :gateway),
       runtime_inputs: Map.get(transport_result, :runtime_inputs),
       acceptance: transport_acceptance(dispatch.classification, transport_result),
       rejection: transport_rejection(dispatch.classification, transport_result)
     }}
  end

  defp dispatch_through_citadel!(
         %InvocationBridge{} = bridge,
         %RunIntent{} = run_intent,
         %RequestContext{} = context,
         claimed,
         binding_snapshot
       ) do
    compile_attrs = %{
      tenant_id: context.tenant_ref.id,
      installation_id: claimed.installation_id,
      installation_revision: claimed.compiled_pack_revision,
      compiled_pack_revision: claimed.compiled_pack_revision,
      actor_ref: context.actor_ref.id,
      actor_id: context.actor_ref.id,
      subject_id: claimed.subject_id,
      execution_id: claimed.execution_id,
      request_trace_id: context.trace_id,
      substrate_trace_id: claimed.trace_id,
      idempotency_key: claimed.submission_dedupe_key,
      submission_dedupe_key: claimed.submission_dedupe_key,
      environment: "stage4",
      scope_kind: "work_object",
      target_kind: "runtime_target",
      target_id: binding_snapshot["placement_ref"] || "workspace_runtime",
      service_id: "workspace_runtime",
      boundary_class: "workspace_session",
      execution_intent: %{
        "command" => run_intent.capability,
        "args" => [claimed.subject_id],
        "environment" => %{"TRACE_ID" => claimed.trace_id},
        "extensions" => %{
          "run_request_id" => run_intent.intent_id,
          "submission_dedupe_key" => claimed.submission_dedupe_key
        }
      },
      allowed_operations: [run_intent.capability],
      execution_intent_family: "process",
      downstream_scope: "work:#{claimed.subject_id}",
      workspace_mutability: "read_write",
      objective: "Execute #{run_intent.capability} for work #{claimed.subject_id}"
    }

    {:ok, compiled} =
      SubstrateIngress.compile_run_intent(run_intent, compile_attrs, [policy_pack()], [])

    lower_intent = compiled.lower_intent

    case InvocationBridge.submit(
           bridge,
           lower_intent.invocation_request,
           lower_intent.outbox_entry
         ) do
      {:accepted, acceptance, _bridge} ->
        {:accepted, acceptance_payload(lower_intent, acceptance, claimed)}

      {:rejected, rejection, _bridge} ->
        {:rejected, rejection_payload(rejection)}

      {:error, reason, _bridge} ->
        {:error, {:retryable, reason, %{"reason" => inspect(reason)}}}
    end
  end

  defp acceptance_payload(lower_intent, acceptance, claimed) do
    %{
      "submission_ref" => %{
        "id" => lower_intent.entry_id,
        "status" => Atom.to_string(acceptance.status),
        "submission_key" => acceptance.submission_key,
        "submission_receipt_ref" => acceptance.submission_receipt_ref
      },
      "lower_receipt" => %{
        "state" => "accepted",
        "ji_submission_key" => acceptance.submission_key,
        "submission_receipt_ref" => acceptance.submission_receipt_ref,
        "run_id" => "run-#{claimed.execution_id}",
        "attempt_id" => "attempt-#{claimed.execution_id}",
        "artifact_id" => "artifact-#{claimed.execution_id}",
        "artifact_ids" => ["artifact-#{claimed.execution_id}"]
      }
    }
  end

  defp rejection_payload(rejection) do
    %{
      "reason" => Map.get(rejection, :reason_code, "citadel_rejected"),
      "rejection_family" => rejection |> Map.get(:rejection_family) |> to_string(),
      "summary" => Map.get(rejection, :summary)
    }
  end

  defp hydrate_run_intent!(%RunIntent{} = run_intent), do: run_intent

  defp hydrate_run_intent!(run_intent) when is_map(run_intent) do
    RunIntent.new!(%{
      intent_id: map_value!(run_intent, :intent_id),
      program_id: map_value!(run_intent, :program_id),
      work_id: map_value!(run_intent, :work_id),
      capability: map_value!(run_intent, :capability),
      runtime_class:
        run_intent
        |> optional_map_value(:runtime_class)
        |> normalize_runtime_class(),
      placement: optional_map_value(run_intent, :placement, %{}),
      grant_profile: optional_map_value(run_intent, :grant_profile, %{}),
      input: optional_map_value(run_intent, :input, %{}),
      metadata: optional_map_value(run_intent, :metadata, %{})
    })
  end

  defp hydrate_run_intent!(other),
    do: raise("expected a surfaced run intent, got: #{inspect(other)}")

  defp fetch_installation!(installation_id) do
    {:ok, %Installation{} = installation} = Ash.get(Installation, installation_id)
    installation
  end

  defp binding_snapshot_for(installation, recipe_ref) do
    installation
    |> Map.fetch!(:binding_config)
    |> get_in(["execution_bindings", recipe_ref])
    |> Map.take(["placement_ref", "execution_params", "connector_bindings"])
  end

  defp validate_lower_backed_claim!(
         claimed,
         installation,
         subject_id,
         recipe_ref,
         binding_snapshot
       ) do
    if claimed.installation_id != installation.id do
      raise "app_kit lower-backed proof claimed the wrong installation"
    end

    if claimed.subject_id != subject_id do
      raise "app_kit lower-backed proof claimed the wrong subject"
    end

    if claimed.compiled_pack_revision != installation.compiled_pack_revision do
      raise "app_kit lower-backed proof lowered with the wrong compiled-pack revision"
    end

    if claimed.binding_snapshot != binding_snapshot do
      raise "app_kit lower-backed proof lowered with the wrong binding snapshot"
    end

    expected_submission_key =
      "#{installation.id}:#{subject_id}:#{recipe_ref}:#{installation.compiled_pack_revision}"

    if claimed.submission_dedupe_key != expected_submission_key do
      raise "app_kit lower-backed proof lowered with the wrong submission dedupe key"
    end
  end

  defp await_transport_result! do
    receive do
      {:stack_lab_brain_ingress_result,
       %{
         result: :accepted,
         acceptance: acceptance,
         submission_key: _submission_key,
         gateway: gateway,
         runtime_inputs: runtime_inputs
       }} ->
        %{
          result: :accepted,
          acceptance: acceptance,
          gateway: gateway,
          runtime_inputs: runtime_inputs
        }

      {:stack_lab_brain_ingress_result,
       %{result: :rejected, rejection: rejection, submission_key: _submission_key}} ->
        %{result: :rejected, rejection: rejection}
    after
      5_000 -> raise "timed out waiting for lower-backed transport result"
    end
  end

  defp transport_acceptance(:accepted, %{result: :accepted, acceptance: acceptance}),
    do: acceptance

  defp transport_acceptance(:terminal_rejection, %{result: :rejected}), do: nil

  defp transport_acceptance(classification, transport_result) do
    raise """
    unexpected lower-backed transport acceptance state:
    classification=#{inspect(classification)}
    transport_result=#{inspect(transport_result)}
    """
  end

  defp transport_rejection(:terminal_rejection, %{result: :rejected, rejection: rejection}),
    do: rejection

  defp transport_rejection(:accepted, %{result: :accepted}), do: nil

  defp transport_rejection(classification, transport_result) do
    raise """
    unexpected lower-backed transport rejection state:
    classification=#{inspect(classification)}
    transport_result=#{inspect(transport_result)}
    """
  end

  defp rejection_reason(nil), do: nil

  defp rejection_reason(rejection) do
    case Map.get(rejection, :reason_code) do
      nil -> nil
      reason -> to_string(reason)
    end
  end

  defp lower_receipt_proof!(
         %RequestContext{} = context,
         installation_id,
         execution_id,
         submission_key
       ) do
    direct_receipt =
      case LowerFacts.fetch_submission_receipt(
             tenant_scope!(context, installation_id),
             submission_key
           ) do
        {:ok, receipt} ->
          receipt

        {:error, reason} ->
          raise "lower-backed proof could not fetch a direct submission receipt: #{inspect(reason)}"
      end

    read_intent =
      ReadIntent.new!(%{
        intent_id: "stack-lab:lower-receipt:#{execution_id}",
        read_type: :lower_fact,
        subject: %{
          actor_id: context.actor_ref.id,
          tenant_id: context.tenant_ref.id,
          installation_id: installation_id,
          execution_id: execution_id
        },
        query: %{operation: :fetch_submission_receipt}
      })

    bridged_receipt =
      case IntegrationBridge.dispatch_read(read_intent) do
        {:ok, %{result: receipt}} -> receipt
        {:error, reason} -> raise "lower-backed proof bridge read failed: #{inspect(reason)}"
      end

    %{
      direct_submission_key: direct_receipt.submission_key,
      bridged_submission_key: bridged_receipt.submission_key,
      receipt_ref: direct_receipt.submission_receipt_ref
    }
  end

  def handle_observability_telemetry(event, measurements, metadata, test_pid) do
    send(test_pid, {:observability_telemetry, event, measurements, metadata})
  end

  defp attach_observability_telemetry!(handler_id, test_pid) do
    :ok =
      :telemetry.attach_many(
        handler_id,
        [
          Telemetry.event_name(:unified_trace_assembled),
          ClaimCheckTelemetry.event(:stage),
          Citadel.ObservabilityContract.Telemetry.event_name(:trace_publication_failure),
          [:lower_gateway, :trace_id, :backfill],
          [:mezzanine, :archival, :run],
          [:mezzanine, :archival, :verified],
          [:mezzanine, :archival, :rows_removed]
        ],
        &__MODULE__.handle_observability_telemetry/4,
        test_pid
      )

    :ok
  end

  defp collect_observability_telemetry!(acc \\ []) do
    receive do
      {:observability_telemetry, event, measurements, metadata} ->
        collect_observability_telemetry!([
          %{event: event, measurements: measurements, metadata: metadata} | acc
        ])
    after
      100 -> Enum.reverse(acc)
    end
  end

  defp summarize_observability_telemetry!(events) when is_list(events) do
    %{
      app_kit_unified_trace:
        fetch_events!(events, Telemetry.event_name(:unified_trace_assembled)),
      claim_check_stage: fetch_events!(events, ClaimCheckTelemetry.event(:stage)),
      execution_plane_backfill: fetch_one_event!(events, [:lower_gateway, :trace_id, :backfill]),
      citadel_trace_publication_failure:
        fetch_one_event!(
          events,
          Citadel.ObservabilityContract.Telemetry.event_name(:trace_publication_failure)
        ),
      archival_run: fetch_one_event!(events, [:mezzanine, :archival, :run]),
      archival_verified: fetch_one_event!(events, [:mezzanine, :archival, :verified]),
      archival_rows_removed: fetch_one_event!(events, [:mezzanine, :archival, :rows_removed])
    }
  end

  defp fetch_events!(events, event_name) do
    matched = Enum.filter(events, &(&1.event == event_name))

    if matched == [] do
      raise "missing observability telemetry for #{inspect(event_name)}"
    end

    matched
  end

  defp fetch_one_event!(events, event_name) do
    fetch_events!(events, event_name)
    |> hd()
  end

  defp collect_lower_fetch_messages!(acc \\ []) do
    receive do
      {:lower_fetch_submission_receipt, submission_key} ->
        collect_lower_fetch_messages!([{:fetch_submission_receipt, submission_key} | acc])

      {:lower_fetch_submission_receipt, tenant_id, submission_key} ->
        collect_lower_fetch_messages!([
          {:fetch_submission_receipt, tenant_id, submission_key} | acc
        ])

      {:lower_fetch_run, run_id} ->
        collect_lower_fetch_messages!([{:fetch_run, run_id} | acc])

      {:lower_fetch_run, tenant_id, run_id} ->
        collect_lower_fetch_messages!([{:fetch_run, tenant_id, run_id} | acc])

      {:lower_events, run_id} ->
        collect_lower_fetch_messages!([{:events, run_id} | acc])

      {:lower_events, tenant_id, run_id} ->
        collect_lower_fetch_messages!([{:events, tenant_id, run_id} | acc])

      {:lower_attempts, run_id} ->
        collect_lower_fetch_messages!([{:attempts, run_id} | acc])

      {:lower_attempts, tenant_id, run_id} ->
        collect_lower_fetch_messages!([{:attempts, tenant_id, run_id} | acc])

      {:lower_run_artifacts, run_id} ->
        collect_lower_fetch_messages!([{:run_artifacts, run_id} | acc])

      {:lower_run_artifacts, tenant_id, run_id} ->
        collect_lower_fetch_messages!([{:run_artifacts, tenant_id, run_id} | acc])
    after
      50 -> Enum.reverse(acc)
    end
  end

  defp enrich_subject_trace_graph!(installation_id, subject_id, execution_id, trace_id) do
    decision_id = Ecto.UUID.generate()
    evidence_id = Ecto.UUID.generate()
    audit_fact_id = Ecto.UUID.generate()
    now = ~U[2026-04-16 11:00:00Z]

    ObjectsRepo.query!(
      """
      UPDATE subject_records
      SET lifecycle_state = 'approved',
          status = 'completed',
          terminal_at = $3,
          status_updated_at = $4,
          updated_at = $4
      WHERE installation_id = $1
        AND id = $2::uuid
      """,
      [installation_id, dump_uuid!(subject_id), @scenario_19_terminal_at, now]
    )

    ExecutionRepo.query!(
      """
      UPDATE execution_records
      SET dispatch_state = 'completed',
          updated_at = $3
      WHERE installation_id = $1
        AND id = $2::uuid
      """,
      [installation_id, dump_uuid!(execution_id), now]
    )

    DecisionsRepo.query!(
      """
      INSERT INTO decision_records (
        id,
        installation_id,
        subject_id,
        execution_id,
        decision_kind,
        lifecycle_state,
        decision_value,
        trace_id,
        row_version,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2, $3::uuid, $4::uuid, 'review', 'resolved', 'accept', $5, 1, $6, $6)
      """,
      [
        dump_uuid!(decision_id),
        installation_id,
        dump_uuid!(subject_id),
        dump_uuid!(execution_id),
        trace_id,
        now
      ]
    )

    EvidenceRepo.query!(
      """
      INSERT INTO evidence_records (
        id,
        installation_id,
        subject_id,
        execution_id,
        evidence_kind,
        status,
        metadata,
        trace_id,
        row_version,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2, $3::uuid, $4::uuid, 'artifact', 'verified', '{}'::jsonb, $5, 1, $6, $6)
      """,
      [
        dump_uuid!(evidence_id),
        installation_id,
        dump_uuid!(subject_id),
        dump_uuid!(execution_id),
        trace_id,
        now
      ]
    )

    AuditRepo.query!(
      """
      INSERT INTO audit_facts (
        id,
        installation_id,
        subject_id,
        execution_id,
        decision_id,
        evidence_id,
        trace_id,
        fact_kind,
        actor_ref,
        payload,
        occurred_at,
        inserted_at,
        updated_at
      )
      VALUES ($1::uuid, $2, $3::uuid, $4::uuid, $5::uuid, $6::uuid, $7, 'execution_completed', '{}'::jsonb, '{}'::jsonb, $8, $8, $8)
      """,
      [
        dump_uuid!(audit_fact_id),
        installation_id,
        dump_uuid!(subject_id),
        dump_uuid!(execution_id),
        dump_uuid!(decision_id),
        dump_uuid!(evidence_id),
        trace_id,
        now
      ]
    )

    %{
      decision_id: decision_id,
      evidence_id: evidence_id,
      audit_fact_id: audit_fact_id
    }
  end

  defp archived_pivot_summaries!(installation_id, pivots) when is_map(pivots) do
    Map.new(pivots, fn {pivot, pivot_id} ->
      {:ok, trace} =
        OperatorQueryService.get_archived_unified_trace_by_pivot(%{
          installation_id: installation_id,
          pivot: pivot,
          pivot_id: pivot_id
        })

      {pivot,
       %{
         trace_id: trace.trace_id,
         archived_manifest_ref: trace.metadata.archived_manifest_ref,
         archive_pivot: trace.metadata.archive_pivot,
         step_sources:
           trace.steps
           |> Enum.map(& &1.source)
           |> Enum.map(&to_string/1),
         staleness_classes:
           trace.steps
           |> Enum.map(& &1.staleness_class)
           |> Enum.map(&to_string/1)
           |> Enum.uniq()
           |> Enum.sort(),
         join_keys: trace.join_keys
       }}
    end)
  end

  defp archived_pivot_error!(installation_id, pivot, pivot_id) do
    case OperatorQueryService.get_archived_unified_trace_by_pivot(%{
           installation_id: installation_id,
           pivot: pivot,
           pivot_id: pivot_id
         }) do
      {:error, reason} ->
        reason

      {:ok, trace} ->
        raise "expected archived pivot lookup to fail closed, got: #{inspect(trace)}"
    end
  end

  defp emit_execution_plane_backfill!(trace_id, tenant_id) do
    lineage =
      ExecutionPlane.Contracts.normalize_lineage!(
        %{
          tenant_id: tenant_id,
          request_id: trace_id,
          decision_id: "scenario19-decision",
          boundary_session_id: "scenario19-boundary-session",
          attempt_ref: "attempt://scenario19/#{trace_id}",
          route_id: "scenario19-route",
          idempotency_key: "scenario19-idempotency"
        },
        @scenario_19_execution_plane_required_keys
      )

    envelope =
      ExecutionPlane.LaneSupport.build_envelope(
        "scenario19",
        "process",
        "scenario19.execute",
        lineage,
        requested_capabilities: ["scenario19.execute"]
      )

    route =
      ExecutionPlane.LaneSupport.build_route(
        "scenario19",
        "process",
        "process",
        "local",
        %{"execution_surface" => %{"surface_kind" => "local_subprocess"}},
        30_000,
        lineage
      )

    %{
      lineage_trace_id: lineage.trace_id,
      envelope_trace_id: envelope.trace_id,
      route_trace_id: route.lineage.trace_id,
      request_id: lineage.request_id,
      route_id: lineage.route_id
    }
  end

  defp emit_citadel_trace_failure!(trace_id, tenant_id, request_id) do
    {:ok, publisher} =
      TracePublisher.start_link(
        trace_port: FailingTracePort,
        batch_size: 1,
        flush_interval_ms: 1
      )

    Process.unlink(publisher)

    envelope =
      TraceEnvelope.new!(%{
        trace_envelope_id: "scenario19-failure-#{System.unique_integer([:positive])}",
        record_kind: :event,
        family: "scenario19",
        name: "citadel.scenario19.trace_join_probe",
        phase: "post_commit",
        trace_id: trace_id,
        tenant_id: tenant_id,
        session_id: "scenario19/session",
        request_id: request_id,
        decision_id: nil,
        snapshot_seq: 1,
        signal_id: nil,
        outbox_entry_id: nil,
        boundary_ref: "scenario19-boundary",
        span_id: nil,
        parent_span_id: nil,
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
        started_at: nil,
        finished_at: nil,
        status: "error",
        attributes: %{},
        extensions: %{}
      })

    :ok = TracePublisher.publish_trace(publisher, envelope)
    Process.sleep(50)
    GenServer.stop(publisher)
    :ok
  end

  defp assert_archived_hot_reads!(context, subject_ref, surface_opts, manifest_ref) do
    work_query_result =
      archived_surface_result!(
        "work-query",
        WorkSurface.get_subject(context, subject_ref, surface_opts),
        manifest_ref
      )

    operator_query_result =
      archived_surface_result!(
        "operator-status",
        OperatorSurface.subject_status(context, subject_ref, surface_opts),
        manifest_ref
      )

    assert_archived_result!("work-query", work_query_result, manifest_ref)
    assert_archived_result!("operator-status", operator_query_result, manifest_ref)

    %{
      work_query: work_query_result,
      operator_status: operator_query_result
    }
  end

  defp assert_archived_result!(label, result, manifest_ref) do
    if match?({:error, :archived, ^manifest_ref}, result) do
      :ok
    else
      raise "expected archived #{label} result, got: #{inspect(result)}"
    end
  end

  defp archived_surface_result!(
         _label,
         {:error, %SurfaceError{code: code, details: %{manifest_ref: manifest_ref}}},
         manifest_ref
       )
       when code in [:archived, "archived"] do
    {:error, :archived, manifest_ref}
  end

  defp archived_surface_result!(label, result, manifest_ref) do
    raise "expected archived #{label} surface result for #{manifest_ref}, got: #{inspect(result)}"
  end

  @spec direct_submission_receipt_read!(ReadLease.t(), String.t()) :: SubmissionAcceptance.t()
  defp direct_submission_receipt_read!(%ReadLease{} = read_lease, submission_key)
       when is_binary(submission_key) do
    authorization_scope = authorization_scope!(read_lease)

    {:ok, _lease} =
      Leasing.authorize_read(
        authorization_scope,
        read_lease.lease_ref.id,
        read_lease.lease_token,
        :fetch_submission_receipt,
        repo: ExecutionRepo
      )

    case LowerFacts.fetch_submission_receipt(tenant_scope!(authorization_scope), submission_key) do
      {:ok, receipt} ->
        receipt

      {:error, reason} ->
        raise "direct leased lower read could not fetch a submission receipt: #{inspect(reason)}"
    end
  end

  @spec authorization_scope!(map()) :: AuthorizationScope.t()
  defp authorization_scope!(lease) do
    lease
    |> Map.get(:authorization_scope)
    |> AuthorizationScope.new!()
  end

  @spec tenant_scope!(RequestContext.t(), String.t()) :: TenantScope.t()
  defp tenant_scope!(%RequestContext{} = context, installation_id) do
    TenantScope.new!(
      tenant_id: context.tenant_ref.id,
      installation_id: installation_id,
      actor_ref: Map.from_struct(context.actor_ref),
      trace_id: context.trace_id,
      authorized_at: DateTime.utc_now()
    )
  end

  @spec tenant_scope!(AuthorizationScope.t()) :: TenantScope.t()
  defp tenant_scope!(%AuthorizationScope{} = authorization_scope) do
    TenantScope.new!(
      tenant_id: authorization_scope.tenant_id,
      installation_id: authorization_scope.installation_id,
      actor_ref: authorization_scope.actor_ref,
      trace_id: authorization_scope.trace_id,
      authorized_at: authorization_scope.authorized_at || DateTime.utc_now()
    )
  end

  defp emit_stream_invalidation_burst!(lease_id, count, max_concurrency) do
    1..count
    |> RuntimeProcesses.async_stream(
      fn index ->
        {:ok, [row]} =
          Leasing.invalidate_stream_attach_lease(
            lease_id,
            "disconnect_burst_#{index}",
            repo: ExecutionRepo,
            trace_id: "trace-stage24-burst-#{index}"
          )

        row
      end,
      max_concurrency: max_concurrency,
      timeout: 15_000,
      ordered: false
    )
    |> Enum.map(fn
      {:ok, row} -> row
      {:exit, reason} -> raise "stream invalidation burst failed: #{inspect(reason)}"
      {:error, reason} -> raise "stream invalidation burst failed: #{inspect(reason)}"
    end)
  end

  defp ensure_disconnect_window_elapsed!(started_at_ms, required_ms) do
    elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
    remaining_ms = max(required_ms - elapsed_ms, 0)

    if remaining_ms > 0 do
      Process.sleep(remaining_ms)
    end

    :ok
  end

  defp await_stream_attached!(lease_id, timeout_ms \\ 2_000) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_await_stream_attached(lease_id, deadline_ms)
  end

  defp await_stream_invalidated!(lease_id, timeout_ms) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_await_stream_invalidated(lease_id, deadline_ms)
  end

  defp ensure_no_stream_attached!(lease_id) do
    deadline_ms = System.monotonic_time(:millisecond) + 100
    do_ensure_no_stream_attached(lease_id, deadline_ms)
  end

  defp wait_for_stream_host_shutdown!(pid) when is_pid(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      2_000 ->
        Process.demonitor(ref, [:flush])
        raise "timed out waiting for stream host shutdown"
    end
  end

  defp contiguous_sequence?([]), do: true

  defp contiguous_sequence?(sequence_numbers) do
    sorted = Enum.sort(sequence_numbers)
    sorted == Enum.to_list(hd(sorted)..List.last(sorted))
  end

  defp do_await_stream_attached(lease_id, deadline_ms) do
    timeout_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {:stream_attached, ^lease_id, cursor} ->
        cursor

      _other ->
        do_await_stream_attached(lease_id, deadline_ms)
    after
      timeout_ms ->
        raise "timed out waiting for stream attach for #{inspect(lease_id)}"
    end
  end

  defp do_await_stream_invalidated(lease_id, deadline_ms) do
    timeout_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {:stream_invalidated, ^lease_id, reason, sequence_number} ->
        %{reason: reason, sequence_number: sequence_number}

      _other ->
        do_await_stream_invalidated(lease_id, deadline_ms)
    after
      timeout_ms ->
        raise "timed out waiting for stream invalidation for #{inspect(lease_id)}"
    end
  end

  defp do_ensure_no_stream_attached(lease_id, deadline_ms) do
    timeout_ms = max(deadline_ms - System.monotonic_time(:millisecond), 0)

    receive do
      {:stream_attached, ^lease_id, cursor} ->
        raise "unexpected stream attachment for invalidated lease #{inspect(lease_id)} at #{cursor}"

      _other ->
        do_ensure_no_stream_attached(lease_id, deadline_ms)
    after
      timeout_ms ->
        :ok
    end
  end

  defp normalize_read_error({:error, {:lease_invalidated, reason, sequence_number}}) do
    %{
      code: :lease_invalidated,
      reason: reason,
      sequence_number: sequence_number
    }
  end

  defp normalize_read_error(other), do: %{code: :unexpected_result, result: other}

  defp lease_invalidated?({:error, {:lease_invalidated, _reason, _sequence_number}}), do: true
  defp lease_invalidated?(_other), do: false

  defp leases_invalidated?(results) when is_list(results) do
    Enum.all?(results, &lease_invalidated?/1)
  end

  defp execution_trace_step!(unified_trace, execution_id) do
    unified_trace.steps
    |> Enum.find(fn step ->
      step.source == "execution_record" and trace_step_execution_id(step) == execution_id
    end)
    |> case do
      nil ->
        raise "unified trace missing execution_record step for #{execution_id}"

      step ->
        Map.fetch!(step, :payload)
    end
  end

  defp trace_step_execution_id(step) do
    payload = Map.fetch!(step, :payload)

    Map.get(step, :ref) || Map.get(step, "ref") || Map.get(payload, :execution_id) ||
      Map.get(payload, "execution_id")
  end

  defp ensure_store_local_ready!(storage_dir) do
    stop_store_local()
    File.rm_rf!(storage_dir)
    File.mkdir_p!(storage_dir)
    :ok = StoreLocal.configure_defaults!(storage_dir: storage_dir)

    _ = Application.ensure_all_started(:jido_integration_v2_store_local)

    case Process.whereis(StoreLocalServer) do
      nil ->
        raise "store_local server did not start"

      _pid ->
        :ok = StoreLocal.reset!()
    end
  end

  defp stop_store_local do
    case Application.stop(:jido_integration_v2_store_local) do
      :ok -> :ok
      {:error, {:not_started, :jido_integration_v2_store_local}} -> :ok
      {:error, {:not_started, _other_app}} -> :ok
      {:error, reason} -> raise "unable to stop store_local application: #{inspect(reason)}"
    end
  end

  defp lower_transport_config(listener, work_object_id, mode \\ :accepted)

  defp lower_transport_config(listener, _work_object_id, :scope_rejection) do
    %{
      listener: listener,
      submission_ledger: SubmissionLedger,
      submission_ledger_opts: [],
      scope_resolver: StaticScopeResolver,
      scope_resolver_opts: [mapping: %{}]
    }
  end

  defp lower_transport_config(listener, work_object_id, :accepted) do
    %{
      listener: listener,
      submission_ledger: SubmissionLedger,
      submission_ledger_opts: [],
      scope_resolver: StaticScopeResolver,
      scope_resolver_opts: [
        mapping: %{
          "workspace://work_object/#{work_object_id}" => RoundtripRuntime.workspace_root()
        }
      ]
    }
  end

  defp policy_pack do
    %{
      pack_id: "default",
      policy_version: "policy-stack-lab",
      policy_epoch: 1,
      priority: 0,
      selector: %{
        tenant_ids: [],
        scope_kinds: [],
        environments: [],
        default?: true,
        extensions: %{}
      },
      profiles: %{
        trust_profile: "baseline",
        approval_profile: "standard",
        egress_profile: "restricted",
        workspace_profile: "workspace",
        resource_profile: "standard",
        boundary_class: "workspace_session",
        extensions: %{}
      },
      rejection_policy: %{
        runtime_change_reason_codes: ["scope_changed"],
        governance_change_reason_codes: ["governance_changed"],
        denial_audit_reason_codes: ["policy_denied"],
        derived_state_reason_codes: [],
        extensions: %{}
      },
      extensions: %{}
    }
  end

  defp store_local_dir(case_name) do
    Path.join(
      System.tmp_dir!(),
      "stack_lab_app_kit_operational_surface_#{case_name}_#{System.unique_integer([:positive])}"
    )
  end

  defp map_value!(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      nil -> raise KeyError, key: key, term: map
      value -> value
    end
  end

  defp optional_map_value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end

  defp semantic_failure_carrier!(tenant_id, trace_id, execution_id) do
    {:ok, failure} =
      SemanticFailure.new(%{
        kind: :semantic_insufficient_context,
        tenant_id: tenant_id,
        semantic_session_id: "app-kit-operational-semantic-failure",
        causal_unit_id: execution_id,
        request_trace_id: trace_id,
        provenance: [%{"surface" => "stack_lab.app_kit_operational_surface"}],
        operator_message: "The lower-backed semantic command needs additional context."
      })

    failure
  end

  defp semantic_failure_carrier_value(failed_execution, key) do
    failed_execution
    |> map_value(:last_dispatch_error_payload)
    |> map_value("error")
    |> map_value("carrier")
    |> map_value(key)
  end

  defp map_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key)) || bounded_atom_key_value(map, key)
  end

  defp map_value(_value, _key), do: nil

  defp bounded_atom_key_value(map, key) when is_binary(key) do
    case Map.fetch(@bounded_lookup_atom_keys, key) do
      {:ok, atom_key} -> Map.get(map, atom_key)
      :error -> nil
    end
  end

  defp bounded_atom_key_value(_map, _key), do: nil

  defp normalize_runtime_class(value) when value in [:direct, :session, :stream], do: value
  defp normalize_runtime_class("direct"), do: :direct
  defp normalize_runtime_class("stream"), do: :stream
  defp normalize_runtime_class(_value), do: :session

  defp workflow_body(review_required?) do
    review_required_value = if(review_required?, do: "true", else: "false")
    review_decisions = if(review_required?, do: "1", else: "0")

    """
    ---
    tracker:
      kind: linear
      endpoint: https://api.linear.app/graphql
    run:
      profile: default_session
      runtime_class: session
      capability: linear.issue.execute
      target: linear-default
    approval:
      mode: manual
      reviewers:
        - ops_lead
      escalation_required: true
    retry:
      strategy: exponential
      max_attempts: 4
      initial_backoff_ms: 5000
      max_backoff_ms: 300000
    placement:
      profile_id: default-placement
      strategy: affinity
      target_selector:
        runtime_driver: jido_session
      runtime_preferences:
        locality: same_region
    workspace:
      root_mode: per_work
      sandbox_profile: strict
    review:
      required: #{review_required_value}
      required_decisions: #{review_decisions}
      gates:
        - operator
    capability_grants:
      - capability_id: linear.issue.read
        mode: allow
      - capability_id: linear.issue.update
        mode: allow
    ---
    # Operator Prompt
    """
  end

  defp dump_uuid!(value), do: Ecto.UUID.dump!(value)
end
