defmodule StackLab.CitadelSpineHarness.Phase6EvidenceReport do
  @moduledoc false

  @contract "SimulationEvidenceReport.v1"
  @schema_ref "contracts/phase6_evidence_report.schema.json"
  @report_id "phase6-m12-simulation-evidence-report"
  @scenario 611

  @stack_lab_root Path.expand("../../../../..", __DIR__)
  @repo_parent Path.expand("..", @stack_lab_root)
  @schema_path Path.expand(
                 "../j/jido_brainstorm/nshkrdotcom/docs/20260421/ecosystem_buildout_phase6/contracts/phase6_evidence_report.schema.json",
                 @repo_parent
               )

  @forbidden_raw_keys [
    "raw_payload",
    "raw_prompt",
    "provider_body",
    "raw_provider_body",
    "full_prompt",
    "workflow_history"
  ]

  @forbidden_raw_fragments [
    "raw_payload",
    "raw prompt",
    "raw_prompt",
    "raw provider body",
    "provider_body",
    "full_prompt",
    "workflow history"
  ]

  @required_ref_checks [
    {["authority", "tenant_refs"], :list, :missing_tenant_evidence},
    {["authority", "authority_decision_refs"], :list, :missing_authority_evidence},
    {["authority", "authorization_scope_refs"], :list, :missing_authority_evidence},
    {["temporal", "worker_health_refs"], :list, :missing_temporal_worker_evidence},
    {["outer_brain", "semantic_provenance_refs"], :list, :missing_semantic_provenance},
    {["no_egress", "policy_ref"], :ref, :missing_no_egress_policy},
    {["no_egress", "negative_refs"], :list, :missing_no_egress_policy},
    {["results", "negative_evidence_refs"], :list, :missing_negative_evidence},
    {["results", "owner_evidence_refs"], :list, :missing_owner_evidence}
  ]

  @spec schema_ref() :: String.t()
  def schema_ref, do: @schema_ref

  @spec schema_path() :: String.t()
  def schema_path, do: @schema_path

  @spec valid_report() :: map()
  def valid_report do
    %{
      "report_id" => @report_id,
      "profile" => profile_section(),
      "source_repos" => source_repos(),
      "governed_workload" => governed_workload_section(),
      "authority" => authority_section(),
      "temporal" => temporal_section(),
      "outer_brain" => outer_brain_section(),
      "provider_families" => provider_families_section(),
      "no_egress" => no_egress_section(),
      "lineage" => lineage_section(),
      "raw_payload_scan" => raw_payload_scan_section(),
      "cleanup" => cleanup_section(),
      "results" => results_section()
    }
  end

  @spec run_case(:validated_report) :: {:ok, map()} | {:error, term()}
  def run_case(:validated_report) do
    report = valid_report()

    with :ok <- validate_report(report) do
      {:ok,
       %{
         case: :validated_report,
         scenario: @scenario,
         contract: @contract,
         schema_ref: @schema_ref,
         schema_path: @schema_path,
         report: report,
         validation: %{
           status: :passed,
           schema_ref: @schema_ref,
           schema_validation: :passed,
           owner_evidence: :passed,
           aitrace_lineage_join: :passed,
           no_egress: :passed,
           negative_controls: :passed
         },
         negative_failures: negative_report_failures(report)
       }}
    end
  end

  @spec validate_report(map()) :: :ok | {:error, term()}
  def validate_report(%{} = report) do
    [
      fn -> reject_raw_payload_leak(report) end,
      fn -> validate_required_report_refs(report) end,
      fn -> validate_owner_evidence(report) end,
      fn -> validate_aitrace_lineage(report) end,
      fn -> validate_no_egress(report) end,
      fn -> validate_raw_payload_scan(report) end,
      fn -> validate_cleanup(report) end,
      fn -> validate_schema(report) end
    ]
    |> Enum.reduce_while(:ok, fn validator, :ok ->
      validator.() |> continue_or_halt()
    end)
  end

  def validate_report(_report), do: {:error, :invalid_evidence_report}

  defp profile_section do
    %{
      "service_profile_ref" =>
        "contract://ServiceSimulationProfile.v1/phase6/m3/jido-service-profile",
      "version" => "phase6.v1",
      "registry_entry_ref" =>
        "profile-registry-entry://jido_integration/phase6/m4/persistent-service-profile",
      "registry_lifecycle_refs" => [
        "profile-registry://jido_integration/m4/install",
        "profile-registry://jido_integration/m4/activate",
        "profile-registry://jido_integration/m4/cleanup"
      ],
      "lower_scenario_refs" => [
        "lower-scenario://execution-plane/m10/no-egress",
        "phase6://scenario-606/cli/claude",
        "phase6://scenario-606/rest/notion-github",
        "phase6://scenario-606/graphql/linear",
        "phase6://scenario-606/self-hosted/ready"
      ],
      "scale_pressure_profile_ref" => "scale-pressure-profile://phase6/m11/bounded-local-pressure"
    }
  end

  defp source_repos do
    [
      source_repo(
        "app_kit",
        "51cdab4e6640764eac233025a50f540e9e139266",
        "mix ci (app_kit root)",
        "GovernedAgentWorkloadContract.v1 owner evidence"
      ),
      source_repo(
        "jido_integration",
        "9a4550a8b859f46d58d3a9d0dd36826994463983",
        "mix ci (jido_integration root)",
        "SimulationProfileRegistryEntry.v1 persistent registry lifecycle"
      ),
      source_repo(
        "mezzanine",
        "ddf31d14c7b8e992bd2aa28353ecf416cc4e69d0",
        "mix ci (mezzanine root)",
        "TemporalDispatchContract.v1 owner evidence"
      ),
      source_repo(
        "outer_brain",
        "ad28808069a9beed47371ee518e3e0074caeccf7",
        "mix ci (outer_brain root)",
        "SemanticGatewayContract.v1 owner evidence"
      ),
      source_repo(
        "citadel",
        "a2d69b75468d33f80c2415cb389fca058a7688b5",
        "mix ci (citadel root)",
        "AuthorityTenantPropagation.v1 owner evidence"
      ),
      source_repo(
        "execution_plane",
        "9a49ac63bb4a8717460488fc99bcc6c9e10c5a0d",
        "mix ci (execution_plane root)",
        "NoEgressPolicy.v1 lower simulation boundary"
      ),
      source_repo(
        "stack_lab",
        "490feac6e000f07eb8f8d34339756fed5c00f58a",
        "mix ci (support/citadel_spine_harness and stack_lab root)",
        "ScalePressureProfile.v1 and M5-M11 composed owner evidence"
      ),
      source_repo(
        "AITrace",
        "ac3427c1f4a6741ca1a6544b6e2f4f442830aba8",
        "source-read-only AITrace file-export receipt contract",
        "AITrace anchored evidence receipt and export-boundary source"
      )
    ]
  end

  defp source_repo(repo, commit, gate, evidence_ref) do
    %{
      "repo" => repo,
      "commit" => commit,
      "pushed" => true,
      "gate" => gate,
      "evidence_ref" => evidence_ref
    }
  end

  defp governed_workload_section do
    %{
      "ingress_ref" => "app_kit_operator_surface_via_mezzanine_bridge",
      "work_class_ref" => "stack_lab/work_classes/service_operations",
      "pack_ref" => "mezzanine/packs/stack_lab_service_ops@1",
      "subject_refs" => [
        "subject://phase6/m5/governed-coding-operation",
        "subject-kind://service_task"
      ],
      "review_gate_refs" => [
        "stack_lab/review_gates/operator_review",
        "review-action://phase6/m5/operator-accept"
      ],
      "lifecycle_refs" => [
        "lifecycle://phase6/m5/submitted",
        "lifecycle://phase6/m5/awaiting_review",
        "lifecycle://phase6/m5/completed",
        "lifecycle://phase6/m5/rejected",
        "lifecycle://phase6/m5/expired"
      ]
    }
  end

  defp authority_section do
    %{
      "tenant_refs" => [
        "tenant:tenant-phase6-m8",
        "tenant://phase6/m11/t1",
        "tenant://phase6/m11/t2",
        "tenant://phase6/m11/t3"
      ],
      "authority_decision_refs" => [
        "authority-decision:phase6-m8",
        "decision-stack-lab-m6"
      ],
      "authorization_scope_refs" => [
        "authorization-scope://tenant-phase6-m8/exec-phase6-m8",
        "authorization-scope://phase6/m11/t1/a1/i1"
      ],
      "budget_refs" => [
        "budget://phase6/m8/local-no-spend",
        "budget://phase6/m11/local-no-spend"
      ],
      "negative_refs" => [
        "negative://phase6/m8/harness-self-assertion",
        "negative://phase6/m8/cross-tenant-lower-read",
        "negative://phase6/m8/direct-lower-shortcut"
      ]
    }
  end

  defp temporal_section do
    %{
      "worker_health_refs" => [
        "temporal-worker://default/mezzanine.hazmat",
        "temporal-worker://default/mezzanine.semantic"
      ],
      "workflow_refs" => [
        "workflow://Mezzanine.Workflows.ExecutionAttempt",
        "temporal-workflow://phase6-m6-just-restart-9539/019db780-8aa9-7a00-ad0e-d05ddc2ee1bf"
      ],
      "restart_replay_refs" => [
        "mezzanine-just://temporal-restart",
        "temporal-replay://phase6/m6/execution-attempt",
        "workflow-start-outbox://outbox-m6-9539/started/019db780-8aa9-7a00-ad0e-d05ddc2ee1bf"
      ],
      "raw_workflow_history_included" => false
    }
  end

  defp outer_brain_section do
    %{
      "semantic_provenance_refs" => [
        "semantic:result-phase6-m7",
        "context-adapter:phase6-m7"
      ],
      "failure_refs" => [
        "semantic_failure_journal:v1:phase6-m7"
      ],
      "dedupe_refs" => [
        "reply-publication-dedupe://phase6/m7/causal-final"
      ],
      "privacy_refs" => [
        "suppression:phase6-m7",
        "fixture:phase6-m7-privacy"
      ],
      "restart_refs" => [
        "outer-brain-restart://phase6/m7/semantic-state",
        "outer-brain-replay://phase6/m7/duplicate-publication-suppressed"
      ]
    }
  end

  defp provider_families_section do
    %{
      "cli" => %{
        "owner_repos" => ["cli_subprocess_core", "agent_session_manager"],
        "profile_refs" => [
          "phase6://scenario-606/cli/claude",
          "phase6://scenario-606/cli/codex",
          "phase6://scenario-606/cli/gemini",
          "phase6://scenario-606/cli/amp"
        ],
        "negative_refs" => [
          "negative://phase6/m9/required-provider-runtime-profile",
          "negative://phase6/m9/sdk-lane-blocked"
        ]
      },
      "rest" => %{
        "owner_repos" => ["pristine"],
        "profile_refs" => ["phase6://scenario-606/rest/notion-github"],
        "negative_refs" => ["negative://phase6/m9/rest-public-selector-blocked"]
      },
      "graphql" => %{
        "owner_repos" => ["prismatic"],
        "profile_refs" => ["phase6://scenario-606/graphql/linear"],
        "negative_refs" => ["negative://phase6/m9/graphql-public-selector-blocked"]
      },
      "self_hosted" => %{
        "owner_repos" => ["self_hosted_inference_core"],
        "profile_refs" => ["phase6://scenario-606/self-hosted/ready"],
        "negative_refs" => [
          "negative://phase6/m9/self-hosted-boot-spec-blocked",
          "negative://phase6/m9/local-subprocess-blocked"
        ]
      }
    }
  end

  defp no_egress_section do
    %{
      "policy_ref" => "no-egress://phase6/m12/report-validation",
      "positive_refs" => [
        "no-egress://phase6/m10/execution-plane-lower-boundary",
        "no-egress://phase6/m11/scale-pressure"
      ],
      "negative_refs" => [
        "negative://phase6/m10/attempted-unregistered-provider-route",
        "negative://phase6/m10/attempted-external-saas-write",
        "negative://phase6/m11/attempted-unregistered-provider-route",
        "negative://phase6/m11/attempted-raw-external-saas-write-path"
      ],
      "provider_spend_cents" => 0,
      "external_write_refs" => []
    }
  end

  defp lineage_section do
    %{
      "trace_refs" => [
        "trace-stack-lab-m6",
        "trace://phase6/m8/authority-tenant",
        "trace://phase6/m11/t1/a1/i1"
      ],
      "aitrace_refs" => [
        "aitrace://phase6/m12/report-validation/root",
        "aitrace://phase6/m12/report-validation/lineage-join"
      ],
      "aitrace_receipt_refs" => [
        "aitrace://evidence-receipt/phase6-m12-report-validation-root",
        "aitrace://evidence-receipt/phase6-m12-report-validation-lineage-join"
      ],
      "join_ref" => "lineage-join://phase6/m12/aitrace-owner-receipts"
    }
  end

  defp raw_payload_scan_section do
    %{
      "status" => "pass",
      "scan_refs" => [
        "scan://phase6/m12/payload-boundary-absence",
        "aitrace://export-bounds/phase6/m12/hash-spillover"
      ]
    }
  end

  defp cleanup_section do
    %{
      "status" => "pass",
      "cleanup_refs" => [
        "profile-cleanup://phase6/m11/scale-pressure",
        "stack-lab-cleanup://phase6/m12/report-validation"
      ]
    }
  end

  defp results_section do
    %{
      "positive_evidence_refs" => [
        "evidence://phase6/m5/governed-agent-workload",
        "evidence://phase6/m6/temporal-dispatch",
        "evidence://phase6/m7/semantic-gateway",
        "evidence://phase6/m8/authority-tenant",
        "evidence://phase6/m9/provider-family-runtime",
        "evidence://phase6/m10/no-egress-lower-boundary",
        "evidence://phase6/m11/scale-pressure"
      ],
      "negative_evidence_refs" => [
        "negative://phase6/m6/missing-worker",
        "negative://phase6/m7/missing-semantic-provenance",
        "negative://phase6/m8/missing-authority",
        "negative://phase6/m10/egress-attempt",
        "negative://phase6/m11/cleanup-failure"
      ],
      "owner_evidence_refs" => [
        "push://app_kit/51cdab4e6640764eac233025a50f540e9e139266",
        "push://jido_integration/9a4550a8b859f46d58d3a9d0dd36826994463983",
        "push://mezzanine/ddf31d14c7b8e992bd2aa28353ecf416cc4e69d0",
        "push://outer_brain/ad28808069a9beed47371ee518e3e0074caeccf7",
        "push://citadel/a2d69b75468d33f80c2415cb389fca058a7688b5",
        "push://execution_plane/9a49ac63bb4a8717460488fc99bcc6c9e10c5a0d",
        "push://stack_lab/490feac6e000f07eb8f8d34339756fed5c00f58a",
        "push://AITrace/ac3427c1f4a6741ca1a6544b6e2f4f442830aba8"
      ],
      "summary" =>
        "Phase 6 M12 evidence report joins committed owner evidence, AITrace receipts, lineage, no-egress, cleanup, and negative controls."
    }
  end

  defp negative_report_failures(report) do
    %{
      missing_authority:
        report
        |> put_in(["authority", "authority_decision_refs"], [])
        |> validate_report()
        |> rejected(),
      missing_tenant:
        report
        |> put_in(["authority", "tenant_refs"], [])
        |> validate_report()
        |> rejected(),
      missing_semantic_provenance:
        report
        |> put_in(["outer_brain", "semantic_provenance_refs"], [])
        |> validate_report()
        |> rejected(),
      missing_temporal_worker:
        report
        |> put_in(["temporal", "worker_health_refs"], [])
        |> validate_report()
        |> rejected(),
      missing_no_egress:
        report
        |> put_in(["no_egress", "policy_ref"], "")
        |> validate_report()
        |> rejected(),
      raw_payload_leak:
        report
        |> put_in(["results", "positive_evidence_refs", Access.at(0)], "raw provider body leaked")
        |> validate_report()
        |> rejected(),
      local_only_proof:
        report
        |> put_in(["source_repos", Access.at(0), "pushed"], false)
        |> validate_report()
        |> rejected(),
      missing_aitrace_receipt:
        report
        |> put_in(["lineage", "aitrace_receipt_refs"], [])
        |> validate_report()
        |> rejected()
    }
  end

  defp validate_required_report_refs(report) do
    Enum.reduce_while(@required_ref_checks, :ok, fn {path, kind, reason}, :ok ->
      if missing_ref?(get_in(report, path), kind),
        do: {:halt, {:error, reason}},
        else: {:cont, :ok}
    end)
  end

  defp validate_owner_evidence(report) do
    source_repos = Map.get(report, "source_repos", [])
    owner_refs = get_in(report, ["results", "owner_evidence_refs"]) || []

    cond do
      not source_repos_valid?(source_repos) ->
        {:error, :missing_owner_evidence}

      Enum.any?(source_repos, &(Map.get(&1, "pushed") != true)) ->
        {:error, :local_only_owner_evidence}

      not Enum.any?(source_repos, &(Map.get(&1, "repo") == "stack_lab")) ->
        {:error, :missing_owner_evidence}

      not Enum.any?(source_repos, &(Map.get(&1, "repo") == "AITrace")) ->
        {:error, :missing_aitrace_receipt}

      Enum.any?(owner_refs, &local_only_ref?/1) ->
        {:error, :local_only_owner_evidence}

      true ->
        :ok
    end
  end

  defp validate_aitrace_lineage(report) do
    lineage = Map.get(report, "lineage", %{})

    cond do
      empty_ref_list?(Map.get(lineage, "trace_refs")) ->
        {:error, :missing_lineage_refs}

      empty_ref_list?(Map.get(lineage, "aitrace_refs")) ->
        {:error, :missing_aitrace_refs}

      empty_ref_list?(Map.get(lineage, "aitrace_receipt_refs")) ->
        {:error, :missing_aitrace_receipt}

      empty_ref?(Map.get(lineage, "join_ref")) ->
        {:error, :missing_lineage_join}

      not Enum.all?(
        Map.get(lineage, "aitrace_receipt_refs", []),
        &String.starts_with?(&1, "aitrace://evidence-receipt/")
      ) ->
        {:error, :missing_aitrace_receipt}

      true ->
        :ok
    end
  end

  defp validate_no_egress(report) do
    no_egress = Map.get(report, "no_egress", %{})

    cond do
      empty_ref?(Map.get(no_egress, "policy_ref")) ->
        {:error, :missing_no_egress_policy}

      empty_ref_list?(Map.get(no_egress, "positive_refs")) ->
        {:error, :missing_no_egress_policy}

      empty_ref_list?(Map.get(no_egress, "negative_refs")) ->
        {:error, :missing_no_egress_policy}

      Map.get(no_egress, "provider_spend_cents") != 0 ->
        {:error, :real_provider_spend_detected}

      Map.get(no_egress, "external_write_refs") != [] ->
        {:error, :external_writes_detected}

      true ->
        :ok
    end
  end

  defp validate_raw_payload_scan(report) do
    raw_payload_scan = Map.get(report, "raw_payload_scan", %{})

    cond do
      Map.get(raw_payload_scan, "status") != "pass" ->
        {:error, :raw_payload_scan_failed}

      empty_ref_list?(Map.get(raw_payload_scan, "scan_refs")) ->
        {:error, :raw_payload_scan_failed}

      true ->
        :ok
    end
  end

  defp validate_cleanup(report) do
    cleanup = Map.get(report, "cleanup", %{})

    cond do
      Map.get(cleanup, "status") != "pass" ->
        {:error, :cleanup_required}

      empty_ref_list?(Map.get(cleanup, "cleanup_refs")) ->
        {:error, :cleanup_required}

      true ->
        :ok
    end
  end

  defp validate_schema(report) do
    @schema_path
    |> File.read!()
    |> Jason.decode!()
    |> JSV.build!()
    |> then(&JSV.validate(report, &1))
    |> case do
      {:ok, _validated} ->
        :ok

      {:error, validation_error} ->
        {:error, {:schema_validation_failed, JSV.normalize_error(validation_error)}}
    end
  end

  defp source_repos_valid?(repos) when is_list(repos) and repos != [] do
    Enum.all?(repos, fn repo ->
      is_map(repo) and not empty_ref?(Map.get(repo, "repo")) and
        not empty_ref?(Map.get(repo, "commit")) and not empty_ref?(Map.get(repo, "gate"))
    end)
  end

  defp source_repos_valid?(_repos), do: false

  defp reject_raw_payload_leak(report) do
    do_reject_raw_payload_leak(report, [])
  end

  defp do_reject_raw_payload_leak(%{} = map, path) do
    Enum.reduce_while(map, :ok, fn {key, value}, :ok ->
      if key in @forbidden_raw_keys,
        do: {:halt, {:error, {:raw_payload_leak, path ++ [key]}}},
        else: value |> do_reject_raw_payload_leak(path ++ [key]) |> continue_or_halt()
    end)
  end

  defp do_reject_raw_payload_leak(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      value |> do_reject_raw_payload_leak(path ++ [index]) |> continue_or_halt()
    end)
  end

  defp do_reject_raw_payload_leak(value, path) when is_binary(value) do
    normalized = String.downcase(value)

    if Enum.any?(@forbidden_raw_fragments, &String.contains?(normalized, &1)) do
      {:error, {:raw_payload_leak, path}}
    else
      :ok
    end
  end

  defp do_reject_raw_payload_leak(_value, _path), do: :ok

  defp local_only_ref?(ref) when is_binary(ref) do
    String.starts_with?(ref, ["local://", "file://", "proof://local"])
  end

  defp local_only_ref?(_ref), do: true

  defp empty_ref_list?(values) when is_list(values) do
    values == [] or Enum.any?(values, &empty_ref?/1)
  end

  defp empty_ref_list?(_values), do: true

  defp missing_ref?(value, :list), do: empty_ref_list?(value)
  defp missing_ref?(value, :ref), do: empty_ref?(value)

  defp empty_ref?(value) when is_binary(value), do: String.trim(value) == ""
  defp empty_ref?(nil), do: true
  defp empty_ref?(_value), do: false

  defp continue_or_halt(:ok), do: {:cont, :ok}
  defp continue_or_halt({:error, reason}), do: {:halt, {:error, reason}}

  defp rejected({:error, reason}), do: reason
  defp rejected(:ok), do: :unexpected_acceptance
end
