defmodule StackLab.CitadelSpineHarness.GovernedRun do
  @moduledoc false

  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Execution.{Dispatcher, DispatchOutboxEntry, ExecutionRecord}
  alias Mezzanine.Lifecycle.{Evaluator, SubjectSnapshot}
  alias Mezzanine.Objects.SubjectRecord

  alias Mezzanine.Pack.{
    CompiledPack,
    Compiler,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    ProjectionSpec,
    Registry,
    SubjectKindSpec
  }

  alias StackLab.CitadelSpineHarness.MezzanineSubstrate

  @binding_config %{
    "execution_bindings" => %{
      "expense_capture" => %{
        "placement_ref" => "local_runner",
        "execution_params" => %{"timeout_ms" => 300_000},
        "connector_bindings" => %{
          "expense_system" => %{"connector_key" => "expenses_api"}
        }
      }
    }
  }

  @spec run_case(:expense_capture_acceptance) :: {:ok, map()}
  def run_case(:expense_capture_acceptance) do
    MezzanineSubstrate.with_store(:expense_capture_acceptance, fn _repo_config ->
      compiled_pack = compile_pack!()
      registration = activate_registration!(compiled_pack)
      installation = install_pack!(registration)

      {:ok, compiled_from_registry} =
        Registry.get_compiled_pack(installation.id, installation.compiled_pack_revision)

      {:ok, subject} = ingest_subject(installation.id)
      {:ok, execution} = dispatch_execution(subject, installation)
      accepted_now = ~U[2026-04-16 13:00:00.000000Z]

      {:ok, %{classification: :accepted, execution: accepted_execution}} =
        Dispatcher.dispatch_next(
          submit_fun: fn claimed ->
            validate_claim!(claimed, installation, subject.id)
            {:accepted, acceptance_payload(claimed)}
          end,
          actor_ref: %{kind: :dispatcher},
          now: accepted_now
        )

      outbox = fetch_outbox!(execution.id)

      {:ok, requested_transition} =
        transition_for(compiled_from_registry, subject, {:execution_requested, "expense_capture"})

      {:ok, completed_transition} =
        Evaluator.can_transition?(
          compiled_from_registry,
          snapshot(subject, requested_transition.to),
          {:execution_completed, "expense_capture"}
        )

      {:ok,
       %{
         case: :expense_capture_acceptance,
         pack: %{
           pack_slug: compiled_from_registry.pack_slug,
           subject_kind: subject.subject_kind,
           compiled_pack_revision: installation.compiled_pack_revision
         },
         dispatch: %{
           recipe_ref: accepted_execution.recipe_ref,
           classification: :accepted,
           outbox_status: outbox.status,
           submission_ref_status: accepted_execution.submission_ref["status"]
         },
         transitions: %{
           on_execution_requested: requested_transition.to,
           on_execution_completed: completed_transition.to,
           terminal_state?:
             CompiledPack.terminal_state?(
               compiled_from_registry,
               subject.subject_kind,
               completed_transition.to
             )
         }
       }}
    end)
  end

  defp compile_pack! do
    manifest = %Manifest{
      pack_slug: :expense_approval,
      version: "1.0.0",
      subject_kind_specs: [
        %SubjectKindSpec{name: :expense_request}
      ],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: :expense_request,
          initial_state: :submitted,
          terminal_states: [:paid],
          transitions: [
            %{
              from: :submitted,
              to: :processing,
              trigger: {:execution_requested, :expense_capture}
            },
            %{from: :processing, to: :paid, trigger: {:execution_completed, :expense_capture}}
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: :expense_capture,
          runtime_class: :session,
          placement_ref: :local_runner
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: :active_expenses, subject_kinds: [:expense_request]}
      ]
    }

    case Compiler.compile(manifest) do
      {:ok, %CompiledPack{} = compiled_pack} -> compiled_pack
      {:error, errors} -> raise "failed to compile non-extravaganza pack: #{inspect(errors)}"
    end
  end

  defp activate_registration!(compiled_pack) do
    compiled_pack
    |> MezzanineConfigRegistry.register_pack!()
    |> PackRegistration.activate()
    |> case do
      {:ok, registration} -> registration
      {:error, error} -> raise "failed to activate pack registration: #{inspect(error)}"
    end
  end

  defp install_pack!(registration) do
    {:ok, installation} =
      MezzanineConfigRegistry.create_installation(%{
        tenant_id: "tenant-expense",
        environment: "stage2",
        pack_registration_id: registration.id
      })

    {:ok, installation} = MezzanineConfigRegistry.activate_installation(installation)
    {:ok, installation} = MezzanineConfigRegistry.update_bindings(installation, @binding_config)
    installation
  end

  defp ingest_subject(installation_id) do
    SubjectRecord.ingest(%{
      installation_id: installation_id,
      source_ref: "expense:request:stack-lab",
      subject_kind: "expense_request",
      lifecycle_state: "submitted",
      payload: %{"amount_cents" => 12_500, "merchant" => "Atlas Travel"},
      trace_id: "trace-subject-expense-request",
      causation_id: "cause-subject-expense-request",
      actor_ref: %{kind: :intake}
    })
  end

  defp dispatch_execution(subject, installation) do
    ExecutionRecord.dispatch(%{
      installation_id: installation.id,
      subject_id: subject.id,
      recipe_ref: "expense_capture",
      compiled_pack_revision: installation.compiled_pack_revision,
      binding_snapshot: binding_snapshot_for(installation),
      dispatch_envelope: %{"capability" => "finance.expense.capture"},
      submission_dedupe_key: "#{installation.id}:expense_capture",
      trace_id: "trace-expense-capture",
      causation_id: "cause-expense-capture",
      actor_ref: %{kind: :scheduler}
    })
  end

  defp validate_claim!(claimed, installation, subject_id) do
    if claimed.installation_id != installation.id do
      raise "genericity proof claimed the wrong installation"
    end

    if claimed.subject_id != subject_id do
      raise "genericity proof claimed the wrong subject"
    end

    if claimed.compiled_pack_revision != installation.compiled_pack_revision do
      raise "genericity proof lowered with the wrong compiled-pack revision"
    end

    if claimed.binding_snapshot != binding_snapshot_for(installation) do
      raise "genericity proof lowered with the wrong binding snapshot"
    end
  end

  defp binding_snapshot_for(installation) do
    installation
    |> Map.fetch!(:binding_config)
    |> get_in(["execution_bindings", "expense_capture"])
    |> Map.take(["placement_ref", "execution_params", "connector_bindings"])
  end

  defp acceptance_payload(claimed) do
    %{
      "submission_ref" => %{
        "id" => "submission-#{claimed.submission_dedupe_key}",
        "status" => "accepted"
      },
      "lower_receipt" => %{
        "state" => "accepted",
        "ji_submission_key" => "ji-#{claimed.submission_dedupe_key}",
        "run_id" => "run-#{claimed.execution_id}"
      }
    }
  end

  defp transition_for(compiled_pack, subject, trigger_key) do
    Evaluator.can_transition?(
      compiled_pack,
      snapshot(subject, subject.lifecycle_state),
      trigger_key
    )
  end

  defp snapshot(subject, lifecycle_state) do
    SubjectSnapshot.new(%{
      subject_kind: subject.subject_kind,
      lifecycle_state: lifecycle_state,
      payload: subject.payload
    })
  end

  defp fetch_outbox!(execution_id) do
    {:ok, outbox} = DispatchOutboxEntry.by_execution_id(execution_id)
    outbox
  end
end
