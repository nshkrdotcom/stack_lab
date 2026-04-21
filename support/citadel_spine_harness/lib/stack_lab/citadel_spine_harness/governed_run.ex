defmodule StackLab.CitadelSpineHarness.GovernedRun do
  @moduledoc false

  alias Mezzanine.ConfigRegistry.PackRegistration
  alias Mezzanine.Execution.ExecutionRecord
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

  alias StackLab.CitadelSpineHarness.{DispatchProbe, LowerGatewayStub, MezzanineSubstrate}

  @spec run_case(:expense_capture_acceptance | :multi_pack_installation_routing) ::
          {:ok, map()}
  def run_case(:expense_capture_acceptance) do
    MezzanineSubstrate.with_store(:expense_capture_acceptance, fn _repo_config ->
      compiled_pack =
        compile_pack!(
          pack_slug: :expense_approval,
          version: "1.0.0",
          subject_kind: :expense_request,
          recipe_ref: :expense_capture,
          projection_name: :active_expenses,
          terminal_state: :paid
        )

      registration = activate_registration!(compiled_pack)

      installation =
        install_pack!(
          registration,
          tenant_id: "tenant-expense",
          environment: "stage2",
          binding_config: binding_config_for("expense_capture", "expense_system")
        )

      {:ok, compiled_from_registry} =
        Registry.get_compiled_pack(installation.id, installation.compiled_pack_revision)

      {:ok, subject} =
        ingest_subject(
          installation.id,
          "expense:request:stack-lab",
          "expense_request",
          %{"amount_cents" => 12_500, "merchant" => "Atlas Travel"},
          "trace-subject-expense-request",
          "cause-subject-expense-request"
        )

      {:ok, execution} =
        dispatch_execution(
          subject,
          installation,
          "expense_capture",
          "finance.expense.capture"
        )

      dispatch =
        accept_next_dispatch!(
          execution,
          installation,
          subject.id,
          "expense_capture",
          "expense"
        )

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
           tenant_id: dispatch.tenant_id,
           recipe_ref: dispatch.recipe_ref,
           classification: dispatch.classification,
           job_status: dispatch.job_status,
           submission_ref_status: dispatch.submission_ref_status
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

  def run_case(:multi_pack_installation_routing) do
    MezzanineSubstrate.with_store(:multi_pack_installation_routing, fn _repo_config ->
      tenant_id = "tenant-multi-pack"
      environment = "stage3"
      shared_source_ref = "shared:external:event-42"

      expense_pack =
        compile_pack!(
          pack_slug: :expense_approval,
          version: "1.0.0",
          subject_kind: :expense_request,
          recipe_ref: :expense_capture,
          projection_name: :active_expenses,
          terminal_state: :paid
        )

      invoice_pack =
        compile_pack!(
          pack_slug: :invoice_ops,
          version: "1.0.0",
          subject_kind: :invoice_request,
          recipe_ref: :invoice_capture,
          projection_name: :active_invoices,
          terminal_state: :settled
        )

      expense_installation =
        expense_pack
        |> activate_registration!()
        |> install_pack!(
          tenant_id: tenant_id,
          environment: environment,
          binding_config: binding_config_for("expense_capture", "expense_system")
        )

      invoice_installation =
        invoice_pack
        |> activate_registration!()
        |> install_pack!(
          tenant_id: tenant_id,
          environment: environment,
          binding_config: binding_config_for("invoice_capture", "invoice_system")
        )

      {:ok, expense_compiled} =
        Registry.get_compiled_pack(
          expense_installation.id,
          expense_installation.compiled_pack_revision
        )

      {:ok, invoice_compiled} =
        Registry.get_compiled_pack(
          invoice_installation.id,
          invoice_installation.compiled_pack_revision
        )

      {:ok, expense_subject} =
        ingest_subject(
          expense_installation.id,
          shared_source_ref,
          "expense_request",
          %{"amount_cents" => 12_500, "merchant" => "Atlas Travel"},
          "trace-subject-expense-shared",
          "cause-subject-expense-shared"
        )

      {:ok, invoice_subject} =
        ingest_subject(
          invoice_installation.id,
          shared_source_ref,
          "invoice_request",
          %{"invoice_number" => "INV-42", "amount_cents" => 42_000},
          "trace-subject-invoice-shared",
          "cause-subject-invoice-shared"
        )

      {:ok, expense_execution} =
        dispatch_execution(
          expense_subject,
          expense_installation,
          "expense_capture",
          "finance.expense.capture"
        )

      expense_dispatch =
        accept_next_dispatch!(
          expense_execution,
          expense_installation,
          expense_subject.id,
          "expense_capture",
          "expense"
        )

      {:ok, invoice_execution} =
        dispatch_execution(
          invoice_subject,
          invoice_installation,
          "invoice_capture",
          "finance.invoice.capture"
        )

      invoice_dispatch =
        accept_next_dispatch!(
          invoice_execution,
          invoice_installation,
          invoice_subject.id,
          "invoice_capture",
          "invoice"
        )

      {:ok,
       %{
         case: :multi_pack_installation_routing,
         routing: %{
           tenant_id: tenant_id,
           environment: environment,
           shared_source_ref: shared_source_ref
         },
         installations: %{
           expense:
             installation_summary(expense_installation, expense_compiled, "expense_request"),
           invoice:
             installation_summary(invoice_installation, invoice_compiled, "invoice_request")
         },
         subjects: %{
           expense: subject_summary(expense_subject),
           invoice: subject_summary(invoice_subject)
         },
         dispatches: %{
           expense: expense_dispatch,
           invoice: invoice_dispatch
         }
       }}
    end)
  end

  defp compile_pack!(opts) when is_list(opts) do
    pack_slug = Keyword.fetch!(opts, :pack_slug)
    version = Keyword.fetch!(opts, :version)
    subject_kind = Keyword.fetch!(opts, :subject_kind)
    recipe_ref = Keyword.fetch!(opts, :recipe_ref)
    projection_name = Keyword.fetch!(opts, :projection_name)
    terminal_state = Keyword.fetch!(opts, :terminal_state)

    manifest = %Manifest{
      pack_slug: pack_slug,
      version: version,
      subject_kind_specs: [
        %SubjectKindSpec{name: subject_kind}
      ],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: subject_kind,
          initial_state: :submitted,
          terminal_states: [terminal_state],
          transitions: [
            %{
              from: :submitted,
              to: :processing,
              trigger: {:execution_requested, recipe_ref}
            },
            %{from: :processing, to: terminal_state, trigger: {:execution_completed, recipe_ref}}
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: recipe_ref,
          runtime_class: :session,
          placement_ref: :local_runner
        }
      ],
      projection_specs: [
        %ProjectionSpec{name: projection_name, subject_kinds: [subject_kind]}
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

  defp ingest_subject(
         installation_id,
         source_ref,
         subject_kind,
         payload,
         trace_id,
         causation_id
       ) do
    SubjectRecord.ingest(%{
      installation_id: installation_id,
      source_ref: source_ref,
      subject_kind: subject_kind,
      lifecycle_state: "submitted",
      schema_ref: subject_schema_ref(subject_kind),
      schema_version: 1,
      payload: payload,
      trace_id: trace_id,
      causation_id: causation_id,
      actor_ref: %{kind: :intake}
    })
  end

  defp subject_schema_ref(subject_kind),
    do: "mezzanine.subject.#{subject_kind}.payload.v1"

  defp dispatch_execution(subject, installation, recipe_ref, capability) do
    ExecutionRecord.dispatch(%{
      tenant_id: installation.tenant_id,
      installation_id: installation.id,
      subject_id: subject.id,
      recipe_ref: recipe_ref,
      compiled_pack_revision: installation.compiled_pack_revision,
      binding_snapshot: binding_snapshot_for(installation, recipe_ref),
      dispatch_envelope: %{"capability" => capability},
      submission_dedupe_key: "#{installation.id}:#{recipe_ref}",
      trace_id: "trace-#{recipe_ref}-#{subject.id}",
      causation_id: "cause-#{recipe_ref}-#{subject.id}",
      actor_ref: %{kind: :scheduler}
    })
  end

  defp accept_next_dispatch!(execution, installation, subject_id, recipe_ref, label) do
    LowerGatewayStub.with_handlers(
      %{
        dispatch: fn [claim] ->
          validate_claim!(claim, installation, subject_id, recipe_ref)
          {:accepted, acceptance_payload(claim)}
        end
      },
      fn ->
        dispatch = DispatchProbe.perform_dispatch!(execution.id)

        if dispatch.classification != :accepted do
          raise "expected governed-run dispatch to be accepted, got: #{inspect(dispatch)}"
        end

        %{
          label: label,
          tenant_id: dispatch.execution.tenant_id,
          installation_id: installation.id,
          recipe_ref: dispatch.execution.recipe_ref,
          classification: dispatch.classification,
          compiled_pack_revision: installation.compiled_pack_revision,
          job_status: dispatch.job_status,
          submission_ref_status: dispatch.execution.submission_ref["status"]
        }
      end
    )
  end

  defp validate_claim!(claimed, installation, subject_id, recipe_ref) do
    if claimed.installation_id != installation.id do
      raise "genericity proof claimed the wrong installation"
    end

    if claimed.tenant_id != installation.tenant_id do
      raise "genericity proof lowered with the wrong tenant"
    end

    if claimed.subject_id != subject_id do
      raise "genericity proof claimed the wrong subject"
    end

    if claimed.submission_dedupe_key != "#{installation.id}:#{recipe_ref}" do
      raise "genericity proof lowered with the wrong submission key"
    end

    if claimed.compiled_pack_revision != installation.compiled_pack_revision do
      raise "genericity proof lowered with the wrong compiled-pack revision"
    end

    if claimed.binding_snapshot != binding_snapshot_for(installation, recipe_ref) do
      raise "genericity proof lowered with the wrong binding snapshot"
    end
  end

  defp binding_snapshot_for(installation, recipe_ref) do
    installation
    |> Map.fetch!(:binding_config)
    |> get_in(["execution_bindings", recipe_ref])
    |> Map.take(["placement_ref", "execution_params", "connector_bindings"])
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

  defp installation_summary(installation, compiled_pack, subject_kind) do
    %{
      installation_id: installation.id,
      pack_slug: compiled_pack.pack_slug,
      compiled_pack_revision: installation.compiled_pack_revision,
      subject_kind: subject_kind
    }
  end

  defp subject_summary(subject) do
    %{
      installation_id: subject.installation_id,
      source_ref: subject.source_ref,
      subject_kind: subject.subject_kind
    }
  end
end
