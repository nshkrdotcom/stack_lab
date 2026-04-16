defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface do
  @moduledoc false

  alias AppKit.Bridges.MezzanineBridge
  alias Ash
  alias Citadel.HostIngress
  alias Citadel.InvocationBridge
  alias Citadel.JidoIntegrationBridge
  alias Citadel.JidoIntegrationBridge.InvocationDownstream
  alias Jido.Integration.V2.BrainIngress.StaticScopeResolver
  alias Jido.Integration.V2.LowerFacts
  alias Jido.Integration.V2.StoreLocal
  alias Jido.Integration.V2.StoreLocal.Server, as: StoreLocalServer
  alias Jido.Integration.V2.StoreLocal.SubmissionLedger

  alias AppKit.Core.{
    ExecutionRef,
    InstallTemplate,
    OperatorActionRequest,
    PageRequest,
    RequestContext,
    RunRequest
  }

  alias AppKit.{
    InstallationSurface,
    OperatorSurface,
    ReviewSurface,
    WorkControl,
    WorkSurface
  }

  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.CitadelBridge.{AuthorityAssembler, RunIntentCompiler}
  alias Mezzanine.ConfigRegistry.Installation
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Decisions.Repo, as: DecisionsRepo
  alias Mezzanine.EvidenceLedger.Repo, as: EvidenceRepo
  alias Mezzanine.Execution.{Dispatcher, DispatchOutboxEntry, ExecutionRecord}
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.IntegrationBridge

  alias Mezzanine.Pack.{
    Compiler,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    ProjectionSpec,
    SubjectKindSpec
  }

  alias Mezzanine.Programs.{PolicyBundle, Program}
  alias Mezzanine.Work.WorkClass
  alias MezzanineOpsModel.Intent.{ReadIntent, RunIntent}

  alias StackLab.CitadelSpineHarness.{
    InProcessTransport,
    MezzanineOperationalStack,
    RoundtripRuntime,
    TransportRuntime
  }

  defmodule LowerFactsStub do
    @moduledoc false

    def operation_supported?(operation),
      do: operation in [:fetch_run, :events, :attempts, :run_artifacts]

    def fetch_run(run_id) do
      send(self(), {:lower_fetch_run, run_id})

      {:ok,
       %{
         run_id: run_id,
         status: :running,
         occurred_at: ~U[2026-04-16 11:10:00Z]
       }}
    end

    def events(run_id) do
      send(self(), {:lower_events, run_id})

      [
        %{
          event_id: "lower-event-#{run_id}",
          run_id: run_id,
          event_kind: "attempt.started",
          occurred_at: ~U[2026-04-16 11:11:00Z]
        }
      ]
    end

    def attempts(run_id) do
      send(self(), {:lower_attempts, run_id})

      [
        %{
          attempt_id: "attempt-#{run_id}",
          run_id: run_id,
          status: :running,
          occurred_at: ~U[2026-04-16 11:12:00Z]
        }
      ]
    end

    def run_artifacts(run_id) do
      send(self(), {:lower_run_artifacts, run_id})

      [
        %{
          artifact_id: "artifact-#{run_id}",
          run_id: run_id,
          kind: :log,
          occurred_at: ~U[2026-04-16 11:13:00Z]
        }
      ]
    end
  end

  @spec run_case(:install_ingest_review_trace | :lower_backed_command_trace) :: {:ok, map()}
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
           detail_active_run_id: subject_detail.current_execution_ref.id,
           detail_pending_reviews: Enum.map(subject_detail.pending_decision_refs, & &1.id)
         },
         control: %{
           state: run_result.state,
           run_id: run_result.payload.run_ref.run_id,
           review_unit_id: run_result.payload.review_unit_id
         },
         operator: %{
           lifecycle_state: operator_projection.lifecycle_state,
           current_execution_ref: operator_projection.current_execution_ref.id,
           chosen_action: chosen_action.action_ref.action_kind,
           applied_action: action_result.action_ref.action_kind,
           timeline_kinds: Enum.map(timeline, & &1.event_kind)
         },
         review: %{
           pending_ids_before: Enum.map(pending_reviews_before.entries, & &1.decision_ref.id),
           pending_ids_after: Enum.map(pending_reviews_after.entries, & &1.decision_ref.id),
           status_before: review_detail_before.status,
           status_after: review_detail_after.status,
           action_kind: review_action.action_ref.action_kind
         },
         trace: %{
           execution_id: execution_id,
           trace_id: unified_trace.trace_id,
           step_sources: Enum.map(unified_trace.steps, & &1.source)
         }
       }}
    end)
  end

  def run_case(:lower_backed_command_trace) do
    MezzanineOperationalStack.with_store(:app_kit_lower_backed_command_trace, fn _repo_config ->
      tenant_id = "tenant-app-kit-lower-backed"
      store_local_dir = store_local_dir(:app_kit_lower_backed_command_trace)

      previous_transport =
        Application.get_env(:citadel_jido_integration_bridge, :transport_module)

      RoundtripRuntime.flush_transport_messages()
      ensure_store_local_ready!(store_local_dir)
      :ok = JidoIntegrationBridge.put_transport_module(InProcessTransport)

      try do
        activate_fixture_registration!("1.0.1")

        %{program: program, work_class: work_class} =
          operational_fixture_stack(tenant_id, review_required?: false)

        {:ok, install_template} =
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

        surface_opts = surface_opts()

        install_context =
          request_context(
            tenant_id,
            "trace/app-kit/lower/install/#{System.unique_integer([:positive])}",
            %{program_id: program.id, work_class_id: work_class.id}
          )

        {:ok, install_result} =
          InstallationSurface.create_installation(install_context, install_template, surface_opts)

        installation_ref = install_result.installation_ref

        runtime_trace_id = "trace/app-kit/lower/runtime/#{System.unique_integer([:positive])}"

        with_installation_context =
          request_context(
            tenant_id,
            runtime_trace_id,
            %{program_id: program.id, work_class_id: work_class.id},
            installation_ref
          )

        {:ok, subject_ref} =
          WorkSurface.ingest_subject(
            with_installation_context,
            %{
              external_ref: "linear:ENG-801",
              title: "Lower-backed operational flow subject",
              payload: %{"issue_id" => "ENG-801"},
              source_kind: "linear"
            },
            surface_opts
          )

        :ok = TransportRuntime.put!(lower_transport_config(self(), subject_ref.id))

        {:ok, run_request} =
          RunRequest.new(%{
            subject_ref: subject_ref,
            recipe_ref: "expense_capture",
            params: %{"priority" => "high"}
          })

        {:ok, run_result} =
          WorkControl.start_run(with_installation_context, run_request, surface_opts)

        {:ok, lower_dispatch} =
          lower_backed_dispatch(
            with_installation_context,
            installation_ref,
            subject_ref,
            run_result
          )

        receipt_proof =
          lower_receipt_proof!(
            with_installation_context,
            installation_ref.id,
            lower_dispatch.execution.id,
            lower_dispatch.acceptance.submission_key
          )

        {:ok, execution_ref} =
          ExecutionRef.new(%{
            id: lower_dispatch.execution.id,
            subject_ref: subject_ref,
            recipe_ref: "expense_capture",
            dispatch_state: lower_dispatch.execution.dispatch_state
          })

        {:ok, unified_trace} =
          OperatorSurface.get_unified_trace(
            with_installation_context,
            execution_ref,
            Keyword.merge(
              surface_opts,
              lower_operations: [:fetch_submission_receipt]
            )
          )

        {:ok,
         %{
           case: :lower_backed_command_trace,
           tenant_id: tenant_id,
           installation: %{
             created_status: install_result.status,
             installation_id: installation_ref.id,
             pack_slug: installation_ref.pack_slug
           },
           work: %{
             subject_id: subject_ref.id,
             run_id: run_result.payload.run_ref.run_id,
             state: run_result.state
           },
           dispatch: %{
             execution_id: lower_dispatch.execution.id,
             classification: lower_dispatch.classification,
             outbox_status: lower_dispatch.outbox.status,
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
      after
        :ok = TransportRuntime.reset!()
        stop_store_local()
        File.rm_rf!(store_local_dir)

        if is_nil(previous_transport) do
          Application.delete_env(:citadel_jido_integration_bridge, :transport_module)
        else
          Application.put_env(
            :citadel_jido_integration_bridge,
            :transport_module,
            previous_transport
          )
        end
      end
    end)
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
        trace_id: trace_id,
        actor_ref: %{id: "ops_lead", kind: :human},
        tenant_ref: %{id: tenant_id},
        installation_ref: installation_ref,
        metadata: metadata
      })

    context
  end

  defp choose_operator_action(actions) do
    Enum.find(actions, &(&1.action_ref.action_kind == "pause")) || hd(actions)
  end

  defp activate_fixture_registration!(version) do
    manifest = %Manifest{
      pack_slug: "expense_approval",
      version: version,
      migration_strategy: :additive,
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
          runtime_class: :session
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

  defp operational_fixture_stack(tenant_id, opts \\ []) do
    actor = %{tenant_id: tenant_id}
    review_required? = Keyword.get(opts, :review_required?, true)

    {:ok, program} =
      Program.create_program(
        %{
          slug: "app-kit-operational-#{System.unique_integer([:positive])}",
          name: "AppKit Operational Program",
          product_family: "operator_stack",
          configuration: %{},
          metadata: %{}
        },
        actor: actor,
        tenant: tenant_id
      )

    {:ok, bundle} =
      PolicyBundle.load_bundle(
        %{
          program_id: program.id,
          name: "default",
          version: "1.0.0",
          policy_kind: :workflow_md,
          source_ref: "WORKFLOW.md",
          body: workflow_body(review_required?),
          metadata: %{}
        },
        actor: actor,
        tenant: tenant_id
      )

    {:ok, work_class} =
      WorkClass.create_work_class(
        %{
          program_id: program.id,
          name: "coding_task_#{System.unique_integer([:positive])}",
          kind: "coding_task",
          intake_schema: %{"required" => ["title"]},
          policy_bundle_id: bundle.id,
          default_review_profile: %{"required" => review_required?},
          default_run_profile: %{"runtime" => "session"}
        },
        actor: actor,
        tenant: tenant_id
      )

    %{program: program, work_class: work_class}
  end

  defp seed_trace_ledger(installation_id, subject_id, trace_id) do
    execution_id = Ecto.UUID.generate()
    now = ~U[2026-04-16 11:00:00Z]

    {1, _} =
      ExecutionRepo.insert_all("execution_records", [
        %{
          id: dump_uuid!(execution_id),
          installation_id: installation_id,
          subject_id: dump_uuid!(subject_id),
          recipe_ref: "expense_capture",
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
          updated_at: now,
          compiled_pack_revision: 1,
          binding_snapshot: %{"placement_ref" => "local_docker"}
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
          installation_id: installation_id,
          subject_id: subject_id,
          execution_id: execution_id,
          dispatch_outbox_entry_id: Ecto.UUID.generate(),
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

    {:ok, _execution} =
      ExecutionRecord.dispatch(%{
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

    bridge = InvocationBridge.new!(downstream: InvocationDownstream)
    accepted_now = ~U[2026-04-16 14:00:00.000000Z]

    {:ok, %{classification: classification, execution: accepted_execution}} =
      Dispatcher.dispatch_next(
        submit_fun: fn claimed ->
          validate_lower_backed_claim!(
            claimed,
            installation,
            subject_ref.id,
            recipe_ref,
            binding_snapshot
          )

          dispatch_through_citadel!(bridge, run_intent, context, claimed, binding_snapshot)
        end,
        actor_ref: %{kind: :dispatcher},
        now: accepted_now
      )

    outbox = fetch_outbox!(accepted_execution.id)
    acceptance = await_transport_acceptance!()

    {:ok,
     %{
       classification: classification,
       execution: accepted_execution,
       outbox: outbox,
       acceptance: acceptance
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
      actor_id: context.actor_ref.id,
      request_id: claimed.execution_id,
      trace_id: claimed.trace_id,
      idempotency_key: claimed.submission_dedupe_key,
      host_request_id: claimed.outbox_id,
      session_id: "work/#{claimed.subject_id}",
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

    {:ok, run_request} = RunIntentCompiler.compile(run_intent, compile_attrs)
    {:ok, request_context} = AuthorityAssembler.request_context(run_intent, compile_attrs)

    {:ok, compiled} =
      HostIngress.compile_run_request(run_request, request_context, [policy_pack()], [])

    case InvocationBridge.submit(bridge, compiled.invocation_request, compiled.outbox_entry) do
      {:accepted, acceptance, _bridge} ->
        {:accepted, acceptance_payload(compiled, acceptance)}

      {:rejected, rejection, _bridge} ->
        {:rejected, rejection_payload(rejection)}

      {:error, reason, _bridge} ->
        {:error, {:retryable, reason, %{"reason" => inspect(reason)}}}
    end
  end

  defp acceptance_payload(compiled, acceptance) do
    %{
      "submission_ref" => %{
        "id" => compiled.entry_id,
        "status" => Atom.to_string(acceptance.status),
        "submission_key" => acceptance.submission_key,
        "submission_receipt_ref" => acceptance.submission_receipt_ref
      },
      "lower_receipt" => %{
        "ji_submission_key" => acceptance.submission_key,
        "submission_receipt_ref" => acceptance.submission_receipt_ref
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

  defp fetch_outbox!(execution_id) do
    {:ok, outbox} = DispatchOutboxEntry.by_execution_id(execution_id)
    outbox
  end

  defp await_transport_acceptance! do
    receive do
      {:stack_lab_brain_ingress_result,
       %{result: :accepted, acceptance: acceptance, submission_key: _submission_key}} ->
        acceptance
    after
      5_000 -> raise "timed out waiting for lower-backed transport acceptance"
    end
  end

  defp lower_receipt_proof!(
         %RequestContext{} = context,
         installation_id,
         execution_id,
         submission_key
       ) do
    direct_receipt =
      case LowerFacts.fetch_submission_receipt(submission_key) do
        {:ok, receipt} -> receipt
        :error -> raise "lower-backed proof could not fetch a direct submission receipt"
      end

    read_intent =
      ReadIntent.new!(%{
        intent_id: "stack-lab:lower-receipt:#{execution_id}",
        read_type: :lower_fact,
        subject: %{
          actor_id: context.actor_ref.id,
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

  defp lower_transport_config(listener, work_object_id) do
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
