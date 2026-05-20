defmodule StackLab.CitadelSpineHarness.AppKitOperationalSurface.Support do
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
    InstallTemplate,
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
    WorkControl,
    WorkSurface
  }

  alias Mezzanine.AppKitBridge.OperatorQueryService

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
    DispatchProbe,
    InProcessInvocationDownstream,
    LowerGatewayStub,
    MezzanineOperationalStack,
    ProfileSlots,
    RoundtripRuntime,
    TransportRuntime
  }

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

  def with_lower_backed_runtime(case_name, tenant_id, fun) when is_function(fun, 1) do
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

  def lower_backed_install_template! do
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

  def seed_mezzanine_subject!(installation_id, subject_ref) do
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

  def surface_opts do
    [
      installation_backend: MezzanineBridge,
      operator_backend: MezzanineBridge,
      review_backend: MezzanineBridge,
      work_backend: MezzanineBridge,
      work_query_backend: MezzanineBridge
    ]
  end

  def request_context(tenant_id, trace_id, metadata, installation_ref \\ nil) do
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

  def revision_epoch_metadata(metadata, nil), do: metadata

  def revision_epoch_metadata(metadata, installation_ref) do
    revision = Map.get(installation_ref, :compiled_pack_revision) || 1

    metadata
    |> Map.put_new(:installation_revision, revision)
    |> Map.put_new(:activation_epoch, 1)
    |> Map.put_new(:lease_epoch, 1)
  end

  def choose_operator_action(actions, preferred_action_kind \\ "pause") do
    Enum.find(actions, &(&1.action_ref.action_kind == preferred_action_kind)) || hd(actions)
  end

  def connector_console_case_file(context, subject_ref, surface_opts) do
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

  def latest_execution_id(subject_detail, operator_projection) do
    payload_value(subject_detail, :latest_execution_id) ||
      payload_value(operator_projection, :latest_execution_id)
  end

  def payload_value(struct_or_map, key) when is_atom(key) do
    payload = Map.get(struct_or_map, :payload, %{})

    if is_map(payload) do
      Map.get(payload, key) || Map.get(payload, Atom.to_string(key))
    end
  end

  def normalize_trace_id(trace_id) do
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

  def activate_fixture_registration!(version) do
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

  def activate_governed_workload_registration! do
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

  def governed_workload_fixture_stack(tenant_id) do
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

  def governed_workload_install_template! do
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

  def governed_workload_attrs do
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

  def bare_asm_substitute_attrs do
    Map.merge(governed_workload_attrs(), %{
      synthetic_operator_driver_ref: "task_async_stream_of_asm_calls",
      driver: :task_async_stream,
      execution_mode: :bare_asm_calls
    })
  end

  def governed_workload_summary(workload) do
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

  def operational_fixture_stack(tenant_id, opts \\ []) do
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

  def seed_trace_ledger(installation_id, subject_id, trace_id) do
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

  def lower_backed_dispatch(
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

  def dispatch_through_citadel!(
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

  def acceptance_payload(lower_intent, acceptance, claimed) do
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

  def rejection_payload(rejection) do
    %{
      "reason" => Map.get(rejection, :reason_code, "citadel_rejected"),
      "rejection_family" => rejection |> Map.get(:rejection_family) |> to_string(),
      "summary" => Map.get(rejection, :summary)
    }
  end

  def hydrate_run_intent!(%RunIntent{} = run_intent), do: run_intent

  def hydrate_run_intent!(run_intent) when is_map(run_intent) do
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

  def hydrate_run_intent!(other),
    do: raise("expected a surfaced run intent, got: #{inspect(other)}")

  def fetch_installation!(installation_id) do
    {:ok, %Installation{} = installation} = Ash.get(Installation, installation_id)
    installation
  end

  def binding_snapshot_for(installation, recipe_ref) do
    installation
    |> Map.fetch!(:binding_config)
    |> get_in(["execution_bindings", recipe_ref])
    |> Map.take(["placement_ref", "execution_params", "connector_bindings"])
  end

  def validate_lower_backed_claim!(
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

  def await_transport_result! do
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

  def transport_acceptance(:accepted, %{result: :accepted, acceptance: acceptance}),
    do: acceptance

  def transport_acceptance(:terminal_rejection, %{result: :rejected}), do: nil

  def transport_acceptance(classification, transport_result) do
    raise """
    unexpected lower-backed transport acceptance state:
    classification=#{inspect(classification)}
    transport_result=#{inspect(transport_result)}
    """
  end

  def transport_rejection(:terminal_rejection, %{result: :rejected, rejection: rejection}),
    do: rejection

  def transport_rejection(:accepted, %{result: :accepted}), do: nil

  def transport_rejection(classification, transport_result) do
    raise """
    unexpected lower-backed transport rejection state:
    classification=#{inspect(classification)}
    transport_result=#{inspect(transport_result)}
    """
  end

  def rejection_reason(nil), do: nil

  def rejection_reason(rejection) do
    case Map.get(rejection, :reason_code) do
      nil -> nil
      reason -> to_string(reason)
    end
  end

  def lower_receipt_proof!(
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

  def attach_observability_telemetry!(handler_id, test_pid) do
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

  def collect_observability_telemetry!(acc \\ []) do
    receive do
      {:observability_telemetry, event, measurements, metadata} ->
        collect_observability_telemetry!([
          %{event: event, measurements: measurements, metadata: metadata} | acc
        ])
    after
      100 -> Enum.reverse(acc)
    end
  end

  def summarize_observability_telemetry!(events) when is_list(events) do
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

  def fetch_events!(events, event_name) do
    matched = Enum.filter(events, &(&1.event == event_name))

    if matched == [] do
      raise "missing observability telemetry for #{inspect(event_name)}"
    end

    matched
  end

  def fetch_one_event!(events, event_name) do
    fetch_events!(events, event_name)
    |> hd()
  end

  def collect_lower_fetch_messages!(acc \\ []) do
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

  def enrich_subject_trace_graph!(installation_id, subject_id, execution_id, trace_id) do
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

  def archived_pivot_summaries!(installation_id, pivots) when is_map(pivots) do
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

  def archived_pivot_error!(installation_id, pivot, pivot_id) do
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

  def emit_execution_plane_backfill!(trace_id, tenant_id) do
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

  def emit_citadel_trace_failure!(trace_id, tenant_id, request_id) do
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

  def assert_archived_hot_reads!(context, subject_ref, surface_opts, manifest_ref) do
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

  def assert_archived_result!(label, result, manifest_ref) do
    if match?({:error, :archived, ^manifest_ref}, result) do
      :ok
    else
      raise "expected archived #{label} result, got: #{inspect(result)}"
    end
  end

  def archived_surface_result!(
        _label,
        {:error, %SurfaceError{code: code, details: %{manifest_ref: manifest_ref}}},
        manifest_ref
      )
      when code in [:archived, "archived"] do
    {:error, :archived, manifest_ref}
  end

  def archived_surface_result!(label, result, manifest_ref) do
    raise "expected archived #{label} surface result for #{manifest_ref}, got: #{inspect(result)}"
  end

  @spec direct_submission_receipt_read!(ReadLease.t(), String.t()) :: SubmissionAcceptance.t()
  def direct_submission_receipt_read!(%ReadLease{} = read_lease, submission_key)
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
  def authorization_scope!(lease) do
    lease
    |> Map.get(:authorization_scope)
    |> AuthorizationScope.new!()
  end

  @spec tenant_scope!(RequestContext.t(), String.t()) :: TenantScope.t()
  def tenant_scope!(%RequestContext{} = context, installation_id) do
    TenantScope.new!(
      tenant_id: context.tenant_ref.id,
      installation_id: installation_id,
      actor_ref: Map.from_struct(context.actor_ref),
      trace_id: context.trace_id,
      authorized_at: DateTime.utc_now()
    )
  end

  @spec tenant_scope!(AuthorizationScope.t()) :: TenantScope.t()
  def tenant_scope!(%AuthorizationScope{} = authorization_scope) do
    TenantScope.new!(
      tenant_id: authorization_scope.tenant_id,
      installation_id: authorization_scope.installation_id,
      actor_ref: authorization_scope.actor_ref,
      trace_id: authorization_scope.trace_id,
      authorized_at: authorization_scope.authorized_at || DateTime.utc_now()
    )
  end

  def emit_stream_invalidation_burst!(lease_id, count, max_concurrency) do
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

  def ensure_disconnect_window_elapsed!(started_at_ms, required_ms) do
    elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
    remaining_ms = max(required_ms - elapsed_ms, 0)

    if remaining_ms > 0 do
      Process.sleep(remaining_ms)
    end

    :ok
  end

  def await_stream_attached!(lease_id, timeout_ms \\ 2_000) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_await_stream_attached(lease_id, deadline_ms)
  end

  def await_stream_invalidated!(lease_id, timeout_ms) do
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms
    do_await_stream_invalidated(lease_id, deadline_ms)
  end

  def ensure_no_stream_attached!(lease_id) do
    deadline_ms = System.monotonic_time(:millisecond) + 100
    do_ensure_no_stream_attached(lease_id, deadline_ms)
  end

  def wait_for_stream_host_shutdown!(pid) when is_pid(pid) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      2_000 ->
        Process.demonitor(ref, [:flush])
        raise "timed out waiting for stream host shutdown"
    end
  end

  def contiguous_sequence?([]), do: true

  def contiguous_sequence?(sequence_numbers) do
    sorted = Enum.sort(sequence_numbers)
    sorted == Enum.to_list(hd(sorted)..List.last(sorted))
  end

  def do_await_stream_attached(lease_id, deadline_ms) do
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

  def do_await_stream_invalidated(lease_id, deadline_ms) do
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

  def do_ensure_no_stream_attached(lease_id, deadline_ms) do
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

  def normalize_read_error({:error, {:lease_invalidated, reason, sequence_number}}) do
    %{
      code: :lease_invalidated,
      reason: reason,
      sequence_number: sequence_number
    }
  end

  def normalize_read_error(other), do: %{code: :unexpected_result, result: other}

  def lease_invalidated?({:error, {:lease_invalidated, _reason, _sequence_number}}), do: true
  def lease_invalidated?(_other), do: false

  def leases_invalidated?(results) when is_list(results) do
    Enum.all?(results, &lease_invalidated?/1)
  end

  def execution_trace_step!(unified_trace, execution_id) do
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

  def trace_step_execution_id(step) do
    payload = Map.fetch!(step, :payload)

    Map.get(step, :ref) || Map.get(step, "ref") || Map.get(payload, :execution_id) ||
      Map.get(payload, "execution_id")
  end

  def ensure_store_local_ready!(storage_dir) do
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

  def stop_store_local do
    case Application.stop(:jido_integration_v2_store_local) do
      :ok -> :ok
      {:error, {:not_started, :jido_integration_v2_store_local}} -> :ok
      {:error, {:not_started, _other_app}} -> :ok
      {:error, reason} -> raise "unable to stop store_local application: #{inspect(reason)}"
    end
  end

  def lower_transport_config(listener, work_object_id, mode \\ :accepted)

  def lower_transport_config(listener, _work_object_id, :scope_rejection) do
    %{
      listener: listener,
      submission_ledger: SubmissionLedger,
      submission_ledger_opts: [],
      scope_resolver: StaticScopeResolver,
      scope_resolver_opts: [mapping: %{}]
    }
  end

  def lower_transport_config(listener, work_object_id, :accepted) do
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

  def policy_pack do
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

  def store_local_dir(case_name) do
    Path.join(
      System.tmp_dir!(),
      "stack_lab_app_kit_operational_surface_#{case_name}_#{System.unique_integer([:positive])}"
    )
  end

  def map_value!(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, Atom.to_string(key)) do
      nil -> raise KeyError, key: key, term: map
      value -> value
    end
  end

  def optional_map_value(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key)) || default
  end

  def semantic_failure_carrier!(tenant_id, trace_id, execution_id) do
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

  def semantic_failure_carrier_value(failed_execution, key) do
    failed_execution
    |> map_value(:last_dispatch_error_payload)
    |> map_value("error")
    |> map_value("carrier")
    |> map_value(key)
  end

  def map_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key)) || bounded_atom_key_value(map, key)
  end

  def map_value(_value, _key), do: nil

  def bounded_atom_key_value(map, key) when is_binary(key) do
    case Map.fetch(@bounded_lookup_atom_keys, key) do
      {:ok, atom_key} -> Map.get(map, atom_key)
      :error -> nil
    end
  end

  def bounded_atom_key_value(_map, _key), do: nil

  def normalize_runtime_class(value) when value in [:direct, :session, :stream], do: value
  def normalize_runtime_class("direct"), do: :direct
  def normalize_runtime_class("stream"), do: :stream
  def normalize_runtime_class(_value), do: :session

  def workflow_body(review_required?) do
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

  def dump_uuid!(value), do: Ecto.UUID.dump!(value)
end
