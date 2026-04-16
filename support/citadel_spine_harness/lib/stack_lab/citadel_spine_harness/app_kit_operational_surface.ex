defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface do
  @moduledoc false

  alias AppKit.Bridges.MezzanineBridge

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
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Decisions.Repo, as: DecisionsRepo
  alias Mezzanine.EvidenceLedger.Repo, as: EvidenceRepo
  alias Mezzanine.Execution.Repo, as: ExecutionRepo

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
  alias StackLab.CitadelSpineHarness.MezzanineOperationalStack

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

  @spec run_case(:install_ingest_review_trace) :: {:ok, map()}
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

  defp operational_fixture_stack(tenant_id) do
    actor = %{tenant_id: tenant_id}

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
          body: workflow_body(),
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
          default_review_profile: %{"required" => true},
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

  defp workflow_body do
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
      required: true
      required_decisions: 1
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
