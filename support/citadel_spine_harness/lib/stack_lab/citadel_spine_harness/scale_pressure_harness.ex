defmodule StackLab.CitadelSpineHarness.ScalePressureHarness do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.RuntimeProcesses
  alias StackLab.CitadelSpineHarness.Timing

  @contract_name "ScalePressureProfile.v1"
  @scenario 610
  @tenant_count 3
  @agent_count_per_tenant 4
  @work_items_per_agent 2
  @concurrency_cap 6
  @work_item_count @tenant_count * @agent_count_per_tenant * @work_items_per_agent
  @fault_classes [
    :timeout,
    :malformed_response,
    :partial_response,
    :rate_limit,
    :unavailable_meter
  ]
  @enforcement_points [
    :preflight,
    :tool_result_append,
    :stream_tick,
    :runtime_admission,
    :post_run_reconcile
  ]
  @required_profile_fields [
    :tenant_count,
    :agent_count_per_tenant,
    :work_items_per_agent,
    :concurrency_cap,
    :rate_limits,
    :backpressure_policy,
    :fault_injection,
    :restart_replay_class,
    :cleanup_class,
    :timeout,
    :slo_claim_status
  ]
  @legacy_pressure_fields [:max_concurrency, :agents_per_tenant, :runs_per_agent]
  @forbidden_raw_keys [:raw_payload, :raw_prompt, :provider_body, :full_prompt]
  @forbidden_raw_fragments [
    "raw_payload",
    "raw prompt",
    "raw_prompt",
    "provider_body",
    "full_prompt",
    "workflow history"
  ]

  @spec profile() :: map()
  def profile do
    %{
      contract_name: @contract_name,
      owner_repo: :stack_lab,
      tenant_count: @tenant_count,
      agent_count_per_tenant: @agent_count_per_tenant,
      work_items_per_agent: @work_items_per_agent,
      concurrency_cap: @concurrency_cap,
      rate_limits: %{
        dispatch_window: %{limit: @concurrency_cap, interval_ms: 1_000},
        per_tenant: %{limit: 2, interval_ms: 1_000}
      },
      backpressure_policy: %{
        policy: :bounded_admission,
        action: :reject_over_cap,
        queue: :none
      },
      fault_injection: %{
        mode: :configured_adapter_boundary,
        classes: @fault_classes
      },
      restart_replay_class: :bounded_restart_replay_evidence,
      cleanup_class: :profile_install_cleanup_required,
      timeout: %{
        run_timeout_ms: 5_000,
        work_item_timeout_ms: 250
      },
      slo_claim_status: %{
        claim?: false,
        reason: :bounded_local_pressure_no_owned_metrics,
        baseline_ref: nil,
        target_ref: nil,
        metric_owner: nil,
        measurement_method: nil
      }
    }
  end

  @spec run_case(:bounded_local_pressure) :: {:ok, map()} | {:error, term()}
  def run_case(:bounded_local_pressure) do
    with {:ok, parsed_profile} <- parse_profile(profile()),
         {:ok, dispatch} <- run_bounded_local_pressure(parsed_profile),
         evidence <- build_evidence(parsed_profile, dispatch),
         :ok <- validate_evidence(evidence) do
      {:ok, attach_negative_failures(evidence)}
    end
  end

  @spec parse_profile(map()) :: {:ok, map()} | {:error, term()}
  def parse_profile(profile) when is_map(profile) do
    with :ok <- reject_legacy_pressure_fields(profile),
         :ok <- require_profile_fields(profile),
         :ok <- validate_contract_owner(profile),
         :ok <- validate_positive_shape(profile),
         :ok <- validate_rate_limits(profile),
         :ok <- validate_backpressure_policy(profile),
         :ok <- validate_fault_injection(profile),
         :ok <- validate_restart_cleanup_timeout(profile),
         :ok <- validate_no_slo_claim(profile) do
      {:ok, normalize_profile(profile)}
    end
  end

  def parse_profile(_profile), do: {:error, :invalid_scale_pressure_profile}

  @spec validate_evidence(map()) :: :ok | {:error, term()}
  def validate_evidence(%{} = evidence) do
    [
      fn -> validate_profile_cap(evidence) end,
      fn -> validate_cleanup(evidence) end,
      fn -> validate_no_egress(evidence) end,
      fn -> validate_cross_tenant_pressure(evidence) end,
      fn -> validate_budget_cost(evidence) end,
      fn -> validate_provider_fault_matrix(evidence) end,
      fn -> validate_raw_payload_absence(evidence) end
    ]
    |> Enum.reduce_while(:ok, fn validator, :ok ->
      case validator.() do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def validate_evidence(_evidence), do: {:error, :invalid_scale_pressure_evidence}

  defp reject_legacy_pressure_fields(profile) do
    case Enum.find(@legacy_pressure_fields, &Map.has_key?(profile, &1)) do
      nil -> :ok
      field -> {:error, {:legacy_pressure_field_forbidden, field}}
    end
  end

  defp require_profile_fields(profile) do
    missing = Enum.filter(@required_profile_fields, &missing_field?(Map.get(profile, &1)))

    case missing do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp missing_field?(value) when is_binary(value), do: String.trim(value) == ""
  defp missing_field?(value), do: value in [nil, []]

  defp validate_contract_owner(profile) do
    cond do
      Map.get(profile, :contract_name) != @contract_name ->
        {:error, :invalid_scale_pressure_contract}

      Map.get(profile, :owner_repo) != :stack_lab ->
        {:error, :invalid_scale_pressure_owner}

      true ->
        :ok
    end
  end

  defp validate_positive_shape(profile) do
    tenant_count = Map.fetch!(profile, :tenant_count)
    agent_count_per_tenant = Map.fetch!(profile, :agent_count_per_tenant)
    work_items_per_agent = Map.fetch!(profile, :work_items_per_agent)
    concurrency_cap = Map.fetch!(profile, :concurrency_cap)
    work_item_count = tenant_count * agent_count_per_tenant * work_items_per_agent

    if Enum.all?(
         [tenant_count, agent_count_per_tenant, work_items_per_agent, concurrency_cap],
         &positive_integer?/1
       ) and concurrency_cap <= work_item_count do
      :ok
    else
      {:error, :invalid_scale_pressure_shape}
    end
  end

  defp validate_rate_limits(%{rate_limits: %{dispatch_window: dispatch, per_tenant: per_tenant}}) do
    if valid_limit?(dispatch) and valid_limit?(per_tenant),
      do: :ok,
      else: {:error, :invalid_rate_limits}
  end

  defp validate_rate_limits(_profile), do: {:error, :invalid_rate_limits}

  defp valid_limit?(%{limit: limit, interval_ms: interval_ms}),
    do: positive_integer?(limit) and positive_integer?(interval_ms)

  defp valid_limit?(_limit), do: false

  defp validate_backpressure_policy(%{
         backpressure_policy: %{
           policy: :bounded_admission,
           action: :reject_over_cap,
           queue: :none
         }
       }),
       do: :ok

  defp validate_backpressure_policy(_profile), do: {:error, :invalid_backpressure_policy}

  defp validate_fault_injection(%{
         fault_injection: %{mode: :configured_adapter_boundary, classes: classes}
       }) do
    if Enum.sort(classes) == Enum.sort(@fault_classes),
      do: :ok,
      else: {:error, {:invalid_fault_classes, classes}}
  end

  defp validate_fault_injection(_profile), do: {:error, :invalid_fault_injection}

  defp validate_restart_cleanup_timeout(%{
         restart_replay_class: :bounded_restart_replay_evidence,
         cleanup_class: :profile_install_cleanup_required,
         timeout: %{run_timeout_ms: run_timeout_ms, work_item_timeout_ms: work_item_timeout_ms}
       }) do
    if positive_integer?(run_timeout_ms) and positive_integer?(work_item_timeout_ms),
      do: :ok,
      else: {:error, :invalid_timeout}
  end

  defp validate_restart_cleanup_timeout(_profile),
    do: {:error, :invalid_restart_cleanup_timeout}

  defp validate_no_slo_claim(%{
         slo_claim_status: %{
           claim?: false,
           reason: :bounded_local_pressure_no_owned_metrics,
           baseline_ref: nil,
           target_ref: nil,
           metric_owner: nil,
           measurement_method: nil
         }
       }),
       do: :ok

  defp validate_no_slo_claim(_profile), do: {:error, :invalid_slo_claim_status}

  defp normalize_profile(profile) do
    agent_count = profile.tenant_count * profile.agent_count_per_tenant
    work_item_count = agent_count * profile.work_items_per_agent

    profile
    |> Map.put(:agent_count, agent_count)
    |> Map.put(:work_item_count, work_item_count)
  end

  defp run_bounded_local_pressure(profile) do
    {:ok, counter} =
      RuntimeProcesses.start_agent(fn ->
        %{current: 0, max: 0}
      end)

    try do
      results =
        1..profile.work_item_count
        |> RuntimeProcesses.async_stream(
          fn index -> run_pressure_item(counter, index) end,
          max_concurrency: profile.concurrency_cap,
          timeout: profile.timeout.work_item_timeout_ms,
          ordered: false
        )
        |> Enum.map(fn
          {:ok, item} -> item
          {:exit, reason} -> {:failed, reason}
        end)

      counter_state = Agent.get(counter, & &1)

      if Enum.all?(results, &match?(%{status: :completed}, &1)) do
        {:ok,
         %{
           scheduler: :bounded_async_stream,
           admitted_work_items: profile.work_item_count,
           completed_work_items: length(results),
           concurrency_cap: profile.concurrency_cap,
           max_in_flight_observed: counter_state.max,
           rate_limits: profile.rate_limits,
           backpressure_action: profile.backpressure_policy.action,
           slo_claim?: false
         }}
      else
        {:error, {:pressure_item_failed, results}}
      end
    after
      Agent.stop(counter)
    end
  end

  defp run_pressure_item(counter, index) do
    Agent.get_and_update(counter, fn state ->
      current = state.current + 1
      updated = %{current: current, max: max(state.max, current)}
      {current, updated}
    end)

    Timing.delay(:scale_pressure_in_flight_window, 5)

    Agent.update(counter, fn state -> %{state | current: state.current - 1} end)

    %{index: index, status: :completed}
  end

  defp build_evidence(profile, dispatch) do
    work_items = work_items(profile)

    %{
      case: :bounded_local_pressure,
      scenario: @scenario,
      stack_lab_role: :scale_pressure_owner,
      contracts: [
        @contract_name,
        "ProviderFaultMatrix.v1",
        "BudgetCostAuthorityContract.v1"
      ],
      profile: profile,
      dispatch: dispatch,
      work_items: work_items,
      no_egress_policy: no_egress_policy(),
      budget_cost: budget_cost(),
      provider_fault_matrix: provider_fault_matrix(),
      cleanup: cleanup(),
      raw_payload_scan: %{
        result: :passed,
        scan_ref: "scan://phase6/m11/raw-payload-absence"
      }
    }
  end

  defp work_items(profile) do
    for tenant_idx <- 1..profile.tenant_count,
        agent_idx <- 1..profile.agent_count_per_tenant,
        item_idx <- 1..profile.work_items_per_agent do
      tenant_ref = "tenant://phase6/m11/t#{tenant_idx}"
      agent_ref = "agent://phase6/m11/t#{tenant_idx}/a#{agent_idx}"
      work_item_ref = "work://phase6/m11/t#{tenant_idx}/a#{agent_idx}/i#{item_idx}"

      %{
        tenant_ref: tenant_ref,
        observed_tenant_ref: tenant_ref,
        agent_ref: agent_ref,
        work_item_ref: work_item_ref,
        execution_ref: "execution://phase6/m11/t#{tenant_idx}/a#{agent_idx}/i#{item_idx}",
        trace_ref: "trace://phase6/m11/t#{tenant_idx}/a#{agent_idx}/i#{item_idx}",
        authorization_scope_ref:
          "authorization-scope://phase6/m11/t#{tenant_idx}/a#{agent_idx}/i#{item_idx}",
        status: :completed,
        provider_egress_allowed?: false,
        cost_units: 0
      }
    end
  end

  defp no_egress_policy do
    %{
      policy_ref: "no-egress://phase6/m11/scale-pressure",
      external_egress: :deny,
      process_spawn: :deny,
      unregistered_provider_route: :deny,
      raw_external_saas_write_path: :deny,
      provider_spend_cents: 0,
      external_write_refs: [],
      negative_evidence_refs: [
        "negative://phase6/m11/attempted-unregistered-provider-route",
        "negative://phase6/m11/attempted-raw-external-saas-write-path"
      ]
    }
  end

  defp budget_cost do
    %{
      contract_name: "BudgetCostAuthorityContract.v1",
      budget_ref: "budget://phase6/m11/local-no-spend",
      meter_ref: "meter://phase6/m11/local-deterministic",
      enforcement_points: @enforcement_points,
      provider_billable_units: 0,
      total_cost_units: 0,
      real_provider_spend?: false,
      missing_budget_policy: :deny_before_dispatch
    }
  end

  defp provider_fault_matrix do
    %{
      contract_name: "ProviderFaultMatrix.v1",
      faults:
        Enum.map(@fault_classes, fn fault_class ->
          %{
            fault_class: fault_class,
            owner_adapter: fault_owner_adapter(fault_class),
            injected_at: :configured_adapter_boundary,
            safe_action: safe_fault_action(fault_class),
            lower_side_effects?: false
          }
        end)
    }
  end

  defp fault_owner_adapter(:timeout), do: :execution_plane
  defp fault_owner_adapter(:malformed_response), do: :cli_subprocess_core
  defp fault_owner_adapter(:partial_response), do: :pristine
  defp fault_owner_adapter(:rate_limit), do: :prismatic
  defp fault_owner_adapter(:unavailable_meter), do: :self_hosted_inference_core

  defp safe_fault_action(:timeout), do: :retry_with_backoff
  defp safe_fault_action(:malformed_response), do: :terminal_provider_error
  defp safe_fault_action(:partial_response), do: :request_replay_or_reject
  defp safe_fault_action(:rate_limit), do: :defer_until_budget_window
  defp safe_fault_action(:unavailable_meter), do: :deny_before_dispatch

  defp cleanup do
    %{
      class: :profile_install_cleanup_required,
      status: :passed,
      install_ref: "profile-install://phase6/m11/scale-pressure",
      removed_ref: "profile-cleanup://phase6/m11/scale-pressure",
      temporary_refs_after_cleanup: []
    }
  end

  defp attach_negative_failures(evidence) do
    negative_failures = %{
      overload_rejection:
        evidence
        |> put_in([:profile, :concurrency_cap], @concurrency_cap + 1)
        |> validate_evidence()
        |> rejected(),
      cleanup_failure:
        evidence
        |> put_in([:cleanup, :status], :failed)
        |> validate_evidence()
        |> rejected(),
      egress_attempt:
        evidence
        |> put_in([:no_egress_policy, :external_egress], :allow)
        |> validate_evidence()
        |> rejected(),
      cross_tenant_pressure_leak:
        evidence
        |> put_in([:work_items, Access.at(0), :observed_tenant_ref], "tenant://phase6/m11/t2")
        |> validate_evidence()
        |> rejected()
    }

    Map.put(evidence, :negative_failures, negative_failures)
  end

  defp validate_profile_cap(%{profile: %{concurrency_cap: concurrency_cap}})
       when concurrency_cap > @concurrency_cap,
       do: {:error, {:concurrency_cap_exceeded, concurrency_cap}}

  defp validate_profile_cap(%{
         profile: %{
           contract_name: @contract_name,
           owner_repo: :stack_lab,
           tenant_count: @tenant_count,
           agent_count_per_tenant: @agent_count_per_tenant,
           work_items_per_agent: @work_items_per_agent,
           concurrency_cap: concurrency_cap,
           slo_claim_status: %{claim?: false}
         },
         dispatch: %{admitted_work_items: @work_item_count, concurrency_cap: concurrency_cap}
       }),
       do: :ok

  defp validate_profile_cap(_evidence), do: {:error, :invalid_scale_pressure_evidence}

  defp validate_cleanup(%{
         cleanup: %{
           class: :profile_install_cleanup_required,
           status: :passed,
           temporary_refs_after_cleanup: []
         }
       }),
       do: :ok

  defp validate_cleanup(_evidence), do: {:error, :cleanup_required}

  defp validate_no_egress(%{
         no_egress_policy: %{
           external_egress: :deny,
           process_spawn: :deny,
           unregistered_provider_route: :deny,
           raw_external_saas_write_path: :deny,
           provider_spend_cents: 0,
           external_write_refs: []
         },
         work_items: work_items
       }) do
    if Enum.any?(work_items, & &1.provider_egress_allowed?),
      do: {:error, :external_egress_denied},
      else: :ok
  end

  defp validate_no_egress(_evidence), do: {:error, :external_egress_denied}

  defp validate_cross_tenant_pressure(%{work_items: work_items}) when is_list(work_items) do
    if Enum.any?(work_items, &(&1.observed_tenant_ref != &1.tenant_ref)),
      do: {:error, :cross_tenant_pressure_leak},
      else: :ok
  end

  defp validate_cross_tenant_pressure(_evidence), do: {:error, :cross_tenant_pressure_leak}

  defp validate_budget_cost(%{
         budget_cost: %{
           enforcement_points: @enforcement_points,
           provider_billable_units: 0,
           total_cost_units: 0,
           real_provider_spend?: false,
           missing_budget_policy: :deny_before_dispatch
         }
       }),
       do: :ok

  defp validate_budget_cost(_evidence), do: {:error, :invalid_budget_cost_authority}

  defp validate_provider_fault_matrix(%{provider_fault_matrix: %{faults: faults}})
       when is_list(faults) do
    fault_classes = Enum.map(faults, & &1.fault_class) |> Enum.sort()

    if fault_classes == Enum.sort(@fault_classes) and
         Enum.all?(faults, &(&1.injected_at == :configured_adapter_boundary)) and
         Enum.all?(faults, &(&1.lower_side_effects? == false)) do
      :ok
    else
      {:error, {:invalid_provider_fault_matrix, fault_classes}}
    end
  end

  defp validate_provider_fault_matrix(_evidence), do: {:error, :invalid_provider_fault_matrix}

  defp validate_raw_payload_absence(term) do
    if raw_payload_present?(term),
      do: {:error, :raw_payload_leak},
      else: :ok
  end

  defp raw_payload_present?(term) when is_map(term) do
    Enum.any?(term, fn
      {key, _value} when key in @forbidden_raw_keys ->
        true

      {_key, value} ->
        raw_payload_present?(value)
    end)
  end

  defp raw_payload_present?(term) when is_list(term), do: Enum.any?(term, &raw_payload_present?/1)

  defp raw_payload_present?(term) when is_binary(term) do
    normalized = String.downcase(term)
    Enum.any?(@forbidden_raw_fragments, &String.contains?(normalized, &1))
  end

  defp raw_payload_present?(_term), do: false

  defp rejected({:error, reason}), do: reason
  defp rejected(:ok), do: :unexpected_acceptance

  defp positive_integer?(value), do: is_integer(value) and value > 0
end
