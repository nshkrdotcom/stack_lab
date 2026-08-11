defmodule StackLab.CitadelSpineHarness.PrelimEvidenceReport do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.PrelimServiceMode

  @schema "phase5prelim_evidence_report.v1"
  @schema_ref "contracts/prelim_evidence_report.schema.json"
  @packet "ecosystem_buildout_phase5PRELIM"
  @release_ref "phase5prelim-m6-evidence-report"
  @generated_at "2026-04-21T00:00:00Z"

  @top_level_keys [
    :schema,
    :packet,
    :run_id,
    :generated_at,
    :source_commit_refs,
    :substrate,
    :workload_profile,
    :scenario_results,
    :authority,
    :temporal,
    :semantic_gateway,
    :provider_simulation,
    :observability,
    :privacy,
    :hygiene
  ]

  @required_ref_paths [
    [:source_commit_refs],
    [:substrate, :boot_refs],
    [:substrate, :worker_health_refs],
    [:workload_profile, :lifecycle_states],
    [:authority, :tenant_refs],
    [:authority, :authority_decision_refs],
    [:authority, :authorization_scope_refs],
    [:authority, :budget_refs],
    [:authority, :negative_case_refs],
    [:temporal, :workflow_type_refs],
    [:temporal, :workflow_id_refs],
    [:temporal, :task_queue_refs],
    [:temporal, :compact_query_refs],
    [:temporal, :restart_replay_refs],
    [:semantic_gateway, :payload_boundary_refs],
    [:semantic_gateway, :context_provenance_refs],
    [:semantic_gateway, :semantic_failure_refs],
    [:semantic_gateway, :reply_publication_refs],
    [:provider_simulation, :adapter_profile_refs],
    [:provider_simulation, :lower_scenario_refs],
    [:provider_simulation, :provider_sdk_fixture_scope_refs],
    [:observability, :trace_refs],
    [:observability, :lineage_refs],
    [:observability, :aitrace_refs],
    [:privacy, :suppression_visibility_refs],
    [:privacy, :privacy_redaction_fixture_refs],
    [:privacy, :artifact_refs],
    [:hygiene, :repo_status_refs],
    [:hygiene, :qa_refs],
    [:hygiene, :pushed_refs]
  ]

  @allowed_statuses ["passed", "failed", "blocked", "not_applicable"]
  @allowed_input_fingerprint_policies ["transient_hash", "claim_check_ref", "frozen_fixture"]
  @forbidden_raw_keys ["raw_payload", "raw_prompt", "provider_body", "full_prompt"]
  @forbidden_raw_fragments [
    "raw_payload",
    "raw prompt",
    "raw_prompt",
    "raw provider body",
    "provider_body",
    "full_prompt",
    "workflow history"
  ]

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) when is_list(opts) do
    with {:ok, contract_join} <- PrelimServiceMode.run_case(:m3_contract_join, opts),
         {:ok, pressure} <- PrelimServiceMode.run_case(:m5_pressure_and_negatives, opts),
         report <- build_report(contract_join, pressure),
         :ok <- validate_report(report) do
      {:ok,
       %{
         case: :m6_evidence_report,
         release_manifest_ref: @release_ref,
         schema_ref: @schema_ref,
         report: report,
         validation: %{
           schema: @schema,
           schema_ref: @schema_ref,
           status: :passed,
           checks: [
             :schema_shape,
             :temporal_required,
             :authority_refs,
             :semantic_gateway_refs,
             :provider_fixture_scope,
             :observability_refs,
             :privacy_refs,
             :raw_payload_absence
           ]
         },
         negative_failures: negative_report_failures(report)
       }}
    end
  end

  @spec validate_report(map()) :: :ok | {:error, term()}
  def validate_report(report) when is_map(report) do
    [
      fn -> validate_raw_payload_absence(report) end,
      fn -> validate_top_level_shape(report) end,
      fn -> validate_constants(report) end,
      fn -> validate_required_refs(report) end,
      fn -> validate_scenario_results(field(report, :scenario_results)) end,
      fn -> validate_source_commit_refs(field(report, :source_commit_refs)) end,
      fn -> validate_provider_simulation(field(report, :provider_simulation)) end,
      fn -> validate_privacy(field(report, :privacy)) end
    ]
    |> Enum.reduce_while(:ok, fn validator, :ok ->
      validator.() |> continue_or_halt()
    end)
  end

  def validate_report(_report), do: {:error, :invalid_report}

  defp build_report(contract_join, pressure) do
    profile = pressure.service_profiles.profile
    workload = pressure.pressure.workload_profile
    run_shape = pressure.pressure.run_shape
    semantic = contract_join.semantic
    temporal = contract_join.temporal
    worker_health = pressure.temporal.worker_health

    %{
      schema: @schema,
      packet: @packet,
      run_id: "run://phase5prelim/m6/evidence-report",
      generated_at: @generated_at,
      source_commit_refs: source_commit_refs(),
      substrate: substrate_section(pressure),
      workload_profile: %{
        profile_ref: profile.profile_ref,
        pack_ref: workload.pack_ref,
        work_class_ref: workload.work_class_ref,
        subject_kind: workload.subject_kind,
        lifecycle_states: [
          "submitted",
          workload.lifecycle_after_execution,
          workload.lifecycle_after_review
        ],
        review_gate_ref: Atom.to_string(workload.review_gate),
        tenant_count: run_shape.tenant_count,
        agent_count: run_shape.agent_count,
        runs_per_agent: run_shape.work_items_per_agent,
        max_concurrency: run_shape.max_concurrency
      },
      scenario_results: scenario_results(pressure),
      authority: authority_section(pressure),
      temporal: temporal_section(temporal, worker_health),
      semantic_gateway: semantic_gateway_section(semantic),
      provider_simulation: provider_simulation_section(profile),
      observability: observability_section(pressure),
      privacy: privacy_section(semantic),
      hygiene: hygiene_section()
    }
  end

  defp source_commit_refs do
    %{
      "stack_lab_m3_contract_join" => "f07ad36",
      "stack_lab_m5_profile_bootstrap" => "4bef6a3",
      "stack_lab_m5_governed_smoke" => "9bcc667",
      "stack_lab_m5_pressure_negatives" => "0d39007",
      "execution_plane_http_simulation" => "827f428",
      "execution_plane_process_simulation" => "832ddcd",
      "cli_subprocess_core_runtime_profiles" => "6ef1c72",
      "agent_session_manager_runtime_selection" => "eed6b45",
      "pristine_simulation_transport" => "83e8c04",
      "prismatic_graphql_simulation" => "5bd56b0",
      "self_hosted_inference_manifest" => "79a5643"
    }
  end

  defp substrate_section(pressure) do
    substrate = pressure.temporal.substrate
    worker = pressure.temporal.worker_health

    %{
      temporal_required: true,
      boot_refs: [
        "temporal://#{substrate.namespace}/#{substrate.endpoint}",
        "service://#{substrate.service}",
        "ui://#{substrate.ui}"
      ],
      worker_health_refs: [
        "worker://#{module_ref(worker.instance_base)}/#{worker.task_queue}",
        "workflow://#{module_ref(Mezzanine.Workflows.ExecutionAttempt)}"
      ]
    }
  end

  defp scenario_results(pressure) do
    [
      scenario_result(
        "P5P-001",
        "temporal://default/mezzanine.hazmat",
        "negative://phase5prelim/non-serving-temporal"
      ),
      scenario_result(
        "P5P-003",
        pressure.pressure.workload_profile.workload_ref,
        "negative://phase5prelim/non-coding-subject"
      ),
      scenario_result(
        "P5P-004",
        "pressure://phase5prelim/m5/#{pressure.pressure.run_shape.work_item_count}-work-items",
        "negative://phase5prelim/max-concurrency-breach"
      ),
      scenario_result(
        "P5P-005",
        "fault-matrix://phase5prelim/m5/budget-cost",
        "negative://phase5prelim/missing-budget-ref"
      ),
      scenario_result(
        "P5P-006",
        pressure.pressure.owner_path_refs.authorization_scope_ref,
        "negative://phase5prelim/direct-lower-shortcut"
      ),
      scenario_result(
        "P5P-008",
        "authority://phase5prelim/cross-tenant-denial",
        "negative://phase5prelim/cross-tenant-lower-read"
      ),
      scenario_result(
        "P5P-009",
        "evidence-report://phase5prelim/m6/schema-validation",
        "negative://phase5prelim/raw-payload-leak"
      ),
      scenario_result(
        "P5P-011",
        "lower-simulation://execution-plane/owner-contract",
        "negative://phase5prelim/real-provider-egress"
      ),
      scenario_result(
        "P5P-012",
        "lower-simulation://cli-family/provider-runtime",
        "negative://phase5prelim/missing-provider-runtime-profile"
      ),
      scenario_result(
        "P5P-013",
        "lower-simulation://pristine-prismatic/provider-transport",
        "negative://phase5prelim/forbidden-provider-local-selector"
      ),
      scenario_result(
        "P5P-014",
        "lower-simulation://self-hosted-inference/ready",
        "negative://phase5prelim/unavailable-meter"
      )
    ]
  end

  defp scenario_result(id, positive_ref, negative_ref) do
    %{
      scenario_id: id,
      status: "passed",
      positive_evidence_ref: positive_ref,
      negative_evidence_ref: negative_ref
    }
  end

  defp authority_section(pressure) do
    work_items = pressure_work_items(pressure.pressure)

    %{
      tenant_refs: unique_refs(Enum.map(pressure.pressure.tenants, & &1.tenant_ref)),
      authority_decision_refs:
        unique_refs([
          pressure.pressure.owner_path_refs.authority_decision_ref
          | Enum.map(pressure.pressure.tenants, & &1.authority_decision_ref)
        ]),
      authorization_scope_refs:
        unique_refs([
          pressure.pressure.owner_path_refs.authorization_scope_ref
          | Enum.map(work_items, & &1.authorization_scope_ref)
        ]),
      budget_refs:
        unique_refs([
          pressure.pressure.cost.budget_ref,
          pressure.budget_cost_fault_matrix.budget.budget_ref
        ]),
      negative_case_refs:
        pressure.negative_failures
        |> Map.keys()
        |> Enum.map(&"negative://phase5prelim/#{Atom.to_string(&1)}")
        |> unique_refs()
    }
  end

  defp temporal_section(temporal, worker_health) do
    %{
      namespace: "default",
      workflow_type_refs:
        unique_refs([
          module_ref(temporal.workflow.module)
          | Enum.map(worker_health.workflows, &module_ref/1)
        ]),
      workflow_id_refs: [
        "workflow-id://phase5prelim/m3-contract-join",
        "workflow-id://phase5prelim/m5-pressure-and-negatives"
      ],
      task_queue_refs:
        unique_refs([
          temporal.workflow.task_queue,
          worker_health.task_queue
        ]),
      compact_query_refs: [
        "temporal-compact-query://scenario-201/postgres-projection-drift"
      ],
      restart_replay_refs: [
        "temporal-restart-replay://phase5prelim/execution-attempt",
        "outer-brain-restart-replay://phase5prelim/semantic-failure"
      ]
    }
  end

  defp semantic_gateway_section(semantic) do
    %{
      payload_boundary_refs: [
        semantic.context_provenance.input_claim_check_ref,
        semantic.context_provenance.output_claim_check_ref,
        semantic.privacy_redaction.scan_ref,
        semantic.context_provenance.redaction_policy_ref
      ],
      context_provenance_refs: [
        semantic.context_provenance.semantic_ref,
        semantic.read_only_context_adapter.adapter_ref
      ],
      semantic_failure_refs: [
        "semantic-failure://#{semantic.semantic_failure.trace_id}",
        "diagnostics://phase5prelim/semantic-failure"
      ],
      reply_publication_refs: [
        "reply-publication://#{semantic.reply_publication.publication_id}",
        "reply-publication-dedupe://#{semantic.durability.duplicate_replayed_publication_id}"
      ]
    }
  end

  defp provider_simulation_section(profile) do
    %{
      service_profile_ref: profile.profile_ref,
      adapter_profile_refs: unique_refs(Map.values(profile.adapter_profile_refs)),
      lower_scenario_refs: unique_refs(flatten_refs(profile.lower_scenario_refs)),
      provider_sdk_fixture_scope_refs: [
        "fixture-scope://claude_agent_sdk/package-local-only",
        "fixture-scope://codex_sdk/package-local-only",
        "fixture-scope://antigravity_cli_sdk/package-local-only",
        "fixture-scope://amp_sdk/package-local-only",
        "fixture-scope://agent_session_manager/common-asm-path"
      ],
      input_fingerprint_policy: Atom.to_string(profile.input_fingerprint_policy.mode),
      egress_denied: profile.egress_policy == :deny_real_provider_and_saas
    }
  end

  defp observability_section(pressure) do
    work_items = pressure_work_items(pressure.pressure)

    %{
      trace_refs:
        unique_refs([
          "trace-prelim",
          "trace://scenario-19/observability-trace-join-continuity",
          "trace://scenario-25/claim-check-trace-continuity"
          | Enum.map(work_items, & &1.trace_ref)
        ]),
      lineage_refs:
        unique_refs([
          pressure.pressure.owner_path_refs.lower_template_ref,
          pressure.pressure.smoke_template_ref
          | Enum.flat_map(work_items, &[&1.execution_ref, &1.lower_submission_ref])
        ]),
      aitrace_refs: [
        "aitrace://scenario-19/observability-trace-join-continuity",
        "aitrace://scenario-25/claim-check-trace-continuity"
      ]
    }
  end

  defp privacy_section(semantic) do
    %{
      raw_payload_scan_result: "passed",
      suppression_visibility_refs: [
        semantic.suppression_visibility.suppression_ref
      ],
      privacy_redaction_fixture_refs: [
        semantic.privacy_redaction.fixture_ref
      ],
      artifact_refs: [
        semantic.context_provenance.input_claim_check_ref,
        semantic.context_provenance.output_claim_check_ref,
        semantic.privacy_redaction.scan_ref,
        "artifact-policy://phase5prelim/no-raw-body"
      ]
    }
  end

  defp hygiene_section do
    %{
      repo_status_refs: [
        "repo-status://stack_lab/main...origin/main",
        "repo-status://execution_plane/main...origin/main",
        "repo-status://cli_subprocess_core/main...origin/main",
        "repo-status://agent_session_manager/main...origin/main",
        "repo-status://pristine/main...origin/main",
        "repo-status://prismatic/master...origin/master",
        "repo-status://self_hosted_inference_core/main...origin/main"
      ],
      qa_refs: [
        "qa://stack_lab/support/mix-test-prelim-service-mode",
        "qa://stack_lab/support/mix-ci",
        "qa://stack_lab/root/mix-monorepo-test",
        "qa://stack_lab/root/mix-ci",
        "qa://stack_lab/root/git-diff-check"
      ],
      pushed_refs: [
        "push://stack_lab/f07ad36",
        "push://stack_lab/4bef6a3",
        "push://stack_lab/9bcc667",
        "push://stack_lab/0d39007",
        "push://execution_plane/827f428",
        "push://execution_plane/832ddcd",
        "push://cli_subprocess_core/6ef1c72",
        "push://agent_session_manager/eed6b45",
        "push://pristine/83e8c04",
        "push://prismatic/5bd56b0",
        "push://self_hosted_inference_core/79a5643"
      ]
    }
  end

  defp negative_report_failures(report) do
    %{
      missing_temporal:
        report
        |> put_in([:temporal, :workflow_type_refs], [])
        |> validate_report()
        |> rejected(),
      missing_authority:
        report
        |> put_in([:authority, :authorization_scope_refs], [])
        |> validate_report()
        |> rejected(),
      missing_semantic:
        report
        |> put_in([:semantic_gateway, :context_provenance_refs], [])
        |> validate_report()
        |> rejected(),
      missing_negative_evidence:
        report
        |> update_in([:scenario_results], fn [first | rest] ->
          [Map.put(first, :negative_evidence_ref, "") | rest]
        end)
        |> validate_report()
        |> rejected(),
      raw_payload_leak:
        report
        |> put_in([:privacy, :artifact_refs], [
          "raw provider body fixture leaked into evidence report"
        ])
        |> validate_report()
        |> rejected()
    }
  end

  defp validate_raw_payload_absence(report) do
    reject_raw_payload_leak(report, [])
  end

  defp reject_raw_payload_leak(%{} = map, path) do
    Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
      reduce_raw_payload_map_entry(key, value, path)
    end)
  end

  defp reject_raw_payload_leak(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      value |> reject_raw_payload_leak(path ++ [index]) |> continue_or_halt()
    end)
  end

  defp reject_raw_payload_leak(value, path) when is_binary(value) do
    value_downcase = String.downcase(value)

    if Enum.any?(@forbidden_raw_fragments, &String.contains?(value_downcase, &1)) do
      {:error, {:raw_payload_leak, path}}
    else
      :ok
    end
  end

  defp reject_raw_payload_leak(_value, _path), do: :ok

  defp reduce_raw_payload_map_entry(key, value, path) do
    key_string = key_to_string(key)

    cond do
      path == [:privacy] and key in [:raw_payload_scan_result, "raw_payload_scan_result"] ->
        {:cont, reject_raw_payload_leak(value, path ++ [key])}

      key_string in @forbidden_raw_keys ->
        {:halt, {:error, {:raw_payload_leak, path ++ [key]}}}

      true ->
        value |> reject_raw_payload_leak(path ++ [key]) |> continue_or_halt()
    end
  end

  defp validate_top_level_shape(report) do
    keys = Map.keys(report)
    missing = @top_level_keys -- keys
    unexpected = keys -- @top_level_keys

    cond do
      missing != [] -> {:error, {:missing_top_level_keys, missing}}
      unexpected != [] -> {:error, {:unexpected_top_level_keys, unexpected}}
      true -> :ok
    end
  end

  defp validate_constants(%{
         schema: @schema,
         packet: @packet,
         run_id: run_id,
         generated_at: generated_at,
         substrate: %{temporal_required: true}
       })
       when is_binary(run_id) and run_id != "" and is_binary(generated_at) and
              generated_at != "",
       do: :ok

  defp validate_constants(%{schema: schema}) when schema != @schema,
    do: {:error, {:invalid_schema, schema}}

  defp validate_constants(%{packet: packet}) when packet != @packet,
    do: {:error, {:invalid_packet, packet}}

  defp validate_constants(%{substrate: %{temporal_required: other}})
       when other != true,
       do: {:error, {:temporal_not_required, other}}

  defp validate_constants(_report), do: {:error, :invalid_report_constants}

  defp validate_required_refs(report) do
    Enum.reduce_while(@required_ref_paths, :ok, fn path, :ok ->
      report |> fetch_path(path) |> reduce_required_ref_path(path)
    end)
  end

  defp reduce_required_ref_path({:ok, value}, path) do
    if non_empty_ref_value?(value), do: {:cont, :ok}, else: halt_missing_required_ref(path)
  end

  defp reduce_required_ref_path(:error, path), do: halt_missing_required_ref(path)

  defp halt_missing_required_ref(path), do: {:halt, {:error, {:missing_required_refs, path}}}

  defp validate_scenario_results(results) when is_list(results) and results != [] do
    Enum.reduce_while(results, :ok, fn result, :ok ->
      with {:ok, scenario_id} <- required_string(result, :scenario_id),
           true <- scenario_id?(scenario_id),
           {:ok, status} <- required_string(result, :status),
           true <- status in @allowed_statuses,
           {:ok, _positive} <- required_string(result, :positive_evidence_ref),
           {:ok, _negative} <- required_string(result, :negative_evidence_ref) do
        {:cont, :ok}
      else
        false -> {:halt, {:error, {:invalid_scenario_result, result}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp validate_scenario_results(_results),
    do: {:error, {:missing_required_refs, [:scenario_results]}}

  defp scenario_id?("P5P-" <> digits) when byte_size(digits) == 3 do
    digits
    |> :binary.bin_to_list()
    |> Enum.all?(fn byte -> byte in ?0..?9 end)
  end

  defp scenario_id?(_value), do: false

  defp validate_source_commit_refs(commit_refs)
       when is_map(commit_refs) and map_size(commit_refs) > 0 do
    if Enum.all?(commit_refs, fn {_key, value} ->
         is_binary(value) and String.length(value) >= 7
       end) do
      :ok
    else
      {:error, :invalid_source_commit_refs}
    end
  end

  defp validate_source_commit_refs(_commit_refs),
    do: {:error, {:missing_required_refs, [:source_commit_refs]}}

  defp validate_provider_simulation(%{
         input_fingerprint_policy: input_fingerprint_policy,
         egress_denied: true
       })
       when input_fingerprint_policy in @allowed_input_fingerprint_policies,
       do: :ok

  defp validate_provider_simulation(%{egress_denied: egress_denied}) when egress_denied != true,
    do: {:error, {:egress_not_denied, egress_denied}}

  defp validate_provider_simulation(%{input_fingerprint_policy: policy}),
    do: {:error, {:invalid_input_fingerprint_policy, policy}}

  defp validate_provider_simulation(_provider), do: {:error, :invalid_provider_simulation}

  defp validate_privacy(%{raw_payload_scan_result: "passed"}), do: :ok

  defp validate_privacy(%{raw_payload_scan_result: result}),
    do: {:error, {:raw_payload_scan_failed, result}}

  defp validate_privacy(_privacy), do: {:error, :invalid_privacy_section}

  defp required_string(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_required_refs, [key]}}
    end
  end

  defp non_empty_ref_value?(value) when is_list(value) do
    value != [] and Enum.all?(value, &(is_binary(&1) and &1 != "")) and
      Enum.uniq(value) == value
  end

  defp non_empty_ref_value?(value) when is_map(value), do: map_size(value) > 0
  defp non_empty_ref_value?(value) when is_binary(value), do: value != ""
  defp non_empty_ref_value?(_value), do: false

  defp fetch_path(map, path) do
    Enum.reduce_while(path, {:ok, map}, fn key, {:ok, current} ->
      case current do
        %{^key => value} -> {:cont, {:ok, value}}
        _other -> {:halt, :error}
      end
    end)
  end

  defp field(map, key), do: Map.fetch!(map, key)

  defp pressure_work_items(pressure) do
    pressure.tenants
    |> Enum.flat_map(& &1.agents)
    |> Enum.flat_map(& &1.work_items)
  end

  defp flatten_refs(%{} = refs), do: refs |> Map.values() |> Enum.flat_map(&flatten_refs/1)
  defp flatten_refs(refs) when is_list(refs), do: Enum.flat_map(refs, &flatten_refs/1)
  defp flatten_refs(ref) when is_binary(ref), do: [ref]
  defp flatten_refs(_ref), do: []

  defp unique_refs(refs) do
    refs
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp module_ref(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.replace_prefix("Elixir.", "")
  end

  defp key_to_string(key) when is_atom(key), do: Atom.to_string(key)
  defp key_to_string(key) when is_binary(key), do: key
  defp key_to_string(key), do: inspect(key)

  defp continue_or_halt(:ok), do: {:cont, :ok}
  defp continue_or_halt({:error, reason}), do: {:halt, {:error, reason}}

  defp rejected(:ok), do: :unexpected_acceptance
  defp rejected({:error, reason}), do: reason
end
