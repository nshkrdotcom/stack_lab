defmodule StackLab.CostRoundtrip do
  @moduledoc """
  End-to-end cost and budget proof for Phase D.
  """

  alias AITrace.AIPlatform
  alias AppKit.{BudgetSurface, CostSurface}
  alias Mezzanine.{BudgetEnforcementEngine, CostAttributionEngine}
  alias OuterBrain.TokenMeter

  @fixture_refs [
    "COST-001",
    "COST-002",
    "COST-003",
    "COST-004",
    "COST-005",
    "COST-006",
    "COST-007",
    "COST-008",
    "COST-009",
    "COST-010",
    "COST-011",
    "COST-012",
    "COST-013",
    "MEM-006",
    "EVAL-007",
    "PROMPT-010",
    "GUARD-008"
  ]

  @spec run(map()) :: {:ok, map()} | {:error, term()}
  def run(attrs \\ %{}) when is_map(attrs) do
    with {:ok, meter_ref} <- token_meter_ref(attrs),
         {:ok, metered_call} <- metered_call(meter_ref),
         {:ok, rollup} <- TokenMeter.rollup([metered_call]),
         {:ok, cost_ledger} <- CostAttributionEngine.new_ledger(),
         {:ok, cost_ledger, production_fact} <-
           CostAttributionEngine.record(cost_ledger, cost_attrs(meter_ref, :production, attrs)),
         {:ok, cost_ledger, replay_fact} <-
           CostAttributionEngine.record(cost_ledger, cost_attrs(meter_ref, :replay, attrs)),
         {:ok, cost_ledger, eval_fact} <-
           CostAttributionEngine.record(cost_ledger, cost_attrs(meter_ref, :eval, attrs)),
         {:ok, cost_projection} <- cost_projection(cost_ledger),
         {:error, :cross_tenant_cost_aggregation_forbidden} <-
           CostAttributionEngine.project(cost_ledger, %{
             tenant_ref: "tenant://phase-d",
             caller_tenant_ref: "tenant://other"
           }),
         {:ok, budget} <- budget_ref(attrs),
         {:ok, budget_ledger} <- BudgetEnforcementEngine.new_ledger(),
         {:ok, budget_ledger, allow_decision} <-
           BudgetEnforcementEngine.enforce(budget_ledger, budget, %{
             locus: :preflight,
             requested_units: 4
           }),
         {:ok, _budget_ledger, override_decision} <-
           BudgetEnforcementEngine.enforce(budget_ledger, budget, %{
             locus: :runtime_admission,
             requested_units: 4,
             override_permission_ref: "permission://budget/override",
             reason_ref: "reason://phase-d/operator",
             duration_seconds: 60
           }),
         {:ok, budget_view} <- budget_view(budget, override_decision),
         {:ok, exhaustion} <- budget_exhaustion(budget, override_decision),
         {:ok, trace_event} <- AIPlatform.cost_attribution_event(cost_event_attrs(rollup)),
         {:ok, budget_event} <-
           AIPlatform.budget_exhaust_event(:runtime_admission, budget_event_attrs()) do
      {:ok,
       %{
         receipt_ref: "cost-roundtrip://phase-d",
         fixture_refs: @fixture_refs,
         rollup_ref: rollup.rollup_ref,
         production_cost_class: production_fact.cost_class,
         replay_cost_class: replay_fact.cost_class,
         eval_cost_class: eval_fact.cost_class,
         cost_projection: cost_projection,
         budget_decisions: [allow_decision.decision_class, override_decision.decision_class],
         budget_view: budget_view,
         budget_exhaustion: exhaustion,
         trace_event_name: trace_event.name,
         budget_event_name: budget_event.name
       }}
    end
  end

  defp token_meter_ref(attrs) do
    TokenMeter.token_meter_ref(%{
      meter_id: Map.get(attrs, :meter_id, "meter://phase-d/codex"),
      provider_family: :codex_cli,
      model_ref: "model://codex/latest",
      tenant_ref: "tenant://phase-d",
      installation_ref: "installation://phase-d",
      revision: 1
    })
  end

  defp metered_call(meter_ref) do
    TokenMeter.count_call(meter_ref, %{
      call_ref: "call://phase-d/provider-effect",
      operation_class: :completion,
      excerpt_ref: "excerpt://phase-d/provider-effect",
      count_class: :bounded_fixture,
      rollup_key: "workflow://phase-d",
      prompt_tokens: 10,
      completion_tokens: 5,
      cache_read_tokens: 2,
      cache_write_tokens: 1
    })
  end

  defp cost_attrs(meter_ref, cost_class, attrs) do
    suffix = Atom.to_string(cost_class)

    %{
      tenant_ref: "tenant://phase-d",
      authority_ref: "authority://phase-d",
      installation_ref: "installation://phase-d",
      run_ref: "run://phase-d/#{suffix}",
      connector_instance_ref: "connector://codex",
      provider_account_ref: "provider-account://redacted",
      capability_id: "codex.session.turn",
      operation_class: operation_class(cost_class),
      model_ref: "model://codex/latest",
      persistence_profile_ref: "persistence://memory/default",
      cost_class: cost_class,
      token_meter_ref: meter_ref,
      amount_class: :redacted_below_floor,
      idempotency_key: "idem-phase-d-#{suffix}",
      trace_id: "trace-phase-d-#{suffix}",
      release_manifest_ref: Map.get(attrs, :release_manifest_ref, "release://phase-d")
    }
  end

  defp operation_class(:replay), do: :replay_execute
  defp operation_class(:eval), do: :eval_run
  defp operation_class(_cost_class), do: :provider_effect

  defp cost_projection(cost_ledger) do
    with {:ok, projection} <-
           CostAttributionEngine.project(cost_ledger, %{
             tenant_ref: "tenant://phase-d",
             caller_tenant_ref: "tenant://phase-d",
             group_by: :cost_class
           }) do
      CostSurface.breakdown_projection(%{
        projection_ref: projection.projection_ref,
        tenant_ref: projection.tenant_ref,
        group_by: projection.group_by,
        facts: [
          %{
            fact_ref: "cost-fact://phase-d",
            run_ref: "run://phase-d/production",
            capability_id: "codex.session.turn",
            cost_class: :production,
            amount_class: :redacted_below_floor,
            token_meter_ref: "meter://phase-d/codex",
            trace_id: "trace-phase-d-production"
          }
        ]
      })
    end
  end

  defp budget_ref(attrs) do
    BudgetEnforcementEngine.budget_ref(%{
      budget_id: Map.get(attrs, :budget_id, "budget://phase-d/default"),
      tenant_ref: "tenant://phase-d",
      installation_ref: "installation://phase-d",
      run_ref: "run://phase-d/production",
      period_class: :per_run,
      hard_cap_amount: 5,
      soft_cap_amount: 3,
      override_policy_ref: "policy://budget/override/default"
    })
  end

  defp budget_view(budget, decision) do
    BudgetSurface.view_projection(%{
      budget_ref: budget.budget_id,
      period_class: budget.period_class,
      hard_cap_class: :redacted_above_ceiling,
      soft_cap_class: :redacted_below_floor,
      decision_class: decision.decision_class
    })
  end

  defp budget_exhaustion(budget, decision) do
    BudgetSurface.exhaustion_record(%{
      budget_ref: budget.budget_id,
      locus: decision.locus,
      decision_class: decision.decision_class,
      requested_units: decision.requested_units,
      granted_units: decision.granted_units
    })
  end

  defp cost_event_attrs(rollup) do
    %{
      cost_class: :production,
      amount_class: :redacted_below_floor,
      prompt_tokens: rollup.token_counts.prompt_tokens,
      completion_tokens: rollup.token_counts.completion_tokens,
      cache_read_tokens: rollup.token_counts.cache_read_tokens,
      cache_write_tokens: rollup.token_counts.cache_write_tokens,
      provider_family: :codex_cli,
      model_ref: "model://codex/latest"
    }
  end

  defp budget_event_attrs do
    %{
      decision_class: :allow_with_override,
      requested_units: 4,
      granted_units: 4
    }
  end
end
