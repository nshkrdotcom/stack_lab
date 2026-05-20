defmodule StackLab.CitadelSpineHarness.MemoryBindingsThroughExistingSeams do
  @moduledoc false

  alias Ash
  alias Ecto.Adapters.SQL
  alias Jido.Integration.V2
  alias Jido.Integration.V2.ArtifactRef
  alias Jido.Integration.V2.Attempt
  alias Jido.Integration.V2.ControlPlane
  alias Jido.Integration.V2.CredentialRef
  alias Jido.Integration.V2.Event
  alias Jido.Integration.V2.Run
  alias Jido.Integration.V2.StoreLocal.ArtifactStore
  alias Jido.Integration.V2.StoreLocal.AttemptStore
  alias Jido.Integration.V2.StoreLocal.EventStore
  alias Jido.Integration.V2.StoreLocal.RunStore
  alias Jido.Integration.V2.StoreLocal.TestSupport, as: StoreLocalTestSupport
  alias Mezzanine.AppKitBridge.InstallationService
  alias Mezzanine.Archival.{Query, Scheduler}
  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Execution.ExecutionRecord
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.LifecycleEvaluator
  alias Mezzanine.Objects.Repo, as: ObjectsRepo
  alias StackLab.AppEnvSandbox

  alias Mezzanine.Pack.{
    Compiler,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    ProjectionSpec,
    SubjectKindSpec
  }

  alias MezzanineConfigRegistry
  alias OuterBrain.Core.SemanticFrame
  alias OuterBrain.Prompting.ContextPack
  alias StackLab.CitadelSpineHarness.MezzanineOperationalStack
  alias StackLab.CitadelSpineHarness.ProfileSlots
  alias StackLab.CitadelSpineHarness.RuntimeResourceOwner

  @shared_trace_id "trace-stage14-memory-runtime"
  @memory_trace_id "trace-stage14-memory-maintenance"
  @archive_now ~U[2026-04-16 13:00:00Z]
  @archivable_terminal_at ~U[2026-03-01 09:00:00Z]
  @tenant_id "tenant-stage14-memory"
  @pack_slug "memory_binding_demo"
  @pack_slug_ref :memory_binding_demo
  @execution_binding_key "hindsight_runtime"
  @execution_binding_ref :hindsight_runtime
  @context_binding_key "workspace_memory"
  @subject_binding_key "turn_consolidation"
  @subject_binding_ref :turn_consolidation
  @observer_binding_key "hindsight_observer"
  @external_system_ref "hindsight.primary"

  defmodule SuccessfulContextAdapter do
    @moduledoc false

    @behaviour OuterBrain.Prompting.ContextAdapter

    @impl true
    def fetch_fragments(request, runtime_binding) do
      {:ok,
       [
         %{
           fragment_id: "fragment-hindsight-1",
           schema_ref: request.schema_ref,
           schema_version: 1,
           content: %{"summary" => "Prior memory context is available."},
           provenance: %{
             "workspace" => get_in(runtime_binding, ["config", "workspace"]),
             "external_system_ref" =>
               get_in(runtime_binding, ["descriptor", "ownership", "external_system_ref"])
           },
           staleness: %{"class" => "fresh"},
           metadata: %{"rank" => 1}
         }
       ]}
    end
  end

  defmodule SlowContextAdapter do
    @moduledoc false

    @behaviour OuterBrain.Prompting.ContextAdapter

    @impl true
    def fetch_fragments(_request, _runtime_binding) do
      Process.sleep(25)
      {:ok, []}
    end
  end

  @spec run_case(:memory_bindings_through_existing_seams) :: {:ok, map()}
  def run_case(:memory_bindings_through_existing_seams) do
    MezzanineOperationalStack.with_store(
      :memory_bindings_through_existing_seams,
      fn _repo_config ->
        pack_version = unique_pack_version()
        cold_store_root = cold_store_root()

        try do
          File.mkdir_p!(cold_store_root)
          activate_fixture_registration!(pack_version)

          installation = create_installation!(pack_version)
          context = prove_context_binding!(installation)
          inference = prove_inference_binding!(installation)
          memory_subject = prove_memory_subject!(installation, cold_store_root)
          observer = prove_observer_binding!(installation)

          {:ok,
           %{
             case: :memory_bindings_through_existing_seams,
             installation: installation_summary(installation),
             context: context,
             inference: inference,
             memory_subject: memory_subject,
             observer: observer,
             boundaries: %{
               allowed_binding_families_only?:
                 installation.bindings
                 |> Map.keys()
                 |> Enum.sort() == [
                   "context_bindings",
                   "execution_bindings",
                   "observer_bindings",
                   "subject_bindings"
                 ],
               no_secondary_binding_plane?:
                 Enum.all?(
                   ["memory_bindings", "query_bindings", "read_bindings", "stream_bindings"],
                   &(not Map.has_key?(installation.bindings, &1))
                 ),
               observer_surface: "jido_integration.audit_subscriber"
             }
           }}
        after
          File.rm_rf(cold_store_root)
        end
      end
    )
  end

  defp installation_summary(%{
         installation_ref: installation_ref,
         bindings: bindings,
         external_systems: [external_system]
       }) do
    %{
      installation_id: installation_ref.id,
      external_system_ref: external_system.external_system_ref,
      binding_count: external_system.binding_count,
      attachments:
        external_system.bindings
        |> Enum.map(& &1.attachment)
        |> Enum.sort(),
      binding_families: bindings |> Map.keys() |> Enum.sort(),
      credential_refs: external_system.credential_refs
    }
  end

  defp create_installation!(pack_version) do
    runtime_profile = runtime_profile_fixture()

    attrs = %{
      tenant_id: @tenant_id,
      environment: "stage14-memory-#{System.unique_integer([:positive])}",
      template_key: "memory-binding-template",
      pack_slug: @pack_slug,
      pack_version: pack_version,
      runtime_profile: runtime_profile,
      metadata: %{"managed_by" => "stack_lab"},
      default_bindings: default_bindings()
    }

    {:ok, install_result} = InstallationService.create_installation(attrs)
    {:ok, detail} = InstallationService.get_installation(install_result.installation_ref.id)

    Map.put(detail, :bindings, detail.bindings)
  end

  defp default_bindings do
    descriptor_envelope = %{
      "staleness_class" => "diagnostic_only",
      "trace_propagation" => "required",
      "tenant_scope" => "installation_scoped",
      "blast_radius" => "installation"
    }

    ownership = %{
      "external_system" => "Hindsight",
      "external_system_ref" => @external_system_ref,
      "operator_owner" => "agent-platform"
    }

    %{
      "execution_bindings" => %{
        @execution_binding_key => %{
          "placement_ref" => "memory_reasoner",
          "authority_decision_ref" => "authority-decision://stage14-memory/hindsight-runtime",
          "connector_binding_ref" => "connector-binding://stage14-memory/hindsight-runtime",
          "credential_lease_ref" => "credential-lease://stage14-memory/hindsight-runtime",
          "execution_params" => %{
            "timeout_ms" => 120_000,
            "reasoning_tier" => "deliberate"
          },
          "credential_ref" => "cred-hindsight",
          "descriptor" => %{
            "attachment" => "mezzanine.execution_recipe",
            "contract" => "authoritative",
            "envelope" => Map.put(descriptor_envelope, "runbook_ref", "runbooks/memory_reasoner"),
            "failure" => %{
              "on_unavailable" => "retry_background",
              "on_timeout" => "fail_execution"
            },
            "ownership" => ownership
          }
        }
      },
      "context_bindings" => %{
        @context_binding_key => %{
          "adapter_key" => "hindsight_context",
          "config" => %{"workspace" => "default"},
          "timeout_ms" => 15,
          "credential_ref" => "cred-hindsight",
          "descriptor" => %{
            "attachment" => "outer_brain.context_adapter",
            "contract" => "contributing",
            "envelope" => Map.put(descriptor_envelope, "runbook_ref", "runbooks/context_adapter"),
            "failure" => %{
              "on_unavailable" => "proceed_without",
              "on_timeout" => "proceed_without"
            },
            "ownership" => ownership
          }
        }
      },
      "subject_bindings" => %{
        @subject_binding_key => %{
          "subject_kind" => @subject_binding_key,
          "recipe_refs" => [@execution_binding_key],
          "descriptor" => %{
            "attachment" => "mezzanine.subject_kind",
            "contract" => "authoritative",
            "envelope" =>
              Map.put(descriptor_envelope, "runbook_ref", "runbooks/turn_consolidation"),
            "failure" => %{
              "on_unavailable" => "retry_background",
              "on_timeout" => "retry_background"
            },
            "ownership" => ownership
          }
        }
      },
      "observer_bindings" => %{
        @observer_binding_key => %{
          "subscriber_key" => "hindsight_audit_export",
          "event_types" => V2.audit_export_kinds(),
          "descriptor" => %{
            "attachment" => "jido_integration.audit_subscriber",
            "contract" => "advisory",
            "envelope" => Map.put(descriptor_envelope, "runbook_ref", "runbooks/audit_export"),
            "failure" => %{
              "on_unavailable" => "fail_installation_health",
              "on_timeout" => "retry_background"
            },
            "ownership" => ownership
          }
        }
      }
    }
  end

  defp runtime_profile_fixture do
    %{
      program: %{
        slug: "stage14-memory-#{System.unique_integer([:positive])}",
        name: "Stage 14 Memory Program",
        product_family: "stack_lab",
        configuration: %{},
        metadata: %{}
      },
      policy_bundle: %{
        name: "stage14-memory-default",
        version: "1.0.0",
        policy_kind: :workflow_md,
        source_ref: "WORKFLOW.md",
        body: "# Stage 14 Memory Scenario\n\nUse the governed runtime only.",
        metadata: %{}
      },
      work_class: %{
        name: "memory_task_#{System.unique_integer([:positive])}",
        kind: "memory_task",
        intake_schema: %{"required" => ["title"]},
        default_review_profile: %{"required" => false},
        default_run_profile: %{"runtime" => "inference"}
      },
      placement_profile: %{
        profile_id: "memory_reasoner",
        strategy: "affinity",
        target_selector: %{"runtime_driver" => "hindsight"},
        runtime_preferences: %{"locality" => "same_region"},
        workspace_policy: %{},
        metadata: %{}
      }
    }
  end

  defp activate_fixture_registration!(pack_version) do
    compiled_pack = compiled_pack_fixture(pack_version)

    compiled_pack
    |> MezzanineConfigRegistry.register_pack!()
    |> PackRegistration.activate()
    |> case do
      {:ok, registration} ->
        registration

      {:error, error} ->
        raise "failed to activate memory-binding fixture pack: #{inspect(error)}"
    end
  end

  defp compiled_pack_fixture(pack_version) do
    manifest = %Manifest{
      pack_slug: @pack_slug_ref,
      version: pack_version,
      max_supersession_depth: 8,
      profile_slots:
        ProfileSlots.default(
          runtime_profile_ref: :memory_runtime_v1,
          memory_profile_ref: :private_facts_v1,
          projection_profile_ref: :memory_readback_v1
        ),
      subject_kind_specs: [
        %SubjectKindSpec{name: :expense_request},
        %SubjectKindSpec{name: @subject_binding_ref}
      ],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: :expense_request,
          initial_state: :submitted,
          terminal_states: [:paid, :needs_correction],
          transitions: [
            %{
              from: :submitted,
              to: :processing,
              trigger: {:execution_requested, @execution_binding_ref}
            },
            %{
              from: :processing,
              to: :paid,
              trigger: {:execution_completed, @execution_binding_ref}
            },
            %{
              from: :processing,
              to: :needs_correction,
              trigger: {:execution_failed, @execution_binding_ref, :semantic_failure}
            }
          ]
        },
        %LifecycleSpec{
          subject_kind: @subject_binding_ref,
          initial_state: :submitted,
          terminal_states: [:consolidated],
          transitions: [
            %{
              from: :submitted,
              to: :consolidating,
              trigger: {:execution_requested, @execution_binding_ref}
            },
            %{
              from: :consolidating,
              to: :consolidated,
              trigger: {:execution_completed, @execution_binding_ref}
            },
            %{
              from: :consolidating,
              to: :needs_retry,
              trigger: {:execution_failed, @execution_binding_ref, :semantic_failure}
            },
            %{
              from: :needs_retry,
              to: :consolidating,
              trigger: {:execution_requested, @execution_binding_ref}
            }
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: @execution_binding_ref,
          runtime_class: :inference,
          placement_ref: :memory_reasoner,
          execution_params: %{
            timeout_ms: 120_000,
            reasoning_tier: "deliberate"
          },
          workspace_policy: %{
            strategy: :per_subject,
            root_ref: "#{@execution_binding_key}_workspaces"
          },
          sandbox_policy_ref: "#{@execution_binding_key}_sandbox",
          prompt_refs: ["#{@execution_binding_key}_prompt"],
          retry_config: %{
            max_attempts: 3,
            backoff: :exponential,
            rekey_on: [:semantic_failure]
          }
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: :memory_queue, subject_kinds: [:expense_request]},
        %ProjectionSpec{
          name: :turn_consolidation_queue,
          subject_kinds: [@subject_binding_ref]
        }
      ]
    }

    case Compiler.compile(manifest) do
      {:ok, compiled_pack} ->
        compiled_pack

      {:error, errors} ->
        raise "failed to compile memory-binding fixture pack: #{inspect(errors)}"
    end
  end

  defp prove_context_binding!(installation) do
    successful_pack =
      build_context_pack!(
        installation,
        @shared_trace_id,
        %{"hindsight_context" => SuccessfulContextAdapter}
      )

    degraded_pack =
      build_context_pack!(
        installation,
        @shared_trace_id,
        %{"hindsight_context" => SlowContextAdapter},
        timeout_ms: 5
      )

    [fragment] = successful_pack.fragments
    [successful_source] = successful_pack.context_sources
    [degraded_source] = degraded_pack.context_sources

    %{
      success: %{
        trace_id: successful_pack.trace_id,
        status: successful_source.status,
        fragment_count: successful_source.fragment_count,
        fragment_provenance: fragment.provenance
      },
      degraded: %{
        trace_id: degraded_pack.trace_id,
        status: degraded_source.status,
        error: degraded_source.error
      }
    }
  end

  defp build_context_pack!(installation, trace_id, adapter_registry, opts \\ []) do
    frame =
      "session-stage14-memory"
      |> SemanticFrame.seed("answer the user with governed memory")
      |> SemanticFrame.record_commitment("I will stay on the bounded seams")

    binding =
      installation.bindings
      |> Map.fetch!("context_bindings")
      |> Map.fetch!(@context_binding_key)
      |> maybe_override_timeout(opts)

    ContextPack.build(
      frame,
      ["turn/stage14-memory", "artifact/stage14-memory"],
      mode: :reasoning,
      trace_id: trace_id,
      context_sources: [
        %{
          source_ref: @context_binding_key,
          binding_key: @context_binding_key,
          usage_phase: :retrieval,
          required?: true,
          timeout_ms: binding["timeout_ms"],
          schema_ref: "context/workspace_memory",
          max_fragments: 2,
          merge_strategy: :ranked_append
        }
      ],
      context_bindings: %{@context_binding_key => binding},
      adapter_registry: adapter_registry
    )
  end

  defp maybe_override_timeout(binding, opts) do
    case Keyword.get(opts, :timeout_ms) do
      nil -> binding
      timeout_ms -> Map.put(binding, "timeout_ms", timeout_ms)
    end
  end

  defp prove_inference_binding!(installation) do
    subject_id =
      insert_subject!(
        installation.installation_ref.id,
        "expense_request",
        "submitted",
        "expense:stage14:inference",
        @shared_trace_id,
        "cause-stage14-memory-inference"
      )

    {:ok, lifecycle_result} = LifecycleEvaluator.advance(subject_id)
    {:ok, execution} = Ash.get(ExecutionRecord, lifecycle_result.execution_id)

    {:ok, accepted_execution} =
      ExecutionRecord.record_accepted(execution, %{
        submission_ref: %{"id" => "sub-stage14-memory-inference"},
        lower_receipt: %{"state" => "accepted", "run_id" => "run-stage14-memory-inference"},
        trace_id: execution.trace_id,
        causation_id: "cause-stage14-memory-inference-accepted",
        actor_ref: %{kind: :dispatcher}
      })

    outcome = %{
      "receipt_id" => "receipt-stage14-memory-inference",
      "status" => "error",
      "failure_kind" => "semantic_failure",
      "lower_receipt" => %{
        "state" => "failed",
        "run_id" => "run-stage14-memory-inference",
        "attempt_id" => "attempt-stage14-memory-inference"
      },
      "normalized_outcome" => %{
        "error" => %{
          "kind" => "semantic_failure",
          "reason" => "insufficient_context"
        }
      },
      "observed_at" => "2026-04-16T04:05:00Z"
    }

    :ok = perform_receipt(accepted_execution.id, outcome)

    {:ok, failed_execution} = Ash.get(ExecutionRecord, accepted_execution.id)

    %{
      dispatch: %{
        execution_id: failed_execution.id,
        trace_id: failed_execution.trace_id,
        runtime_class: failed_execution.dispatch_envelope["runtime_class"],
        placement_ref: failed_execution.binding_snapshot["placement_ref"],
        descriptor_attachment:
          get_in(failed_execution.binding_snapshot, ["descriptor", "attachment"]),
        external_system_ref:
          get_in(failed_execution.binding_snapshot, [
            "descriptor",
            "ownership",
            "external_system_ref"
          ]),
        workflow_handoff_count: workflow_handoff_count(failed_execution.id)
      },
      outcome: %{
        dispatch_state: failed_execution.dispatch_state,
        failure_kind: failed_execution.failure_kind,
        normalized_outcome: failed_execution.last_dispatch_error_payload,
        subject_state: fetch_subject_state(subject_id),
        trace_fact_kinds: list_trace_fact_kinds(@shared_trace_id)
      }
    }
  end

  defp prove_memory_subject!(installation, cold_store_root) do
    subject_id =
      insert_subject!(
        installation.installation_ref.id,
        @subject_binding_key,
        "submitted",
        "memory:turn-consolidation",
        @memory_trace_id,
        "cause-stage14-memory-subject"
      )

    {:ok, first_result} = LifecycleEvaluator.advance(subject_id)
    {:ok, first_execution} = Ash.get(ExecutionRecord, first_result.execution_id)

    {:ok, awaiting_first_execution} =
      ExecutionRecord.record_accepted(first_execution, %{
        submission_ref: %{"id" => "sub-stage14-memory-subject-1"},
        lower_receipt: %{"state" => "accepted", "run_id" => "run-stage14-memory-subject-1"},
        trace_id: first_execution.trace_id,
        causation_id: "cause-stage14-memory-subject-accepted-1",
        actor_ref: %{kind: :dispatcher}
      })

    semantic_failure_outcome = %{
      "receipt_id" => "receipt-stage14-memory-subject-1",
      "status" => "error",
      "failure_kind" => "semantic_failure",
      "lower_receipt" => %{
        "state" => "failed",
        "run_id" => "run-stage14-memory-subject-1",
        "attempt_id" => "attempt-stage14-memory-subject-1"
      },
      "normalized_outcome" => %{
        "error" => %{
          "kind" => "semantic_failure",
          "reason" => "stale_memory"
        }
      },
      "observed_at" => "2026-04-16T04:15:00Z"
    }

    :ok = perform_receipt(awaiting_first_execution.id, semantic_failure_outcome)

    {:ok, _retry_result} =
      LifecycleEvaluator.advance(
        subject_id,
        supersedes_execution_id: awaiting_first_execution.id,
        supersession_reason: :retry_semantic,
        causation_id: "cause-stage14-memory-subject-retry"
      )

    [failed_execution_id, retry_execution_id] = subject_execution_ids(subject_id)

    {:ok, failed_execution} = Ash.get(ExecutionRecord, failed_execution_id)
    {:ok, retry_execution} = Ash.get(ExecutionRecord, retry_execution_id)

    {:ok, awaiting_retry_execution} =
      ExecutionRecord.record_accepted(retry_execution, %{
        submission_ref: %{"id" => "sub-stage14-memory-subject-2"},
        lower_receipt: %{"state" => "accepted", "run_id" => "run-stage14-memory-subject-2"},
        trace_id: retry_execution.trace_id,
        causation_id: "cause-stage14-memory-subject-accepted-2",
        actor_ref: %{kind: :dispatcher}
      })

    successful_outcome = %{
      "receipt_id" => "receipt-stage14-memory-subject-2",
      "status" => "ok",
      "lower_receipt" => %{
        "state" => "completed",
        "run_id" => "run-stage14-memory-subject-2",
        "attempt_id" => "attempt-stage14-memory-subject-2"
      },
      "normalized_outcome" => %{"summary" => "consolidation completed"},
      "observed_at" => "2026-04-16T04:16:00Z"
    }

    :ok = perform_receipt(awaiting_retry_execution.id, successful_outcome)
    final_subject_state = fetch_subject_state(subject_id)
    trace_fact_kinds = list_trace_fact_kinds(@memory_trace_id)
    retry_execution_count = length(subject_execution_ids(subject_id)) - 1

    mark_subject_terminal_at!(subject_id, @archivable_terminal_at)

    {:ok, archival_result} =
      Scheduler.archive_subject(
        installation.installation_ref.id,
        subject_id,
        now: @archive_now,
        root: cold_store_root
      )

    {:ok, archived_bundle} =
      Query.fetch_bundle(archival_result.manifest_ref, root: cold_store_root)

    %{
      first_execution: %{
        execution_id: first_execution.id,
        trace_id: first_execution.trace_id,
        runtime_class: first_execution.dispatch_envelope["runtime_class"]
      },
      retry: %{
        failed_execution_id: failed_execution.id,
        retry_execution_id: retry_execution.id,
        retry_execution_count: retry_execution_count,
        supersession_reason: retry_execution.supersession_reason,
        supersedes_execution_id: retry_execution.supersedes_execution_id,
        subject_state_after_retry: final_subject_state
      },
      archival: %{
        status: archival_result.status,
        manifest_ref: archival_result.manifest_ref,
        removed: normalize_removed_counts(archival_result.removed),
        hot_subject_row_count: hot_subject_row_count(subject_id),
        bundle_subject_state: get_in(archived_bundle, ["subject", "lifecycle_state"]),
        bundle_trace_ids:
          archived_bundle
          |> Map.fetch!("trace_views")
          |> Map.keys()
          |> Enum.sort(),
        trace_fact_kinds: trace_fact_kinds
      }
    }
  end

  defp prove_observer_binding!(installation) do
    with_store_local_case(fn ->
      token = Integer.to_string(System.unique_integer([:positive]))
      run = observer_run_fixture(installation.installation_ref.id, token)
      attempt = observer_attempt_fixture(run.run_id)
      events = observer_event_fixtures(run.run_id, attempt.attempt_id, token)
      artifact = artifact_fixture(run.run_id, attempt.attempt_id)

      :ok = RunStore.put_run(run)
      :ok = AttemptStore.put_attempt(attempt)
      :ok = EventStore.append_events(events)
      :ok = ArtifactStore.put_artifact_ref(artifact)

      {:ok, exports} = V2.replay_audit_exports(run.run_id)

      %{
        export_count: length(exports),
        export_kinds: exports |> Enum.map(& &1.export_kind) |> Enum.uniq() |> Enum.sort(),
        trace_ids: exports |> Enum.map(& &1.trace_id) |> Enum.uniq(),
        tenant_ids: exports |> Enum.map(& &1.tenant_id) |> Enum.uniq(),
        installation_ids: exports |> Enum.map(& &1.installation_id) |> Enum.uniq(),
        staleness: exports |> Enum.map(& &1.staleness) |> Enum.uniq(),
        durable_export_ids?:
          Enum.all?(exports, &(is_binary(&1.export_id) and byte_size(&1.export_id) > 0)),
        payload_ref_present?:
          exports
          |> Enum.find(&(&1.export_kind == "artifact.recorded"))
          |> then(&(not is_nil(get_in(&1.payload, ["artifact", "payload_ref"])))),
        surface: "jido_integration.audit_subscriber"
      }
    end)
  end

  defp observer_run_fixture(installation_id, token) do
    Run.new!(%{
      run_id: "run-stage14-memory-observer-#{token}",
      capability_id: "inference.execute",
      runtime_class: :direct,
      status: :completed,
      input: %{
        "context" => %{
          "metadata" => %{
            "tenant_id" => @tenant_id,
            "installation_id" => installation_id
          },
          "observability" => %{"trace_id" => @shared_trace_id}
        },
        "request" => %{
          "metadata" => %{
            "tenant_id" => @tenant_id,
            "installation_id" => installation_id,
            "trace_id" => @shared_trace_id
          }
        },
        "prompt" => "Summarize the memory binding replay"
      },
      credential_ref:
        CredentialRef.new!(%{
          id: "credential-ref-stage14-memory-observer-#{token}",
          subject: @tenant_id
        }),
      result: %{
        "status" => "ok",
        "content" => "Observer replay is alive."
      },
      artifact_refs: []
    })
  end

  defp observer_attempt_fixture(run_id) do
    Attempt.new!(%{
      run_id: run_id,
      attempt: 1,
      runtime_class: :direct,
      status: :completed,
      output: %{
        "inference_result" => %{
          "status" => "ok",
          "content" => "Observer replay is alive."
        }
      }
    })
  end

  defp observer_event_fixtures(run_id, attempt_id, token) do
    [
      Event.new!(%{
        run_id: run_id,
        attempt_id: attempt_id,
        seq: 0,
        type: "inference.request_admitted",
        payload: %{"request_id" => "req-stage14-memory-observer-#{token}"},
        trace: %{trace_id: @shared_trace_id}
      }),
      Event.new!(%{
        run_id: run_id,
        attempt_id: attempt_id,
        seq: 1,
        type: "inference.attempt_started",
        payload: %{"attempt_id" => attempt_id},
        trace: %{trace_id: @shared_trace_id}
      }),
      Event.new!(%{
        run_id: run_id,
        attempt_id: attempt_id,
        seq: 2,
        type: "inference.attempt_completed",
        payload: %{"status" => "ok"},
        trace: %{trace_id: @shared_trace_id}
      })
    ]
  end

  defp artifact_fixture(run_id, attempt_id) do
    checksum = "sha256:" <> String.duplicate("d", 64)

    ArtifactRef.new!(%{
      artifact_id: "artifact-stage14-memory-#{System.unique_integer([:positive])}",
      run_id: run_id,
      attempt_id: attempt_id,
      artifact_type: :tool_output,
      transport_mode: :object_store,
      checksum: checksum,
      size_bytes: 64,
      payload_ref: %{
        store: "s3",
        key: "stage14-memory/#{run_id}/#{attempt_id}",
        ttl_s: 86_400,
        access_control: :run_scoped,
        checksum: checksum,
        size_bytes: 64
      },
      retention_class: "observer_export",
      redaction_status: :clear,
      metadata: %{
        surface: "audit_subscriber",
        producer: "stack_lab"
      }
    })
  end

  defp with_store_local_case(fun) when is_function(fun, 0) do
    RuntimeResourceOwner.transaction(fn ->
      previous_env = snapshot_store_local_env()
      storage_dir = StoreLocalTestSupport.tmp_dir!()

      try do
        :ok = StoreLocalTestSupport.reconfigure!(storage_dir: storage_dir)
        :ok = StoreLocalTestSupport.reset_all!()
        reset_control_plane_if_started()
        fun.()
      after
        stop_store_local()
        restore_store_local_env(previous_env)
        StoreLocalTestSupport.cleanup!(storage_dir)
      end
    end)
  end

  defp reset_control_plane_if_started do
    if Process.whereis(Jido.Integration.V2.ControlPlane.Registry) do
      ControlPlane.reset!()
    end

    :ok
  end

  defp stop_store_local do
    case Application.stop(:jido_integration_v2_store_local) do
      :ok -> :ok
      {:error, {:not_started, :jido_integration_v2_store_local}} -> :ok
      {:error, {:not_started, _other_app}} -> :ok
      {:error, reason} -> raise "unable to stop store_local application: #{inspect(reason)}"
    end
  end

  defp snapshot_store_local_env do
    %{
      control_plane:
        snapshot_keys(:jido_integration_v2_control_plane, [
          :run_store,
          :attempt_store,
          :event_store,
          :artifact_store,
          :target_store,
          :ingress_store
        ]),
      auth:
        snapshot_keys(:jido_integration_v2_auth, [
          :credential_store,
          :lease_store,
          :connection_store,
          :install_store,
          :keyring,
          :refresh_handler,
          :external_secret_resolver
        ]),
      brain_ingress: snapshot_keys(:jido_integration_v2_brain_ingress, [:submission_ledger]),
      store_local: snapshot_keys(:jido_integration_v2_store_local, [:storage_dir])
    }
  end

  defp restore_store_local_env(previous_env) do
    restore_keys(:jido_integration_v2_control_plane, previous_env.control_plane)
    restore_keys(:jido_integration_v2_auth, previous_env.auth)
    restore_keys(:jido_integration_v2_brain_ingress, previous_env.brain_ingress)
    restore_keys(:jido_integration_v2_store_local, previous_env.store_local)
    :ok
  end

  defp snapshot_keys(app, keys) do
    keys
    |> Enum.map(&{app, &1})
    |> AppEnvSandbox.snapshot()
  end

  defp restore_keys(_app, snapshot), do: AppEnvSandbox.restore(snapshot)

  defp insert_subject!(
         installation_id,
         subject_kind,
         lifecycle_state,
         source_ref,
         trace_id,
         causation_id
       ) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    subject_id = Ecto.UUID.generate()

    SQL.query!(
      ObjectsRepo,
      """
      INSERT INTO subject_records (
        id,
        payload,
        installation_id,
        source_ref,
        subject_kind,
        lifecycle_state,
        schema_version,
        opened_at,
        row_version,
        inserted_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      """,
      [
        dump_uuid!(subject_id),
        %{"title" => source_ref},
        installation_id,
        source_ref,
        subject_kind,
        lifecycle_state,
        1,
        now,
        1,
        now,
        now
      ]
    )

    SQL.query!(
      AuditRepo,
      """
      INSERT INTO audit_facts (
        id,
        installation_id,
        subject_id,
        execution_id,
        trace_id,
        causation_id,
        fact_kind,
        actor_ref,
        payload,
        occurred_at,
        inserted_at,
        updated_at
      )
      VALUES ($1, $2, $3, NULL, $4, $5, $6, $7, $8, $9, $10, $11)
      """,
      [
        dump_uuid!(Ecto.UUID.generate()),
        installation_id,
        subject_id,
        trace_id,
        causation_id,
        "subject_ingested",
        %{"kind" => "intake"},
        %{
          "source_ref" => source_ref,
          "subject_kind" => subject_kind,
          "lifecycle_state" => lifecycle_state
        },
        now,
        now,
        now
      ]
    )

    subject_id
  end

  defp perform_receipt(execution_id, outcome) do
    {:ok, execution} = Ash.get(ExecutionRecord, execution_id)

    attrs = outcome_attrs(execution, outcome)

    result =
      case outcome["status"] do
        "ok" ->
          ExecutionRecord.record_completed(execution, attrs)

        "cancelled" ->
          ExecutionRecord.record_cancelled_outcome(execution, attrs)

        "error" ->
          ExecutionRecord.record_failed_outcome(
            execution,
            Map.put(attrs, :failure_kind, failure_kind(outcome))
          )
      end

    with {:ok, recorded_execution} <- result,
         {:ok, _advance_result} <- advance_after_receipt(recorded_execution, outcome) do
      :ok
    end
  end

  defp advance_after_receipt(recorded_execution, %{"status" => "ok"}) do
    LifecycleEvaluator.advance(
      recorded_execution.subject_id,
      trigger: {:execution_completed, recorded_execution.recipe_ref},
      execution_id: recorded_execution.id,
      causation_id: "lifecycle-receipt:#{recorded_execution.id}:completed"
    )
  end

  defp advance_after_receipt(recorded_execution, %{"status" => "error"} = outcome) do
    LifecycleEvaluator.advance(
      recorded_execution.subject_id,
      trigger: {:execution_failed, recorded_execution.recipe_ref, failure_kind(outcome)},
      execution_id: recorded_execution.id,
      causation_id: "lifecycle-receipt:#{recorded_execution.id}:failed"
    )
  end

  defp advance_after_receipt(recorded_execution, _outcome) do
    LifecycleEvaluator.advance(recorded_execution.subject_id)
  end

  defp outcome_attrs(execution, outcome) do
    %{
      receipt_id: Map.fetch!(outcome, "receipt_id"),
      lower_receipt: Map.get(outcome, "lower_receipt", %{}),
      normalized_outcome: Map.get(outcome, "normalized_outcome", %{}),
      trace_id: execution.trace_id,
      causation_id: "temporal-receipt:#{execution.id}:#{Map.fetch!(outcome, "receipt_id")}",
      actor_ref: %{kind: :temporal_activity}
    }
  end

  defp failure_kind(%{"failure_kind" => "semantic_failure"}), do: :semantic_failure
  defp failure_kind(%{"failure_kind" => "infrastructure_error"}), do: :infrastructure_error
  defp failure_kind(_outcome), do: :infrastructure_error

  defp workflow_handoff_count(execution_id) do
    case ExecutionRecord.enqueue_dispatch(execution_id) do
      {:ok, %{provider: :temporal_workflow}} -> 1
      _other -> 0
    end
  end

  defp subject_execution_ids(subject_id) do
    SQL.query!(
      ExecutionRepo,
      """
      SELECT id::text
      FROM execution_records
      WHERE subject_id = $1::uuid
      ORDER BY inserted_at ASC
      """,
      [dump_uuid!(subject_id)]
    ).rows
    |> Enum.map(fn [execution_id] -> execution_id end)
  end

  defp fetch_subject_state(subject_id) do
    SQL.query!(
      ObjectsRepo,
      """
      SELECT lifecycle_state
      FROM subject_records
      WHERE id = $1::uuid
      LIMIT 1
      """,
      [dump_uuid!(subject_id)]
    ).rows
    |> case do
      [[state]] -> state
      _ -> nil
    end
  end

  defp hot_subject_row_count(subject_id) do
    SQL.query!(
      ObjectsRepo,
      """
      SELECT COUNT(*)
      FROM subject_records
      WHERE id = $1::uuid
      """,
      [dump_uuid!(subject_id)]
    ).rows
    |> case do
      [[count]] -> count
      _ -> 0
    end
  end

  defp list_trace_fact_kinds(trace_id) do
    SQL.query!(
      AuditRepo,
      """
      SELECT fact_kind
      FROM audit_facts
      WHERE trace_id = $1
      ORDER BY occurred_at ASC, inserted_at ASC
      """,
      [trace_id]
    ).rows
    |> Enum.map(fn [fact_kind] -> fact_kind end)
  end

  defp mark_subject_terminal_at!(subject_id, terminal_at) do
    SQL.query!(
      ObjectsRepo,
      """
      UPDATE subject_records
      SET terminal_at = $2,
          updated_at = $2
      WHERE id = $1::uuid
      """,
      [dump_uuid!(subject_id), terminal_at]
    )

    :ok
  end

  defp unique_pack_version do
    "1.0.#{System.unique_integer([:positive])}"
  end

  defp cold_store_root do
    Path.join(
      System.tmp_dir!(),
      "stack-lab-stage14-memory-#{System.unique_integer([:positive])}"
    )
  end

  defp normalize_removed_counts(removed) when is_map(removed) do
    removed
    |> Map.put(:subject, Map.get(removed, :subject, Map.get(removed, :subjects, 0)))
    |> Map.put(:execution, Map.get(removed, :execution, Map.get(removed, :executions, 0)))
    |> Map.put(:audit_fact, Map.get(removed, :audit_fact, Map.get(removed, :audit_facts, 0)))
    |> Map.put(:decision, Map.get(removed, :decision, Map.get(removed, :decisions, 0)))
    |> Map.put(:evidence, Map.get(removed, :evidence, Map.get(removed, :evidence, 0)))
  end

  defp dump_uuid!(value), do: Ecto.UUID.dump!(value)
end
