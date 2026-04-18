defmodule StackLab.CitadelSpineHarness.Stage9OrchestrationRecovery do
  @moduledoc false

  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.DecisionCommands
  alias Mezzanine.DecisionExpiryWorker
  alias Mezzanine.Execution.ExecutionRecord
  alias Mezzanine.Execution.Repo
  alias Mezzanine.ExecutionCancelWorker
  alias Mezzanine.ExecutionReceiptWorker
  alias Mezzanine.ExecutionReconcileWorker
  alias Mezzanine.JoinAdvanceWorker
  alias Mezzanine.LowerGatewayCircuit
  alias Mezzanine.Objects.SubjectRecord
  alias Mezzanine.OperatorCommands
  alias Mezzanine.ParallelBarrier
  alias Oban.Job

  alias Mezzanine.Pack.{
    CompiledPack,
    Compiler,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    ProjectionSpec,
    SubjectKindSpec
  }

  alias Mezzanine.RuntimeScheduler.ReconcileOnStart

  alias StackLab.CitadelSpineHarness.{
    DispatchProbe,
    LowerGatewayStub,
    MezzanineRestartRecovery,
    MezzanineSubstrate
  }

  @dispatch_snapshot %{
    "placement_ref" => "local_docker",
    "execution_params" => %{"timeout_ms" => 600_000},
    "connector_bindings" => %{"github_write" => %{"connector_key" => "github_app"}}
  }

  @tenant_id "tenant-1"
  @installation_id "inst-1"
  @dispatch_worker Oban.Worker.to_string(Mezzanine.ExecutionDispatchWorker)
  @reconcile_worker Oban.Worker.to_string(Mezzanine.ExecutionReconcileWorker)
  @cancel_worker Oban.Worker.to_string(Mezzanine.ExecutionCancelWorker)
  @decision_expiry_worker Oban.Worker.to_string(Mezzanine.DecisionExpiryWorker)
  @pause_sentinel ~U[9999-12-31 00:00:00.000000Z]

  @spec run_case(
          :operator_pause_during_active_execution
          | :operator_cancel_during_active_execution
          | :decision_sla_expiry
          | :parallel_join_closure
          | :restart_during_dispatch_ambiguity
          | :lower_gateway_outage_recovery
          | :startup_reconciliation_deduplication
        ) :: {:ok, map()} | {:error, term()}
  def run_case(:operator_pause_during_active_execution) do
    MezzanineSubstrate.with_store(:operator_pause_during_active_execution, fn _repo_config ->
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      {:ok, subject} = ingest_subject("stack-lab:operator-pause")

      dispatch_executions =
        create_dispatch_executions(subject, 100, "operator-pause",
          tenant_id: @tenant_id,
          installation_id: @installation_id,
          scheduled_at: now
        )

      dispatch_schedule_before =
        subject_jobs(subject.id, @dispatch_worker, "dispatch")
        |> scheduled_at_by_job_id()

      decisions =
        dispatch_executions
        |> Enum.take(20)
        |> Enum.with_index(1)
        |> Enum.map(fn {execution, index} ->
          required_by = DateTime.add(now, index * 2, :hour)
          create_pending_decision(subject, execution, "pause-#{index}", required_by)
        end)

      decision_schedule_before =
        decisions
        |> Enum.map(&expiry_job_for!/1)
        |> scheduled_at_by_job_id()

      reconcile_jobs_before =
        create_reconcile_jobs(subject, 50, "operator-pause-reconcile", now)

      reconcile_schedule_before = scheduled_at_by_job_id(reconcile_jobs_before)

      {:ok, pause_result} =
        OperatorCommands.pause(subject.id,
          reason: "operator hold",
          trace_id: "trace-stage9-operator-pause",
          causation_id: "cause-stage9-operator-pause",
          actor_ref: %{kind: :operator},
          now: now
        )

      paused_dispatch_jobs = subject_jobs(subject.id, @dispatch_worker, "dispatch")

      paused_probe =
        LowerGatewayStub.with_handlers(%{}, fn ->
          result = DispatchProbe.perform_dispatch!(hd(dispatch_executions).id)
          refute_lower_gateway_call!()
          result
        end)

      decision_schedule_after_pause =
        decisions
        |> Enum.map(&expiry_job_for!/1)
        |> scheduled_at_by_job_id()

      reconcile_schedule_after_pause =
        subject_jobs(subject.id, @reconcile_worker, "reconcile")
        |> scheduled_at_by_job_id()

      {:ok, resume_result} =
        OperatorCommands.resume(subject.id,
          trace_id: "trace-stage9-operator-resume",
          causation_id: "cause-stage9-operator-resume",
          actor_ref: %{kind: :operator},
          now: DateTime.add(now, 5, :second)
        )

      resumed_dispatch_schedule =
        subject_jobs(subject.id, @dispatch_worker, "dispatch")
        |> scheduled_at_by_job_id()

      decision_schedule_after_resume =
        decisions
        |> Enum.map(&expiry_job_for!/1)
        |> scheduled_at_by_job_id()

      reconcile_schedule_after_resume =
        subject_jobs(subject.id, @reconcile_worker, "reconcile")
        |> scheduled_at_by_job_id()

      {:ok, saturation_subject} =
        ingest_subject("stack-lab:operator-pause-heavy",
          installation_id: "inst-heavy"
        )

      bulk_insert_dispatch_jobs!(saturation_subject, 10_000,
        tenant_id: "tenant-heavy",
        installation_id: "inst-heavy",
        scheduled_at: DateTime.add(now, 1, :hour),
        prefix: "operator-pause-heavy"
      )

      {:ok, saturation_pause_result} =
        OperatorCommands.pause(saturation_subject.id,
          reason: "bulk pause",
          trace_id: "trace-stage9-operator-pause-heavy",
          causation_id: "cause-stage9-operator-pause-heavy",
          actor_ref: %{kind: :operator},
          now: DateTime.add(now, 10, :second)
        )

      {:ok, peer_subject} =
        ingest_subject("stack-lab:operator-pause-peer",
          installation_id: "inst-peer"
        )

      {:ok, peer_execution} =
        dispatch_execution(peer_subject, "operator-pause-peer",
          tenant_id: "tenant-peer",
          installation_id: "inst-peer",
          scheduled_at: DateTime.add(now, 2, :hour)
        )

      peer_dispatch =
        LowerGatewayStub.with_handlers(
          %{
            lookup_submission: fn [_submission_dedupe_key, _tenant_id] -> :never_seen end,
            dispatch: fn [_claim] ->
              {:accepted,
               %{
                 "submission_ref" => %{"id" => "submission-peer"},
                 "lower_receipt" => %{"state" => "accepted", "run_id" => "run-peer"}
               }}
            end
          },
          fn -> DispatchProbe.perform_dispatch!(peer_execution.id) end
        )

      {:ok,
       %{
         case: :operator_pause_during_active_execution,
         scenario: 9,
         pause: %{
           result_status: pause_result.status,
           paused_dispatch_job_count: length(paused_dispatch_jobs),
           paused_dispatch_metadata_count:
             Enum.count(paused_dispatch_jobs, &paused_dispatch_job?/1),
           decision_schedule_preserved?:
             decision_schedule_after_pause == decision_schedule_before,
           reconcile_schedule_preserved?:
             reconcile_schedule_after_pause == reconcile_schedule_before
         },
         resume: %{
           result_status: resume_result.status,
           dispatch_schedule_restored?: resumed_dispatch_schedule == dispatch_schedule_before,
           decision_schedule_preserved?:
             decision_schedule_after_resume == decision_schedule_before,
           reconcile_schedule_preserved?:
             reconcile_schedule_after_resume == reconcile_schedule_before
         },
         paused_probe: %{
           worker_result: paused_probe.worker_result,
           classification: paused_probe.classification,
           job_status: paused_probe.job_status,
           execution_state: paused_probe.execution.dispatch_state
         },
         saturation: %{
           paused_dispatch_job_count: length(saturation_pause_result.details.paused_job_ids),
           peer_dispatch: %{
             classification: peer_dispatch.classification,
             worker_result: peer_dispatch.worker_result,
             job_status: peer_dispatch.job_status
           }
         }
       }}
    end)
  end

  def run_case(:operator_cancel_during_active_execution) do
    MezzanineSubstrate.with_store(:operator_cancel_during_active_execution, fn _repo_config ->
      {:ok, subject} = ingest_subject("stack-lab:operator-cancel")
      {:ok, execution} = awaiting_receipt_execution(subject, "operator-cancel")

      DispatchProbe.delete_dispatch_jobs!(execution.id)

      lifecycle_count_before = lifecycle_advance_count(subject.id)

      {:ok, cancel_result} =
        OperatorCommands.cancel(subject.id,
          reason: "operator cancel",
          trace_id: "trace-stage9-operator-cancel",
          causation_id: "cause-stage9-operator-cancel",
          actor_ref: %{kind: :operator}
        )

      cancel_job = cancel_job_for!(execution.id)

      lower_cancel =
        LowerGatewayStub.with_handlers(
          %{
            request_cancel: fn [submission_ref, tenant_id, reason] ->
              send(self(), {:request_cancel_observed, submission_ref, tenant_id, reason})
              {:cancelled, ~U[2026-04-17 18:00:00.000000Z]}
            end
          },
          fn ->
            worker_result =
              ExecutionCancelWorker.perform(%Job{
                id: cancel_job.id,
                attempt: 1,
                queue: cancel_job.queue,
                args: cancel_job.args
              })

            observed_call =
              receive do
                {:request_cancel_observed, submission_ref, tenant_id, reason} ->
                  %{
                    submission_ref: submission_ref,
                    tenant_id: tenant_id,
                    reason: reason
                  }
              after
                50 ->
                  nil
              end

            %{worker_result: worker_result, observed_call: observed_call}
          end
        )

      late_receipt_result =
        ExecutionReceiptWorker.perform(%Job{
          id: System.unique_integer([:positive]),
          attempt: 1,
          queue: "receipt",
          args: %{
            "execution_id" => execution.id,
            "outcome" => %{
              "receipt_id" => "late-receipt-operator-cancel",
              "status" => "ok",
              "lower_receipt" => %{
                "state" => "completed",
                "run_id" => "run-operator-cancel"
              },
              "normalized_outcome" => %{"result" => "already completed"},
              "observed_at" => "2026-04-17T18:05:00Z"
            }
          }
        })

      subject_after_late_receipt = fetch_subject!(subject.id)
      lifecycle_count_after = lifecycle_advance_count(subject.id)

      {:ok,
       %{
         case: :operator_cancel_during_active_execution,
         scenario: 16,
         cancel: %{
           result_status: cancel_result.status,
           cancelled_execution_ids: cancel_result.details.cancelled_execution_ids,
           cancel_job_ids: Enum.map(cancel_result.details.cancel_job_refs, & &1.job_id),
           execution_state: execution_state!(execution.id)
         },
         lower_cancel: lower_cancel,
         late_receipt: %{
           worker_result: late_receipt_result,
           audit_kinds:
             execution_audit_kinds(execution.id, ["post_cancel_receipt", "reconciliation_warning"]),
           subject_lifecycle_state: subject_after_late_receipt.lifecycle_state,
           lifecycle_advance_delta: lifecycle_count_after - lifecycle_count_before
         }
       }}
    end)
  end

  def run_case(:decision_sla_expiry) do
    MezzanineSubstrate.with_store(:decision_sla_expiry, fn _repo_config ->
      {:ok, subject} = ingest_subject("stack-lab:decision-expiry")
      {:ok, execution} = dispatch_execution(subject, "decision-expiry")

      early_resolution = prove_early_decision_resolution(subject, execution)
      expiry_resolution = prove_expiry_resolution(subject, execution)
      non_pending_expiry = prove_non_pending_expiry_discard(subject, execution)
      race_resolution = prove_resolution_vs_expiry_race(subject, execution)

      {:ok,
       %{
         case: :decision_sla_expiry,
         scenario: 17,
         early_resolution: early_resolution,
         expiry_resolution: expiry_resolution,
         non_pending_expiry: non_pending_expiry,
         race_resolution: race_resolution
       }}
    end)
  end

  def run_case(:parallel_join_closure) do
    MezzanineSubstrate.with_store(:parallel_join_closure, fn _repo_config ->
      installation =
        compile_join_pack!()
        |> activate_registration!()
        |> install_pack!(
          tenant_id: "tenant-stage9-join",
          environment: "stage9",
          binding_config: binding_config_for("triage_child", "github_write")
        )

      {:ok, subject} = ingest_join_subject(installation.id)

      {:ok, atomic_barrier} =
        ParallelBarrier.open(%{
          subject_id: subject.id,
          barrier_key: "fanout:atomic-close",
          join_step_ref: "triage_join",
          expected_children: 2,
          trace_id: "trace-stage9-join"
        })

      atomic_progress =
        atomic_barrier_progresses(atomic_barrier.id)
        |> Enum.map(fn {:ok, progress} -> progress end)

      {:ok, atomic_barrier_after} = ParallelBarrier.fetch(atomic_barrier.id)

      {:ok, worker_barrier} =
        ParallelBarrier.open(%{
          subject_id: subject.id,
          barrier_key: "fanout:receipt-join",
          join_step_ref: "triage_join",
          expected_children: 2,
          trace_id: "trace-stage9-join"
        })

      executions =
        create_join_executions(subject, installation, worker_barrier.id)

      receipt_results =
        executions
        |> Task.async_stream(
          fn %{execution_id: execution_id, outcome: outcome} ->
            perform_receipt(execution_id, outcome)
          end,
          ordered: false,
          timeout: 5_000,
          max_concurrency: 2
        )
        |> Enum.map(fn {:ok, result} -> result end)

      duplicate_receipt_results =
        executions
        |> Enum.map(fn %{execution_id: execution_id, outcome: outcome} ->
          perform_receipt(execution_id, outcome)
        end)

      {:ok, worker_barrier_before_join} = ParallelBarrier.fetch(worker_barrier.id)
      subject_before_join = fetch_subject!(subject.id)
      join_job_ids = join_job_ids_for(subject.id, worker_barrier.id)

      :ok = perform_join_advance(subject.id, worker_barrier.id)

      subject_after_join = fetch_subject!(subject.id)
      {:ok, worker_barrier_after_join} = ParallelBarrier.fetch(worker_barrier.id)

      {:ok,
       %{
         case: :parallel_join_closure,
         scenario: 23,
         atomic_close: %{
           progresses: atomic_progress,
           completion_row_count: barrier_completion_count(atomic_barrier.id),
           duplicate_progress_count: Enum.count(atomic_progress, & &1.duplicate?),
           closer_count: Enum.count(atomic_progress, & &1.closed_by_me),
           barrier: barrier_summary(atomic_barrier_after),
           over_increment_attempt:
             ParallelBarrier.record_child_completion(atomic_barrier.id, Ecto.UUID.generate())
         },
         worker_integration: %{
           receipt_results: receipt_results,
           duplicate_receipt_results: duplicate_receipt_results,
           completion_row_count: barrier_completion_count(worker_barrier.id),
           barrier_before_join: barrier_summary(worker_barrier_before_join),
           join_job_ids: join_job_ids,
           subject_before_join: subject_before_join,
           subject_after_join: subject_after_join,
           barrier_after_join: barrier_summary(worker_barrier_after_join),
           join_transition_count: join_transition_count(subject.id)
         }
       }}
    end)
  end

  @spec run_case(
          :restart_during_dispatch_ambiguity
          | :lower_gateway_outage_recovery
          | :startup_reconciliation_deduplication
        ) :: {:ok, map()} | {:error, term()}
  def run_case(:restart_during_dispatch_ambiguity) do
    with {:ok, result} <-
           MezzanineRestartRecovery.run_case(:dispatching_retry_after_restart) do
      {:ok,
       %{
         case: :restart_during_dispatch_ambiguity,
         scenario: 18,
         recovered_count: result.after_restart.recovered_count,
         preserved_submission_dedupe_key: result.before_restart.submission_dedupe_key,
         final_dispatch: result.final
       }}
    end
  end

  def run_case(:lower_gateway_outage_recovery) do
    MezzanineSubstrate.with_store(:lower_gateway_outage_recovery, fn _repo_config ->
      {:ok, dispatch_subject} = ingest_subject("stack-lab:dispatch-outage")
      {:ok, dispatch_execution} = dispatch_execution(dispatch_subject, "dispatch-outage")

      {:ok, reconcile_subject} = ingest_subject("stack-lab:reconcile-outage")

      {:ok, reconcile_execution} =
        awaiting_receipt_execution(reconcile_subject, "reconcile-outage")

      opened_circuit = open_circuit!(@tenant_id, @installation_id)

      {dispatch_worker_result, reconcile_worker_result} =
        LowerGatewayStub.with_handlers(%{}, fn ->
          dispatch_result = DispatchProbe.perform_dispatch!(dispatch_execution.id)
          reconcile_result = perform_reconcile(reconcile_execution.id)

          refute_lower_gateway_call!()

          {dispatch_result, reconcile_result}
        end)

      insert_runtime_lease!(@installation_id, "scheduler-node-a")

      probe_now = DateTime.add(opened_circuit.opened_at || DateTime.utc_now(), 31, :second)
      circuit_before_probe = LowerGatewayCircuit.fetch(@tenant_id, @installation_id, repo: Repo)

      probe_results =
        [
          {"scheduler-node-a",
           LowerGatewayCircuit.permit(@tenant_id, @installation_id,
             now: probe_now,
             probe_owner: "scheduler-node-a",
             allow_probe_without_runtime_lease?: false,
             jitter_ms: 0,
             repo: Repo
           )},
          {"scheduler-node-b",
           LowerGatewayCircuit.permit(@tenant_id, @installation_id,
             now: probe_now,
             probe_owner: "scheduler-node-b",
             allow_probe_without_runtime_lease?: false,
             jitter_ms: 0,
             repo: Repo
           )},
          {"scheduler-node-c",
           LowerGatewayCircuit.permit(@tenant_id, @installation_id,
             now: probe_now,
             probe_owner: "scheduler-node-c",
             allow_probe_without_runtime_lease?: false,
             jitter_ms: 0,
             repo: Repo
           )}
        ]

      {:ok,
       %{
         case: :lower_gateway_outage_recovery,
         scenario: 26,
         circuit_before_probe: circuit_before_probe,
         dispatch_worker: %{
           worker_result: dispatch_worker_result.worker_result,
           job_status: dispatch_worker_result.job_status,
           classification: dispatch_worker_result.classification
         },
         reconcile_worker: %{
           worker_result: reconcile_worker_result,
           receipt_job_ids: reconcile_job_ids_for(reconcile_execution.id)
         },
         probe_results: probe_results,
         circuit_after_probe: LowerGatewayCircuit.fetch(@tenant_id, @installation_id, repo: Repo)
       }}
    end)
  end

  def run_case(:startup_reconciliation_deduplication) do
    MezzanineSubstrate.with_store(:startup_reconciliation_deduplication, fn _repo_config ->
      {:ok, subject} = ingest_subject("stack-lab:startup-reconciliation")
      {:ok, execution} = awaiting_receipt_execution(subject, "startup-reconciliation")
      now = DateTime.add(DateTime.utc_now(), 10, :second)

      results =
        1..3
        |> Task.async_stream(
          fn launcher ->
            ReconcileOnStart.reconcile(@installation_id, now,
              actor_ref: %{kind: :runtime_scheduler, launcher: launcher}
            )
          end,
          ordered: false,
          timeout: 5_000,
          max_concurrency: 3
        )
        |> Enum.map(fn {:ok, {:ok, summary}} -> summary end)

      {:ok,
       %{
         case: :startup_reconciliation_deduplication,
         scenario: 27,
         launcher_count: length(results),
         summary_reconcile_counts: Enum.map(results, & &1.reconcile_enqueued_count),
         summary_execution_ids: Enum.map(results, &Enum.sort(&1.reconcile_execution_ids)),
         reconcile_job_ids: reconcile_job_ids_for(execution.id)
       }}
    end)
  end

  defp compile_join_pack! do
    manifest = %Manifest{
      pack_slug: :stage9_join_drill,
      version: "1.0.0",
      subject_kind_specs: [
        %SubjectKindSpec{name: :linear_coding_ticket}
      ],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: :linear_coding_ticket,
          initial_state: :awaiting_join,
          terminal_states: [:paid],
          transitions: [
            %{from: :awaiting_join, to: :paid, trigger: {:join_completed, :triage_join}}
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: :triage_child,
          runtime_class: :session,
          placement_ref: :local_runner,
          execution_params: %{timeout_ms: 300_000}
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: :active_tickets, subject_kinds: [:linear_coding_ticket]}
      ]
    }

    case Compiler.compile(manifest) do
      {:ok, %CompiledPack{} = compiled_pack} ->
        compiled_pack

      {:error, errors} ->
        raise "failed to compile stage9 join proof pack: #{inspect(errors)}"
    end
  end

  defp activate_registration!(compiled_pack) do
    compiled_pack
    |> MezzanineConfigRegistry.register_pack!()
    |> PackRegistration.activate()
    |> case do
      {:ok, registration} ->
        registration

      {:error, error} ->
        raise "failed to activate stage9 join proof pack: #{inspect(error)}"
    end
  end

  defp install_pack!(registration, opts) when is_list(opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    environment = Keyword.fetch!(opts, :environment)
    binding_config = Keyword.fetch!(opts, :binding_config)

    {:ok, installation} =
      MezzanineConfigRegistry.create_installation(%{
        tenant_id: tenant_id,
        environment: environment,
        pack_registration_id: registration.id
      })

    {:ok, installation} = MezzanineConfigRegistry.activate_installation(installation)
    {:ok, installation} = MezzanineConfigRegistry.update_bindings(installation, binding_config)
    installation
  end

  defp binding_config_for(recipe_ref, connector_key) do
    %{
      "execution_bindings" => %{
        recipe_ref => %{
          "placement_ref" => "local_runner",
          "execution_params" => %{"timeout_ms" => 300_000},
          "connector_bindings" => %{
            connector_key => %{"connector_key" => "#{connector_key}_api"}
          }
        }
      }
    }
  end

  defp binding_snapshot_for(installation, recipe_ref) do
    installation
    |> Map.fetch!(:binding_config)
    |> get_in(["execution_bindings", recipe_ref])
    |> Map.take(["placement_ref", "execution_params", "connector_bindings"])
  end

  defp ingest_join_subject(installation_id) do
    SubjectRecord.ingest(%{
      installation_id: installation_id,
      source_ref: "stack-lab:parallel-join",
      subject_kind: "linear_coding_ticket",
      lifecycle_state: "awaiting_join",
      payload: %{"ticket_id" => "T-23"},
      trace_id: "trace-stage9-join",
      causation_id: "cause-stage9-join",
      actor_ref: %{kind: :intake}
    })
  end

  defp atomic_barrier_progresses(barrier_id) do
    child_one = Ecto.UUID.generate()
    child_two = Ecto.UUID.generate()

    [child_one, child_one, child_two, child_two]
    |> Task.async_stream(
      fn child_execution_id ->
        ParallelBarrier.record_child_completion(barrier_id, child_execution_id)
      end,
      ordered: false,
      timeout: 5_000,
      max_concurrency: 4
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  defp create_join_executions(subject, installation, barrier_id) do
    [
      %{suffix: "join-a", receipt_id: "receipt-join-a", run_id: "run-join-a"},
      %{suffix: "join-b", receipt_id: "receipt-join-b", run_id: "run-join-b"}
    ]
    |> Enum.map(fn %{suffix: suffix, receipt_id: receipt_id, run_id: run_id} ->
      {:ok, execution} =
        dispatch_join_execution(subject, installation, barrier_id, suffix)

      {:ok, accepted_execution} =
        ExecutionRecord.record_accepted(execution, %{
          submission_ref: %{"id" => "sub-#{suffix}"},
          lower_receipt: %{"state" => "accepted", "run_id" => run_id},
          trace_id: execution.trace_id,
          causation_id: "cause-accepted-#{suffix}",
          actor_ref: %{kind: :dispatcher}
        })

      %{
        execution_id: accepted_execution.id,
        outcome: join_outcome(receipt_id, run_id, suffix)
      }
    end)
  end

  defp dispatch_join_execution(subject, installation, barrier_id, suffix) do
    ExecutionRecord.dispatch(%{
      tenant_id: installation.tenant_id,
      installation_id: installation.id,
      subject_id: subject.id,
      barrier_id: barrier_id,
      recipe_ref: "triage_child",
      compiled_pack_revision: installation.compiled_pack_revision,
      binding_snapshot: binding_snapshot_for(installation, "triage_child"),
      dispatch_envelope: %{"capability" => "sandbox.exec"},
      submission_dedupe_key: "#{installation.id}:triage_child:#{suffix}",
      trace_id: "trace-stage9-join",
      causation_id: "cause-#{suffix}",
      actor_ref: %{kind: :scheduler}
    })
  end

  defp join_outcome(receipt_id, run_id, suffix) do
    %{
      "receipt_id" => receipt_id,
      "status" => "ok",
      "lower_receipt" => %{
        "state" => "completed",
        "run_id" => run_id,
        "attempt_id" => "attempt-#{suffix}"
      },
      "normalized_outcome" => %{"summary" => "#{suffix} done"},
      "observed_at" => "2026-04-17T06:15:00Z"
    }
  end

  defp perform_receipt(execution_id, outcome) do
    ExecutionReceiptWorker.perform(%Oban.Job{
      id: System.unique_integer([:positive]),
      attempt: 1,
      queue: "receipt",
      args: %{"execution_id" => execution_id, "outcome" => outcome}
    })
  end

  defp perform_join_advance(subject_id, barrier_id) do
    JoinAdvanceWorker.perform(%Oban.Job{
      id: System.unique_integer([:positive]),
      attempt: 1,
      queue: "join",
      args: %{"subject_id" => subject_id, "barrier_id" => barrier_id}
    })
  end

  defp fetch_subject!(subject_id) do
    %{rows: [[id, lifecycle_state, status, status_reason, row_version]]} =
      Repo.query!(
        """
        SELECT id, lifecycle_state, status, status_reason, row_version
        FROM subject_records
        WHERE id = $1::uuid
        """,
        [dump_uuid!(subject_id)]
      )

    %{
      id: load_uuid!(id),
      lifecycle_state: lifecycle_state,
      status: status,
      status_reason: status_reason,
      row_version: row_version
    }
  end

  defp barrier_completion_count(barrier_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT COUNT(*)
        FROM parallel_barrier_completions
        WHERE barrier_id = $1::uuid
        """,
        [dump_uuid!(barrier_id)]
      )

    count
  end

  defp barrier_summary(barrier) do
    %{
      barrier_id: barrier.id,
      expected_children: barrier.expected_children,
      completed_children: barrier.completed_children,
      status: barrier.status
    }
  end

  defp join_job_ids_for(subject_id, barrier_id) do
    Repo.all(Oban.Job)
    |> Enum.filter(fn job ->
      job.worker == Oban.Worker.to_string(JoinAdvanceWorker) and
        job.args["subject_id"] == subject_id and
        job.args["barrier_id"] == barrier_id
    end)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp join_transition_count(subject_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT COUNT(*)
        FROM audit_facts
        WHERE subject_id = $1
          AND fact_kind = 'lifecycle_advanced'
          AND payload->'trigger'->>'kind' = 'join_completed'
        """,
        [subject_id]
      )

    count
  end

  defp create_dispatch_executions(subject, count, prefix, opts) do
    1..count
    |> Enum.map(fn index ->
      suffix = "#{prefix}-#{index}"
      {:ok, execution} = dispatch_execution(subject, suffix, opts)
      execution
    end)
  end

  defp create_pending_decision(subject, execution, suffix, required_by) do
    {:ok, decision} =
      DecisionCommands.create_pending(%{
        installation_id: subject.installation_id,
        subject_id: subject.id,
        execution_id: execution.id,
        decision_kind: "human_review_required:#{suffix}",
        required_by: required_by,
        trace_id: "trace-decision-#{suffix}",
        causation_id: "cause-decision-#{suffix}",
        actor_ref: %{kind: :scheduler}
      })

    decision
  end

  defp create_reconcile_jobs(subject, count, prefix, now) do
    1..count
    |> Enum.map(fn index ->
      suffix = "#{prefix}-#{index}"
      {:ok, execution} = awaiting_receipt_execution(subject, suffix)
      DispatchProbe.delete_dispatch_jobs!(execution.id)

      scheduled_at = DateTime.add(now, index * 60, :second)

      Repo.insert!(
        Job.new(
          %{"execution_id" => execution.id},
          worker: @reconcile_worker,
          queue: "reconcile",
          scheduled_at: scheduled_at
        )
      )
    end)
  end

  defp subject_jobs(subject_id, worker, queue) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT job.id, job.state, job.scheduled_at, COALESCE(job.meta, '{}'::jsonb)
        FROM oban_jobs AS job
        JOIN execution_records AS execution
          ON execution.id::text = job.args->>'execution_id'
        WHERE execution.subject_id = $1::uuid
          AND job.worker = $2
          AND job.queue = $3
        ORDER BY job.id
        """,
        [dump_uuid!(subject_id), worker, queue]
      )

    Enum.map(rows, fn [id, state, scheduled_at, meta] ->
      %{
        id: id,
        state: state,
        scheduled_at: normalize_scheduled_at(scheduled_at),
        meta: meta
      }
    end)
  end

  defp scheduled_at_by_job_id(jobs) do
    Map.new(jobs, fn job -> {job.id, normalize_scheduled_at(job.scheduled_at)} end)
  end

  defp paused_dispatch_job?(job) do
    normalize_scheduled_at(job.scheduled_at) == @pause_sentinel and
      is_binary(job.meta["pause_scheduled_at"])
  end

  defp normalize_scheduled_at(%DateTime{} = scheduled_at), do: scheduled_at

  defp normalize_scheduled_at(%NaiveDateTime{} = scheduled_at) do
    DateTime.from_naive!(scheduled_at, "Etc/UTC")
  end

  defp bulk_insert_dispatch_jobs!(subject, count, opts) do
    tenant_id = Keyword.fetch!(opts, :tenant_id)
    installation_id = Keyword.fetch!(opts, :installation_id)
    scheduled_at = Keyword.fetch!(opts, :scheduled_at)
    prefix = Keyword.fetch!(opts, :prefix)

    execution_ids = Enum.map(1..count, fn _ -> Ecto.UUID.generate() |> dump_uuid!() end)
    submission_keys = Enum.map(1..count, &"#{installation_id}:#{prefix}:#{&1}")
    trace_ids = Enum.map(1..count, &"trace-#{prefix}-#{&1}")
    causation_ids = Enum.map(1..count, &"cause-#{prefix}-#{&1}")

    Repo.query!(
      """
      WITH rows AS (
        SELECT unnest($1::uuid[]) AS id,
               unnest($2::text[]) AS submission_key,
               unnest($3::text[]) AS trace_id,
               unnest($4::text[]) AS causation_id
      )
      INSERT INTO execution_records (
        id,
        tenant_id,
        installation_id,
        subject_id,
        recipe_ref,
        compiled_pack_revision,
        binding_snapshot,
        dispatch_envelope,
        submission_dedupe_key,
        trace_id,
        causation_id,
        dispatch_state,
        dispatch_attempt_count,
        next_dispatch_at,
        submission_ref,
        lower_receipt,
        last_dispatch_error_payload,
        supersession_depth,
        row_version,
        inserted_at,
        updated_at
      )
      SELECT rows.id,
             $5,
             $6,
             $7::uuid,
             'triage_ticket',
             7,
             $8::jsonb,
             $9::jsonb,
             rows.submission_key,
             rows.trace_id,
             rows.causation_id,
             'pending_dispatch',
             0,
             $10,
             '{}'::jsonb,
             '{}'::jsonb,
             '{}'::jsonb,
             0,
             1,
             $10,
             $10
      FROM rows
      """,
      [
        execution_ids,
        submission_keys,
        trace_ids,
        causation_ids,
        tenant_id,
        installation_id,
        dump_uuid!(subject.id),
        @dispatch_snapshot,
        %{"capability" => "sandbox.exec"},
        scheduled_at
      ]
    )

    Repo.query!(
      """
      INSERT INTO oban_jobs (
        args,
        meta,
        state,
        max_attempts,
        queue,
        worker,
        errors,
        attempt,
        tags,
        scheduled_at
      )
      SELECT jsonb_build_object('execution_id', execution_id::text),
             '{}'::jsonb,
             'scheduled',
             20,
             'dispatch',
             $2,
             ARRAY[]::jsonb[],
             0,
             ARRAY[]::text[],
             $3
      FROM unnest($1::uuid[]) AS execution_id
      """,
      [execution_ids, @dispatch_worker, scheduled_at]
    )

    :ok
  end

  defp cancel_job_for!(execution_id) do
    Repo.all(Job)
    |> Enum.find(fn job ->
      job.worker == @cancel_worker and job.args["execution_id"] == execution_id
    end)
    |> case do
      nil -> raise "expected a cancel job for execution #{execution_id}"
      job -> job
    end
  end

  defp execution_state!(execution_id) do
    {:ok, execution} = Ash.get(ExecutionRecord, execution_id)
    execution.dispatch_state
  end

  defp execution_audit_kinds(execution_id, kinds) do
    %{rows: rows} =
      Repo.query!(
        """
        SELECT fact_kind
        FROM audit_facts
        WHERE execution_id = $1
          AND fact_kind = ANY($2)
        ORDER BY occurred_at ASC, inserted_at ASC
        """,
        [execution_id, kinds]
      )

    Enum.map(rows, fn [fact_kind] -> fact_kind end)
  end

  defp lifecycle_advance_count(subject_id) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT COUNT(*)
        FROM audit_facts
        WHERE subject_id = $1
          AND fact_kind = 'lifecycle_advanced'
        """,
        [subject_id]
      )

    count
  end

  defp prove_early_decision_resolution(subject, execution) do
    decision =
      create_pending_decision(
        subject,
        execution,
        "decision-early",
        ~U[2026-04-20 00:00:00.000000Z]
      )

    expiry_job = expiry_job_for!(decision)

    {:ok, resolved_decision} =
      DecisionCommands.decide(decision.id, %{
        decision_value: "approve",
        reason: "resolved before expiry",
        trace_id: "trace-decision-resolve-early",
        causation_id: "cause-decision-resolve-early",
        actor_ref: %{kind: :operator}
      })

    %{
      lifecycle_state: resolved_decision.lifecycle_state,
      expiry_job_id_cleared?: is_nil(resolved_decision.expiry_job_id),
      expiry_job_deleted?: not expiry_job_exists?(expiry_job.id)
    }
  end

  defp prove_expiry_resolution(subject, execution) do
    decision =
      create_pending_decision(
        subject,
        execution,
        "decision-expire",
        ~U[2026-04-14 00:00:00.000000Z]
      )

    expiry_job = expiry_job_for!(decision)

    worker_result =
      DecisionExpiryWorker.perform(%Job{
        id: expiry_job.id,
        attempt: 1,
        queue: expiry_job.queue,
        args: expiry_job.args
      })

    decision_after = decision_summary!(decision.id)

    %{
      worker_result: worker_result,
      lifecycle_state: decision_after.lifecycle_state,
      expiry_job_id_cleared?: is_nil(decision_after.expiry_job_id)
    }
  end

  defp prove_non_pending_expiry_discard(subject, execution) do
    decision =
      create_pending_decision(
        subject,
        execution,
        "decision-discard",
        ~U[2026-04-20 00:00:00.000000Z]
      )

    expiry_job = expiry_job_for!(decision)

    {:ok, _resolved_decision} =
      DecisionCommands.decide(decision.id, %{
        decision_value: "approve",
        reason: "resolved before worker",
        trace_id: "trace-decision-resolve-discard",
        causation_id: "cause-decision-resolve-discard",
        actor_ref: %{kind: :operator}
      })

    %{
      worker_result:
        DecisionExpiryWorker.perform(%Job{
          id: expiry_job.id,
          attempt: 1,
          queue: expiry_job.queue,
          args: expiry_job.args
        })
    }
  end

  defp prove_resolution_vs_expiry_race(subject, execution) do
    decision =
      create_pending_decision(
        subject,
        execution,
        "decision-race",
        ~U[2026-04-14 00:00:00.000000Z]
      )

    expiry_job = expiry_job_for!(decision)
    parent = self()

    decide_task =
      Task.async(fn ->
        send(parent, {:race_ready, :decide})

        receive do
          :race_go ->
            DecisionCommands.decide(decision.id, %{
              decision_value: "approve",
              reason: "race resolution",
              trace_id: "trace-decision-race-resolve",
              causation_id: "cause-decision-race-resolve",
              actor_ref: %{kind: :operator}
            })
        end
      end)

    expire_task =
      Task.async(fn ->
        send(parent, {:race_ready, :expire})

        receive do
          :race_go ->
            DecisionExpiryWorker.perform(%Job{
              id: expiry_job.id,
              attempt: 1,
              queue: expiry_job.queue,
              args: expiry_job.args
            })
        end
      end)

    await_race_ready([:decide, :expire], [])
    send(decide_task.pid, :race_go)
    send(expire_task.pid, :race_go)

    decide_result = Task.await(decide_task, 5_000)
    expire_result = Task.await(expire_task, 5_000)
    decision_after = decision_summary!(decision.id)

    %{
      decide_result: normalize_decision_result(decide_result),
      expire_result: expire_result,
      lifecycle_state: decision_after.lifecycle_state,
      expiry_job_id_cleared?: is_nil(decision_after.expiry_job_id)
    }
  end

  defp await_race_ready([], ready), do: ready

  defp await_race_ready(pending, ready) do
    receive do
      {:race_ready, kind} ->
        await_race_ready(List.delete(pending, kind), [kind | ready])
    after
      1_000 ->
        raise "timed out waiting for race tasks: #{inspect(pending)}"
    end
  end

  defp normalize_decision_result({:ok, decision}), do: {:ok, decision.lifecycle_state}
  defp normalize_decision_result({:error, reason}), do: {:error, reason}

  defp expiry_job_for!(decision_or_id) do
    decision_id =
      case decision_or_id do
        %{id: id} -> id
        id when is_binary(id) -> id
      end

    Repo.all(Job)
    |> Enum.find(fn job ->
      job.worker == @decision_expiry_worker and job.args["decision_id"] == decision_id
    end)
    |> case do
      nil -> raise "expected a decision expiry job for decision #{decision_id}"
      job -> job
    end
  end

  defp expiry_job_exists?(job_id) do
    Repo.all(Job)
    |> Enum.any?(&(&1.id == job_id))
  end

  defp decision_summary!(decision_id) do
    %{rows: [[id, lifecycle_state, decision_value, expiry_job_id]]} =
      Repo.query!(
        """
        SELECT id, lifecycle_state, decision_value, expiry_job_id
        FROM decision_records
        WHERE id = $1::uuid
        """,
        [dump_uuid!(decision_id)]
      )

    %{
      id: load_uuid!(id),
      lifecycle_state: lifecycle_state,
      decision_value: decision_value,
      expiry_job_id: expiry_job_id
    }
  end

  defp ingest_subject(source_ref, opts \\ []) do
    installation_id = Keyword.get(opts, :installation_id, @installation_id)
    lifecycle_state = Keyword.get(opts, :lifecycle_state, "queued")

    SubjectRecord.ingest(%{
      installation_id: installation_id,
      source_ref: source_ref,
      subject_kind: "linear_coding_ticket",
      lifecycle_state: lifecycle_state,
      payload: %{},
      trace_id: "trace-subject-#{source_ref}",
      causation_id: "cause-subject-#{source_ref}",
      actor_ref: %{kind: :intake}
    })
  end

  defp dispatch_execution(subject, suffix, opts \\ []) do
    tenant_id = Keyword.get(opts, :tenant_id, @tenant_id)
    installation_id = Keyword.get(opts, :installation_id, subject.installation_id)

    ExecutionRecord.dispatch(%{
      tenant_id: tenant_id,
      installation_id: installation_id,
      subject_id: subject.id,
      recipe_ref: "triage_ticket",
      compiled_pack_revision: 7,
      binding_snapshot: @dispatch_snapshot,
      dispatch_envelope: %{"capability" => "sandbox.exec"},
      submission_dedupe_key: "#{installation_id}:exec:#{suffix}",
      trace_id: "trace-#{suffix}",
      causation_id: "cause-#{suffix}",
      actor_ref: %{kind: :scheduler}
    })
  end

  defp awaiting_receipt_execution(subject, suffix, opts \\ []) do
    with {:ok, execution} <- dispatch_execution(subject, suffix, opts) do
      ExecutionRecord.record_accepted(execution, %{
        submission_ref: %{"id" => "sub-#{suffix}"},
        lower_receipt: %{"state" => "accepted", "run_id" => "run-#{suffix}"},
        trace_id: execution.trace_id,
        causation_id: "cause-accepted-#{suffix}",
        actor_ref: %{kind: :dispatcher}
      })
    end
  end

  defp open_circuit!(tenant_id, installation_id) do
    Enum.reduce(1..5, nil, fn _, _acc ->
      {:ok, circuit} =
        LowerGatewayCircuit.record_failure(tenant_id, installation_id,
          now: DateTime.utc_now(),
          repo: Repo
        )

      circuit
    end)
  end

  defp perform_reconcile(execution_id) do
    ExecutionReconcileWorker.perform(%Oban.Job{
      id: 43,
      attempt: 1,
      queue: "reconcile",
      args: %{"execution_id" => execution_id}
    })
  end

  defp reconcile_job_ids_for(execution_id) do
    Repo.all(Job)
    |> Enum.filter(fn job ->
      job.worker == Oban.Worker.to_string(Mezzanine.ExecutionReconcileWorker) and
        job.args["execution_id"] == execution_id
    end)
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp insert_runtime_lease!(installation_id, holder) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    Repo.query!(
      """
      INSERT INTO installation_runtime_leases (
        installation_id,
        holder,
        lease_id,
        epoch,
        compiled_pack_revision,
        expires_at,
        inserted_at,
        updated_at
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
      ON CONFLICT (installation_id) DO UPDATE
      SET holder = EXCLUDED.holder,
          lease_id = EXCLUDED.lease_id,
          epoch = EXCLUDED.epoch,
          compiled_pack_revision = EXCLUDED.compiled_pack_revision,
          expires_at = EXCLUDED.expires_at,
          updated_at = EXCLUDED.updated_at
      """,
      [
        installation_id,
        holder,
        "lease-#{holder}",
        1,
        7,
        DateTime.add(now, 60, :second),
        now
      ]
    )
  end

  defp refute_lower_gateway_call! do
    receive do
      {:stack_lab_lower_gateway, operation, args} ->
        raise "expected open circuit to suppress lower gateway calls, got #{inspect({operation, args})}"
    after
      25 ->
        :ok
    end
  end

  defp dump_uuid!(uuid), do: Ecto.UUID.dump!(uuid)
  defp load_uuid!(uuid), do: Ecto.UUID.load!(uuid)
end
