defmodule StackLab.CitadelSpineHarness.InstallationRuntimeLease do
  @moduledoc false

  alias Mezzanine.ConfigRegistry.PackRegistration

  alias Mezzanine.Pack.{
    CompiledPack,
    Compiler,
    ExecutionRecipeSpec,
    LifecycleSpec,
    Manifest,
    ProjectionSpec,
    SubjectKindSpec
  }

  alias Mezzanine.RuntimeScheduler.{InstallationLease, InstallationLeaseStore}
  alias MezzanineConfigRegistry
  alias StackLab.CitadelSpineHarness.MezzanineSubstrate

  @spec run_case(:two_owner_fencing) :: {:ok, map()}
  def run_case(:two_owner_fencing) do
    MezzanineSubstrate.with_store(:installation_runtime_lease, fn _repo_config ->
      tenant_id = "tenant-installation-lease"
      environment = "stage3"
      now = ~U[2026-04-16 15:00:00.000000Z]
      later = ~U[2026-04-16 15:10:00.000000Z]

      expense_registration =
        compile_pack!(
          pack_slug: "expense_approval",
          version: "1.0.0",
          subject_kind: "expense_request",
          recipe_ref: "expense_capture",
          projection_name: "expense_queue",
          terminal_state: :approved
        )
        |> activate_registration!()

      invoice_registration =
        compile_pack!(
          pack_slug: "invoice_ops",
          version: "1.0.0",
          subject_kind: "invoice_request",
          recipe_ref: "invoice_capture",
          projection_name: "invoice_queue",
          terminal_state: :posted
        )
        |> activate_registration!()

      expense_installation = install_pack!(expense_registration, tenant_id, environment)
      invoice_installation = install_pack!(invoice_registration, tenant_id, environment)

      expense_lease =
        lease!(
          expense_installation.id,
          "scheduler-a",
          "lease:expense:a",
          1,
          expense_installation.compiled_pack_revision,
          now
        )

      invoice_lease =
        lease!(
          invoice_installation.id,
          "scheduler-b",
          "lease:invoice:b",
          1,
          invoice_installation.compiled_pack_revision,
          now
        )

      {:ok, :acquired, expense_claim} =
        InstallationLeaseStore.acquire_lease(expense_lease, now)

      {:ok, :acquired, invoice_claim} =
        InstallationLeaseStore.acquire_lease(invoice_lease, now)

      {:error, {:held_by_other, expense_fence}} =
        InstallationLeaseStore.acquire_lease(
          lease!(
            expense_installation.id,
            "scheduler-b",
            "lease:expense:b",
            2,
            expense_installation.compiled_pack_revision,
            now
          ),
          now
        )

      {:error, {:stale_epoch, stale_fence}} =
        InstallationLeaseStore.acquire_lease(
          lease!(
            expense_installation.id,
            "scheduler-b",
            "lease:expense:b",
            1,
            expense_installation.compiled_pack_revision,
            later
          ),
          later
        )

      takeover_lease =
        lease!(
          expense_installation.id,
          "scheduler-b",
          "lease:expense:b",
          2,
          expense_installation.compiled_pack_revision,
          later
        )

      {:ok, :acquired, expense_takeover} =
        InstallationLeaseStore.acquire_lease(takeover_lease, later)

      {:ok, persisted_expense} =
        InstallationLeaseStore.fetch_current_lease(expense_installation.id)

      {:ok, persisted_invoice} =
        InstallationLeaseStore.fetch_current_lease(invoice_installation.id)

      {:ok,
       %{
         case: :two_owner_fencing,
         tenant_id: tenant_id,
         environment: environment,
         installations: %{
           expense: installation_summary(expense_installation),
           invoice: installation_summary(invoice_installation)
         },
         first_claims: %{
           expense: lease_summary(expense_claim),
           invoice: lease_summary(invoice_claim)
         },
         competing_claim: %{
           status: :held_by_other,
           fence: fence_summary(expense_fence)
         },
         stale_takeover: %{
           status: :stale_epoch,
           fence: fence_summary(stale_fence)
         },
         takeover: %{
           status: :acquired,
           lease: lease_summary(expense_takeover)
         },
         persisted: %{
           expense: lease_summary(persisted_expense),
           invoice: lease_summary(persisted_invoice)
         }
       }}
    end)
  end

  defp compile_pack!(opts) when is_list(opts) do
    manifest = %Manifest{
      pack_slug: Keyword.fetch!(opts, :pack_slug),
      version: Keyword.fetch!(opts, :version),
      subject_kind_specs: [
        %SubjectKindSpec{name: Keyword.fetch!(opts, :subject_kind)}
      ],
      lifecycle_specs: [
        %LifecycleSpec{
          subject_kind: Keyword.fetch!(opts, :subject_kind),
          initial_state: :submitted,
          terminal_states: [Keyword.fetch!(opts, :terminal_state)],
          transitions: [
            %{
              from: :submitted,
              to: :processing,
              trigger: {:execution_requested, Keyword.fetch!(opts, :recipe_ref)}
            },
            %{
              from: :processing,
              to: Keyword.fetch!(opts, :terminal_state),
              trigger: {:execution_completed, Keyword.fetch!(opts, :recipe_ref)}
            }
          ]
        }
      ],
      execution_recipe_specs: [
        %ExecutionRecipeSpec{
          recipe_ref: Keyword.fetch!(opts, :recipe_ref),
          runtime_class: :session,
          placement_ref: :local_runner
        }
      ],
      projection_specs: [
        %ProjectionSpec{
          name: Keyword.fetch!(opts, :projection_name),
          subject_kinds: [Keyword.fetch!(opts, :subject_kind)]
        }
      ]
    }

    case Compiler.compile(manifest) do
      {:ok, %CompiledPack{} = compiled_pack} ->
        compiled_pack

      {:error, errors} ->
        raise "failed to compile installation lease proof pack: #{inspect(errors)}"
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
        raise "failed to activate installation lease proof pack: #{inspect(error)}"
    end
  end

  defp install_pack!(registration, tenant_id, environment) do
    {:ok, installation} =
      MezzanineConfigRegistry.create_installation(%{
        tenant_id: tenant_id,
        environment: environment,
        pack_registration_id: registration.id
      })

    {:ok, installation} = MezzanineConfigRegistry.activate_installation(installation)
    installation
  end

  defp lease!(installation_id, holder, lease_id, epoch, revision, now) do
    {:ok, lease} =
      InstallationLease.new(%{
        installation_id: installation_id,
        holder: holder,
        lease_id: lease_id,
        epoch: epoch,
        compiled_pack_revision: revision,
        expires_at: DateTime.add(now, 300, :second)
      })

    lease
  end

  defp installation_summary(installation) do
    %{
      installation_id: installation.id,
      pack_slug: installation.pack_slug,
      compiled_pack_revision: installation.compiled_pack_revision
    }
  end

  defp lease_summary(lease) do
    %{
      installation_id: lease.installation_id,
      holder: lease.holder,
      lease_id: lease.lease_id,
      epoch: lease.epoch,
      compiled_pack_revision: lease.compiled_pack_revision
    }
  end

  defp fence_summary(fence) do
    %{
      installation_id: fence.installation_id,
      holder: fence.holder,
      lease_id: fence.lease_id,
      epoch: fence.epoch,
      compiled_pack_revision: fence.compiled_pack_revision
    }
  end
end
