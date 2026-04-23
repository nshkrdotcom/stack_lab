defmodule StackLab.CitadelSpineHarness.AuthorityTenantPropagationEvidence do
  @moduledoc false

  alias Citadel.AuthorityContract.AuthorityTenantPropagation.V1, as: CitadelAuthorityTenant
  alias Jido.Integration.V2.AuthorityTenantPropagation, as: JidoAuthorityTenant
  alias Mezzanine.Leasing.AuthorityTenantPropagation, as: MezzanineAuthorityTenant
  alias StackLab.CitadelSpineHarness.LowerFacts

  @spec run_case(:owner_composed_evidence) :: {:ok, map()} | {:error, term()}
  def run_case(:owner_composed_evidence) do
    contract = CitadelAuthorityTenant.contract()

    with {:ok, citadel} <- CitadelAuthorityTenant.owner_evidence(CitadelAuthorityTenant.fixture()),
         {:ok, mezzanine} <-
           MezzanineAuthorityTenant.authorization_scope_evidence(
             MezzanineAuthorityTenant.fixture()
           ),
         {:ok, jido} <- jido_owner_evidence(),
         :ok <- owner_evidence_consistent(citadel, mezzanine, jido),
         {:ok, real_lower_facts} <- LowerFacts.run_case(:authorized_mezzanine_readback),
         :ok <- require_real_lower_facts_read(real_lower_facts),
         {:ok, unauthorized_lower_facts} <- LowerFacts.run_case(:unauthorized_mezzanine_readback),
         negative_failures = negative_failures(unauthorized_lower_facts),
         :ok <- require_negative_failures(negative_failures) do
      {:ok,
       %{
         case: :owner_composed_evidence,
         contract: contract,
         stack_lab_role: :evidence_composer_not_owner,
         service_mode_gate: %{
           citadel_owner_consumed?: true,
           mezzanine_owner_consumed?: true,
           jido_integration_owner_consumed?: true,
           real_lower_facts_read_consumed?: true,
           no_bypass_scope_present?: true,
           authorization_scope_ref_consistent?: true,
           lower_facts_propagation_ref_consistent?: true,
           harness_self_assertion_rejected?: true,
           cross_tenant_lower_read_rejected?: true,
           direct_lower_shortcut_rejected?: true
         },
         citadel: citadel,
         mezzanine: mezzanine,
         jido: jido,
         real_lower_facts: real_lower_facts,
         negative_failures: negative_failures
       }}
    end
  end

  defp jido_owner_evidence do
    # Keeps the cross-package fixture call from being over-specialized by Dialyzer.
    owner_evidence = Function.capture(JidoAuthorityTenant, :lower_owner_evidence, 1)

    owner_evidence.(JidoAuthorityTenant.fixture())
  end

  defp owner_evidence_consistent(citadel, mezzanine, jido) do
    [
      {:contract_id, [citadel.contract_id, mezzanine.contract_id, jido.contract_id]},
      {:tenant_ref,
       [
         normalize_tenant_ref(citadel.tenant_ref),
         normalize_tenant_ref(mezzanine.tenant_ref),
         normalize_tenant_ref(jido.tenant_ref)
       ]},
      {:authority_decision_ref,
       [
         citadel.authority_decision_ref,
         mezzanine.authority_decision_ref,
         jido.authority_decision_ref
       ]},
      {:authorization_scope_ref,
       [
         citadel.authorization_scope_ref,
         mezzanine.authorization_scope_ref,
         jido.authorization_scope_ref
       ]},
      {:budget_ref, [citadel.budget_ref, mezzanine.budget_ref, jido.budget_ref]},
      {:no_bypass_scope_ref, [mezzanine.no_bypass_scope_ref, jido.no_bypass_scope_ref]},
      {:lineage_ref, [citadel.lineage_ref, mezzanine.lineage_ref, jido.lineage_ref]},
      {:causation_ref, [citadel.causation_ref, mezzanine.causation_ref, jido.causation_ref]},
      {:idempotency_ref,
       [citadel.idempotency_ref, mezzanine.idempotency_ref, jido.idempotency_ref]},
      {:lower_facts_propagation_ref,
       [
         citadel.lower_facts_propagation_ref,
         mezzanine.lower_facts_propagation_ref,
         jido.lower_facts_propagation_ref
       ]}
    ]
    |> Enum.reduce_while(:ok, fn {field, refs}, :ok ->
      case same_ref(field, refs) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp same_ref(field, refs) do
    case Enum.uniq(refs) do
      [_ref] -> :ok
      _refs -> {:error, {:owner_evidence_mismatch, field, refs}}
    end
  end

  defp normalize_tenant_ref("tenant:" <> tenant_id), do: tenant_id
  defp normalize_tenant_ref(tenant_id), do: tenant_id

  defp require_real_lower_facts_read(real_lower_facts) do
    required = %{
      case: :authorized_mezzanine_readback,
      operation: :fetch_run,
      source: :lower_run_status
    }

    if Map.take(real_lower_facts, Map.keys(required)) == required do
      :ok
    else
      {:error, {:missing_real_lower_facts_read, real_lower_facts}}
    end
  end

  defp require_negative_failures(negative_failures) do
    required = %{
      harness_self_assertion:
        {:forbidden_evidence, :harness_self_assertion_as_authority_evidence},
      cross_tenant_lower_read: :unauthorized_lower_read,
      direct_lower_shortcut: {:forbidden_evidence, :direct_lower_shortcut_bypassing_authority}
    }

    if Map.take(negative_failures, Map.keys(required)) == required do
      :ok
    else
      {:error, {:missing_negative_failure_evidence, negative_failures}}
    end
  end

  defp negative_failures(%{error: unauthorized_error}) do
    citadel_fixture = CitadelAuthorityTenant.fixture()
    mezzanine_fixture = MezzanineAuthorityTenant.fixture()
    jido_fixture = JidoAuthorityTenant.fixture()

    {:error, missing_authority} =
      citadel_fixture
      |> Map.put(:authority_decision, nil)
      |> CitadelAuthorityTenant.owner_evidence()

    {:error, missing_budget} =
      mezzanine_fixture
      |> Map.delete(:budget_ref)
      |> MezzanineAuthorityTenant.authorization_scope_evidence()

    {:error, missing_no_bypass_scope} =
      mezzanine_fixture
      |> Map.delete(:no_bypass_scope_ref)
      |> MezzanineAuthorityTenant.authorization_scope_evidence()

    {:error, cross_tenant_scope} =
      mezzanine_fixture
      |> put_in([:authorization_scope_attrs, :tenant_id], "tenant-other")
      |> MezzanineAuthorityTenant.authorization_scope_evidence()

    {:error, lower_facts_mismatch} =
      jido_fixture
      |> put_in([:lower_facts, :tenant_id], "tenant-other")
      |> JidoAuthorityTenant.lower_owner_evidence()

    {:error, direct_lower_shortcut} =
      jido_fixture
      |> put_in([:lower_facts, :shortcut?], true)
      |> JidoAuthorityTenant.lower_owner_evidence()

    {:error, harness_self_assertion} =
      citadel_fixture
      |> Map.put(:evidence_source, :harness_self_assertion)
      |> CitadelAuthorityTenant.owner_evidence()

    %{
      missing_authority: missing_authority,
      missing_budget: missing_budget,
      missing_no_bypass_scope: missing_no_bypass_scope,
      cross_tenant_scope: cross_tenant_scope,
      lower_facts_mismatch: lower_facts_mismatch,
      direct_lower_shortcut: direct_lower_shortcut,
      harness_self_assertion: harness_self_assertion,
      cross_tenant_lower_read: unauthorized_error
    }
  end
end
