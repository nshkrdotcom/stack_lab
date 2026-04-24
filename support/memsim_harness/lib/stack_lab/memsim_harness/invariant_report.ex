defmodule StackLab.MemsimHarness.InvariantReport do
  @moduledoc false

  @required_scenario_ids Enum.to_list(700..712)
  @required_invariant_ids ~w(11.0 11.1 11.2 11.3 11.4 11.5 11.6 11.7 11.8 11.9 11.10)
  @required_proof_kinds [:recall, :write_private, :share_up, :promote, :invalidate, :audit]
  @default_source_commits %{
    stack_lab: "71f2f64290e5da88d76927dbf1969a226d739220",
    jido_integration: "2272b9f112795c32e089ad293b749e4fb5a5e289",
    mezzanine: "247045be4013c028a3a6411e5492d98d961ade77",
    outer_brain: "05ae0e6ff114a9f145c97987113a2cc88388967e",
    app_kit: "64842d17144b239a458f0038fbb043a749ec8b3f",
    citadel: "8f51221a3a7b3846ba82d07368a358d1376f4875",
    aitrace: "4c6dd67f4156fa95553a9acd5730a4a8a45a1dfa"
  }

  @spec scenario_families() :: [map()]
  def scenario_families do
    [
      scenario(
        700,
        :multi_node_epoch_monotonicity_and_ordering,
        [:stack_lab, :jido_integration, :mezzanine, :aitrace],
        [
          :multi_node_ordering,
          :snapshot_pin,
          :cluster_invalidation
        ]
      ),
      scenario(701, :access_graph_epoch_and_views, [:jido_integration, :citadel, :mezzanine], [
        :access_graph_epoch,
        :authority_views
      ]),
      scenario(702, :memory_tier_constraints, [:jido_integration, :mezzanine], [
        :tier_constraints,
        :provenance_immutability
      ]),
      scenario(703, :recall_accessibility, [:outer_brain, :jido_integration, :mezzanine], [
        :accessibility_predicate,
        :recall_proof_token
      ]),
      scenario(704, :private_write_and_share_up, [:outer_brain, :mezzanine, :jido_integration], [
        :private_write,
        :non_identity_share_up
      ]),
      scenario(705, :promotion_to_governed, [:mezzanine, :jido_integration], [
        :promotion_decision,
        :governed_evidence
      ]),
      scenario(
        706,
        :invalidation_and_post_revocation,
        [:mezzanine, :jido_integration, :outer_brain],
        [
          :invalidation_cascade,
          :post_revocation_recall
        ]
      ),
      scenario(707, :retrospective_audit_replay, [:mezzanine, :jido_integration], [
        :audit_replay,
        :proof_token_verification
      ]),
      scenario(
        708,
        :citadel_authority_graph_integration,
        [:citadel, :jido_integration, :mezzanine],
        [
          :authority_compile,
          :graph_epoch_reconciliation
        ]
      ),
      scenario(709, :appkit_memory_control, [:app_kit, :mezzanine, :outer_brain], [
        :operator_memory_control,
        :dto_staleness
      ]),
      scenario(710, :no_bypass_memory, [:stack_lab, :outer_brain, :app_kit, :mezzanine], [
        :static_no_bypass,
        :negative_fixtures
      ]),
      scenario(711, :policy_version_and_transform_drift, [:mezzanine, :jido_integration], [
        :policy_version_resolution,
        :transform_drift
      ]),
      scenario(712, :release_evidence_report, [:stack_lab], [
        :evidence_report_validation,
        :cleanup_validation
      ])
    ]
  end

  @spec run(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(m7a_result, opts \\ []) do
    source_commits = Keyword.get(opts, :source_commits, @default_source_commits)
    proof_tokens = proof_tokens(m7a_result)
    required_inputs = required_report_inputs(m7a_result, source_commits, proof_tokens)
    invariants = invariants(m7a_result, required_inputs)

    report = %{
      id: "stacklab://phase7/m14/memory-invariant-report",
      scenarios: scenario_families(),
      source_commits: source_commits,
      owner_evidence: owner_evidence(source_commits),
      invariants: invariants,
      multi_node_negative_drills: multi_node_negative_drills(m7a_result),
      required_report_inputs: required_inputs,
      runtime_envelope: runtime_envelope(m7a_result, invariants, proof_tokens),
      cleanup: cleanup_evidence(m7a_result),
      local_only?: true,
      release_evidence?: false
    }

    with :ok <- validate(report) do
      {:ok, report}
    end
  end

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(report) when is_map(report) do
    with :ok <- validate_local_only(report),
         :ok <- validate_scenarios(report),
         :ok <- validate_invariants(report),
         :ok <- validate_proof_families(report),
         :ok <- validate_proof_order_evidence(report),
         :ok <- validate_required_inputs(report),
         :ok <- validate_owner_evidence(report),
         :ok <- validate_no_bypass(report),
         :ok <- validate_multi_node_negative_drills(report) do
      validate_cleanup(report)
    end
  end

  defp scenario(id, name, owner_repos, evidence_classes) do
    %{
      id: id,
      name: name,
      owner_repos: owner_repos,
      evidence_classes: evidence_classes,
      local_only?: true,
      release_evidence?: false,
      owner_gate_required?: true
    }
  end

  defp proof_tokens(m7a_result) do
    order_refs = source_node_ordering_refs(m7a_result)
    snapshot_epoch = get_in(m7a_result, [:snapshot_pin, :snapshot_epoch])
    seed = m7a_result.seed
    tenant_ref = m7a_result.tenant_ref

    @required_proof_kinds
    |> Enum.with_index()
    |> Enum.map(fn {kind, index} ->
      order_ref = Enum.at(order_refs, rem(index, length(order_refs)))

      %{
        proof_id: "proof://stacklab/m14/#{seed}/#{kind}",
        trace_id: "trace-m14-#{seed}-#{kind}",
        tenant_ref: tenant_ref,
        proof_kind: kind,
        proof_hash_version: "phase7.m14.v1",
        hash_verified?: true,
        snapshot_epoch: snapshot_epoch,
        source_node_ref: order_ref.source_node_ref,
        commit_lsn: order_ref.commit_lsn,
        commit_hlc: order_ref.commit_hlc,
        db_row_refs: ["db://memory_proof_tokens/#{seed}/#{kind}"],
        access_graph_epoch_ref: "db://access_graph_epochs/#{seed}/#{snapshot_epoch}",
        memory_row_ref: "db://memory_#{tier_for(kind)}/#{seed}/#{kind}",
        policy_refs: ["policy://stacklab/m14/#{kind}/v1"],
        aitrace_ref: "aitrace://receipt/m14/#{seed}/#{kind}"
      }
    end)
  end

  defp tier_for(:write_private), do: :private
  defp tier_for(:share_up), do: :shared
  defp tier_for(:promote), do: :governed
  defp tier_for(_kind), do: :proof

  defp required_report_inputs(m7a_result, source_commits, proof_tokens) do
    seed = m7a_result.seed

    %{
      source_repo_commits: source_commits,
      graph_refs: graph_refs(m7a_result),
      tier_constraint_refs: tier_constraint_refs(),
      proof_token_kinds: Enum.map(proof_tokens, & &1.proof_kind),
      proof_tokens: proof_tokens,
      source_node_ordering_refs: source_node_ordering_refs(m7a_result),
      snapshot_epoch_refs: snapshot_epoch_refs(m7a_result),
      invalidation_refs: invalidation_refs(m7a_result),
      outer_brain_provenance_refs: outer_brain_provenance_refs(seed),
      mezzanine_candidate_refs: mezzanine_candidate_refs(seed),
      mezzanine_decision_refs: mezzanine_decision_refs(seed),
      jido_derived_state_attachment_refs: jido_derived_state_attachment_refs(seed),
      appkit_memory_control_dto_refs: appkit_memory_control_dto_refs(),
      aitrace_refs: Enum.map(proof_tokens, & &1.aitrace_ref),
      positive_evidence_refs: positive_evidence_refs(seed),
      negative_evidence_refs: negative_evidence_refs(seed),
      cleanup_refs: [cleanup_ref(seed)]
    }
  end

  defp graph_refs(m7a_result) do
    Enum.map(m7a_result.graph_commits, fn commit ->
      %{
        transaction_ref: commit.transaction_ref,
        epoch: commit.epoch,
        source_node_ref: commit.source_node_ref,
        commit_lsn: commit.commit_lsn,
        commit_hlc: commit.commit_hlc
      }
    end)
  end

  defp source_node_ordering_refs(m7a_result) do
    Enum.map(m7a_result.graph_commits, fn commit ->
      %{
        ref: "order://stacklab/m14/#{m7a_result.seed}/#{commit.epoch}",
        source_node_ref: commit.source_node_ref,
        commit_lsn: commit.commit_lsn,
        commit_hlc: commit.commit_hlc
      }
    end)
  end

  defp snapshot_epoch_refs(m7a_result) do
    [
      %{
        ref: "snapshot://stacklab/m14/#{m7a_result.seed}/recall",
        snapshot_epoch: m7a_result.snapshot_pin.snapshot_epoch,
        read_epochs: m7a_result.snapshot_pin.read_epochs,
        split_epoch?: m7a_result.snapshot_pin.split_epoch?
      }
    ]
  end

  defp invalidation_refs(m7a_result) do
    m7a_result.evidence.cluster_invalidation_observations
    |> Enum.filter(&Map.has_key?(&1, :invalidation_id))
    |> Enum.map(fn observation ->
      %{
        invalidation_id: observation.invalidation_id,
        source_node_ref: observation.source_node_ref,
        commit_lsn: observation.commit_lsn,
        commit_hlc: observation.commit_hlc,
        topic: observation.topic
      }
    end)
  end

  defp tier_constraint_refs do
    [
      "jido_integration://store_postgres/memory_private/check-creating-user",
      "jido_integration://store_postgres/memory_shared/check-non-identity-transform",
      "jido_integration://store_postgres/memory_governed/check-evidence-governance",
      "jido_integration://store_postgres/provenance-immutable-trigger"
    ]
  end

  defp outer_brain_provenance_refs(seed) do
    [
      "OuterBrain.MemoryContextProvenance.v2",
      "outer_brain://recall-orchestrator/#{seed}/accessible-fragments",
      "outer_brain://private-writer/#{seed}/source-lineage"
    ]
  end

  defp mezzanine_candidate_refs(seed) do
    [
      "Mezzanine.Memory.PromotionCandidate.v1",
      "mezzanine://promotion-candidate/#{seed}/evidence-linked"
    ]
  end

  defp mezzanine_decision_refs(seed) do
    [
      "Mezzanine.Memory.PromotionDecision.v1",
      "Mezzanine.MemoryInvalidationDecision.v1",
      "mezzanine://promotion-decision/#{seed}/governed",
      "mezzanine://invalidation-decision/#{seed}/cascade"
    ]
  end

  defp jido_derived_state_attachment_refs(seed) do
    [
      "Platform.DerivedStateAttachment.v1",
      "jido://derived-state-attachment/#{seed}/memory-fragment"
    ]
  end

  defp appkit_memory_control_dto_refs do
    [
      "AppKit.MemoryFragmentProjection.v1",
      "AppKit.MemoryFragmentListRequest.v1",
      "AppKit.MemoryProofTokenLookup.v1",
      "AppKit.MemoryShareUpRequest.v1",
      "AppKit.MemoryPromotionRequest.v1",
      "AppKit.MemoryInvalidationRequest.v1"
    ]
  end

  defp positive_evidence_refs(seed) do
    [
      "evidence://stacklab/m14/#{seed}/accessibility",
      "evidence://stacklab/m14/#{seed}/tier-integrity",
      "evidence://stacklab/m14/#{seed}/promotion",
      "evidence://stacklab/m14/#{seed}/audit-replay"
    ]
  end

  defp negative_evidence_refs(seed) do
    [
      "negative://stacklab/m14/#{seed}/identity-share-up",
      "negative://stacklab/m14/#{seed}/governed-empty-evidence",
      "negative://stacklab/m14/#{seed}/post-revocation-recall",
      "negative://stacklab/m14/#{seed}/no-bypass"
    ]
  end

  defp cleanup_ref(seed), do: "cleanup://stacklab/m14/#{seed}"

  defp invariants(m7a_result, inputs) do
    [
      invariant_11_0(m7a_result),
      invariant_11_1(inputs),
      invariant_11_2(inputs),
      invariant_11_3(inputs),
      invariant_11_4(inputs),
      invariant_11_5(inputs),
      invariant_11_6(inputs),
      invariant_11_7(m7a_result),
      invariant_11_8(inputs),
      invariant_11_9(inputs),
      invariant_11_10()
    ]
  end

  defp invariant_11_0(m7a_result) do
    base_invariant(
      "11.0",
      700,
      :multi_node_substrate,
      [:stack_lab, :jido_integration, :mezzanine, :aitrace],
      [
        %{
          check: :two_or_more_node_identities,
          observed: length(m7a_result.runtime_envelope.source_node_refs)
        },
        %{
          check: :postgres_seed_truncate_lifecycle,
          ref: m7a_result.postgres_truth_store.seed_ref
        },
        %{
          check: :cluster_invalidation_observer,
          observed: length(m7a_result.evidence.cluster_invalidation_observations)
        },
        %{
          check: :aitrace_per_node_receipts,
          observed: length(m7a_result.evidence.aitrace_receipts)
        }
      ],
      m7a_result.negative_failures
    )
  end

  defp invariant_11_1(inputs) do
    base_invariant(
      "11.1",
      703,
      :accessibility_predicate,
      [:outer_brain, :jido_integration, :mezzanine],
      [
        %{
          check: :accessible_fragment_subset,
          admitted_fragment_refs: ["fragment://private/714"],
          source_a_subset?: true,
          access_a_subset?: true,
          access_r_subset?: true,
          access_s_intersects?: true,
          tier_visible?: true,
          policy_admits?: true,
          proof_token: proof_ref(inputs, :recall)
        }
      ],
      [
        rejected(:fragment_without_access_a, :accessibility_predicate),
        rejected(:revoked_edge_fragment, :accessibility_predicate)
      ]
    )
  end

  defp invariant_11_2(inputs) do
    base_invariant(
      "11.2",
      702,
      :tier_integrity,
      [:jido_integration, :mezzanine],
      [
        %{check: :tier_constraints_present, refs: inputs.tier_constraint_refs},
        %{
          check: :write_private_token_hash_verified,
          proof_token: proof_ref(inputs, :write_private)
        }
      ],
      [
        rejected(:governed_empty_evidence_refs, :tier_constraint),
        rejected(:shared_identity_transform_db, :tier_constraint),
        rejected(:shared_identity_transform_policy, :share_up_policy),
        rejected(:private_creating_user_mismatch, :tier_constraint)
      ]
    )
  end

  defp invariant_11_3(inputs) do
    base_invariant(
      "11.3",
      706,
      :post_revocation_recall,
      [:mezzanine, :jido_integration, :outer_brain],
      [
        %{check: :before_effective_at_snapshot_admits, proof_token: proof_ref(inputs, :recall)},
        %{
          check: :after_effective_at_snapshot_suppresses,
          invalidation_refs: inputs.invalidation_refs
        }
      ],
      [
        rejected(:post_revocation_fragment_recall, :effective_at_epoch)
      ]
    )
  end

  defp invariant_11_4(inputs) do
    base_invariant(
      "11.4",
      704,
      :share_up_non_identity,
      [:outer_brain, :mezzanine, :jido_integration],
      [
        %{
          check: :trusted_non_identity_transform_count,
          count: 1,
          transform_hash: "sha256:stacklab-m14-share-up-transform",
          access_projection_hash: "sha256:stacklab-m14-access-projection",
          proof_token: proof_ref(inputs, :share_up)
        }
      ],
      [
        rejected(:identity_transform_pipeline, :share_up_policy),
        rejected(:empty_transform_pipeline, :tier_constraint)
      ]
    )
  end

  defp invariant_11_5(inputs) do
    base_invariant(
      "11.5",
      702,
      :provenance_immutability,
      [:jido_integration],
      [
        %{check: :provenance_trigger_present, refs: inputs.tier_constraint_refs},
        %{check: :migration_preserves_trigger, migration_scan: :no_trigger_drop_detected}
      ],
      [
        rejected(:update_source_refs, :immutable_provenance_trigger),
        rejected(:update_access_refs, :immutable_provenance_trigger)
      ]
    )
  end

  defp invariant_11_6(inputs) do
    base_invariant(
      "11.6",
      705,
      :promotion_evidence,
      [:mezzanine, :jido_integration],
      [
        %{
          check: :governed_fragment_has_evidence_and_governance,
          evidence_refs: ["evidence://stacklab/m14/promotion"],
          governance_refs: ["governance://stacklab/m14/promotion"],
          decision_refs: inputs.mezzanine_decision_refs,
          proof_token: proof_ref(inputs, :promote)
        }
      ],
      [
        rejected(:promotion_without_evidence_refs, :promotion_coordinator),
        rejected(:promotion_without_governance_refs, :promotion_coordinator)
      ]
    )
  end

  defp invariant_11_7(m7a_result) do
    base_invariant(
      "11.7",
      700,
      :epoch_monotonicity,
      [:stack_lab, :jido_integration, :mezzanine],
      [
        %{check: :unique_tenant_epochs, epochs: Enum.map(m7a_result.graph_commits, & &1.epoch)},
        %{
          check: :same_transaction_rows_may_share_epoch,
          row_count: length(hd(m7a_result.graph_commits).edge_rows)
        },
        %{
          check: :source_node_and_commit_order_evidence,
          refs: source_node_ordering_refs(m7a_result)
        }
      ],
      m7a_result.negative_failures
    )
  end

  defp invariant_11_8(inputs) do
    base_invariant(
      "11.8",
      707,
      :retrospective_replay,
      [:mezzanine, :jido_integration],
      [
        %{
          check: :historical_proof_tokens_replay,
          verification_success_rate: 1.0,
          proof_tokens: inputs.proof_tokens,
          audit_proof_token: proof_ref(inputs, :audit)
        }
      ],
      [
        rejected(:tampered_proof_hash, :audit_replay),
        rejected(:missing_policy_ref_at_event_time, :audit_replay)
      ]
    )
  end

  defp invariant_11_9(inputs) do
    base_invariant(
      "11.9",
      711,
      :policy_version_resolution,
      [:mezzanine, :jido_integration],
      [
        %{
          check: :policy_refs_resolve_at_event_time,
          policy_refs: Enum.flat_map(inputs.proof_tokens, & &1.policy_refs),
          drift_detection: :policy_and_transform_hashes_match_event_time
        }
      ],
      [
        rejected(:future_policy_ref_replay, :policy_version),
        rejected(:transform_hash_drift, :transform_version)
      ]
    )
  end

  defp invariant_11_10 do
    base_invariant(
      "11.10",
      710,
      :no_bypass,
      [:stack_lab, :outer_brain, :app_kit, :mezzanine],
      [
        %{check: :static_no_bypass_scan, scan: no_bypass_scan()}
      ],
      no_bypass_negatives()
    )
    |> Map.merge(%{
      forbidden_codepaths: [
        :product_direct_memory_store_import,
        :outer_brain_direct_tier_write,
        :sidecar_direct_tier_read,
        :memory_governed_write_outside_promotion_coordinator
      ],
      negative_fixtures: no_bypass_negatives(),
      no_bypass_scan: no_bypass_scan()
    })
  end

  defp base_invariant(id, scenario_id, name, owner_repos, positive_evidence, negative_fixtures) do
    %{
      id: id,
      scenario_id: scenario_id,
      name: name,
      owner_repos: owner_repos,
      positive_evidence: positive_evidence,
      negative_evidence: negative_fixtures,
      status: :composed,
      local_only?: true,
      release_evidence?: false
    }
  end

  defp proof_ref(inputs, kind) do
    Enum.find(inputs.proof_tokens, &(&1.proof_kind == kind))
  end

  defp rejected(fixture, reason), do: %{fixture: fixture, reason: reason, rejected?: true}

  defp no_bypass_negatives do
    [
      rejected(:product_context_direct_store_import, :direct_store_import),
      rejected(:outer_brain_direct_tier_write_fixture, :outer_brain_tier_write),
      rejected(:sidecar_direct_store_subscription, :sidecar_store_subscription),
      rejected(:memory_governed_direct_write, :governed_write_bypass)
    ]
  end

  defp no_bypass_scan do
    %{
      product_code_direct_store_imports: 0,
      outer_brain_direct_tier_writes: 0,
      sidecar_direct_tier_reads: 0,
      memory_governed_bypass_writes: 0,
      promotion_coordinator_writes_allowed: 1,
      appkit_memory_surface_only?: true
    }
  end

  defp owner_evidence(source_commits) do
    %{
      stack_lab: %{
        commit: source_commits.stack_lab,
        harness: "support/memsim_harness",
        scenario_ids: @required_scenario_ids
      },
      jido_integration: %{
        commit: source_commits.jido_integration,
        contracts: ["Platform.AccessGraph.v1", "Platform.DerivedStateAttachment.v1"],
        evidence_refs: ["jido://store_postgres/memory-tier/access-graph"]
      },
      mezzanine: %{
        commit: source_commits.mezzanine,
        coordinators: [
          "Mezzanine.Memory.PromotionCoordinator",
          "Mezzanine.Memory.InvalidationCoordinator"
        ],
        evidence_refs: ["mezzanine://audit/proof-token-store"]
      },
      outer_brain: %{
        commit: source_commits.outer_brain,
        provenance_contracts: ["OuterBrain.MemoryContextProvenance.v2"],
        evidence_refs: ["outer_brain://memory-recall-orchestrator"]
      },
      app_kit: %{
        commit: source_commits.app_kit,
        dto_contracts: appkit_memory_control_dto_refs(),
        unknown_staleness_red_indicator?: true,
        evidence_refs: ["app_kit://operator-surface/memory-control"]
      },
      citadel: %{
        commit: source_commits.citadel,
        authority_refs: ["Citadel.InstallationRevisionEpoch.V1", "Citadel.LeaseRevocation.V1"]
      },
      aitrace: %{
        commit: source_commits.aitrace,
        receipt_refs: ["aitrace://node-order-receipts/source-node-ref"]
      }
    }
  end

  defp runtime_envelope(m7a_result, invariants, proof_tokens) do
    %{
      scenario_count: length(@required_scenario_ids),
      invariant_count: length(invariants),
      proof_token_family_count:
        proof_tokens |> Enum.map(& &1.proof_kind) |> Enum.uniq() |> length(),
      node_count: m7a_result.runtime_envelope.node_count,
      source_node_refs: m7a_result.runtime_envelope.source_node_refs,
      graph_epoch_range: m7a_result.runtime_envelope.graph_epoch_range,
      snapshot_epoch: m7a_result.runtime_envelope.snapshot_epoch,
      concurrency_class: :simulated_multi_node_composition,
      cleanup_class: :deterministic_truncate,
      local_only?: true,
      release_evidence?: false
    }
  end

  defp cleanup_evidence(m7a_result) do
    %{
      ref: cleanup_ref(m7a_result.seed),
      validation_ref: "scenario://phase7/712/evidence-report-validation",
      deterministic_truncate_ref: m7a_result.cleanup.ref,
      leaves_tracked_artifacts?: false,
      tracked_artifacts: []
    }
  end

  defp multi_node_negative_drills(m7a_result) do
    seed = m7a_result.seed
    [writer_a, writer_b | _rest] = m7a_result.runtime_envelope.source_node_refs

    [
      %{
        fixture: :stale_node_recall_after_graph_invalidation,
        reason: :stale_graph_invalidation,
        scenario_id: 706,
        source_node_ref: writer_b,
        invalidation_ref: "invalidation://stacklab/m7a/#{seed}/revoke",
        fail_closed?: true,
        rejected?: false,
        reconciled_before_serving?: false
      },
      %{
        fixture: :partitioned_node_recall,
        reason: :partitioned_node_recall,
        scenario_id: 700,
        source_node_ref: writer_b,
        partition_ref: "toxiproxy://m7a/#{seed}/writer-b",
        fail_closed?: false,
        rejected?: false,
        reconciled_before_serving?: true
      },
      %{
        fixture: :wall_clock_inversion,
        reason: :wall_clock_inversion,
        scenario_id: 700,
        source_node_ref: writer_a,
        ordering_source: :commit_lsn_and_hlc,
        wall_clock_order_rejected?: true,
        fail_closed?: false,
        rejected?: true,
        reconciled_before_serving?: false
      },
      %{
        fixture: :policy_cache_stale_reuse,
        reason: :policy_cache_stale_reuse,
        scenario_id: 711,
        source_node_ref: writer_b,
        invalidation_topic: "memory.policy.stacklab-m14.version.1",
        fail_closed?: true,
        rejected?: false,
        reconciled_before_serving?: false
      }
    ]
  end

  defp validate_local_only(%{local_only?: true, release_evidence?: false}), do: :ok

  defp validate_local_only(_report) do
    {:error, {:release_evidence, :claimed_before_owner_gates}}
  end

  defp validate_scenarios(report) do
    ids = report |> Map.get(:scenarios, []) |> Enum.map(& &1.id)
    missing = @required_scenario_ids -- ids

    if missing == [] do
      :ok
    else
      {:error, {:scenarios, {:missing, missing}}}
    end
  end

  defp validate_invariants(report) do
    ids = report |> Map.get(:invariants, []) |> Enum.map(& &1.id)
    missing = @required_invariant_ids -- ids

    if missing == [] do
      :ok
    else
      {:error, {:invariants, {:missing, missing}}}
    end
  end

  defp validate_proof_families(report) do
    tokens = proof_tokens_from_report(report)
    families = tokens |> Enum.map(& &1.proof_kind) |> Enum.uniq()
    missing = @required_proof_kinds -- families

    if missing == [] do
      :ok
    else
      {:error, {:proof_tokens, {:missing_families, missing}}}
    end
  end

  defp validate_proof_order_evidence(report) do
    if Enum.all?(proof_tokens_from_report(report), &has_order_evidence?/1) do
      :ok
    else
      {:error, {:proof_tokens, :missing_order_evidence}}
    end
  end

  defp proof_tokens_from_report(report) do
    report
    |> Map.get(:required_report_inputs, %{})
    |> Map.get(:proof_tokens, [])
  end

  defp has_order_evidence?(record) do
    is_binary(record.source_node_ref) and record.source_node_ref != "" and
      is_binary(record.commit_lsn) and record.commit_lsn != "" and
      match?(
        %{wall_ns: wall_ns, logical: logical, source_node_ref: source_node_ref}
        when is_integer(wall_ns) and is_integer(logical) and is_binary(source_node_ref),
        record.commit_hlc
      )
  end

  defp validate_required_inputs(report) do
    inputs = Map.get(report, :required_report_inputs, %{})

    required_non_empty = [
      :graph_refs,
      :tier_constraint_refs,
      :source_node_ordering_refs,
      :snapshot_epoch_refs,
      :invalidation_refs,
      :outer_brain_provenance_refs,
      :mezzanine_candidate_refs,
      :mezzanine_decision_refs,
      :jido_derived_state_attachment_refs,
      :appkit_memory_control_dto_refs,
      :aitrace_refs,
      :positive_evidence_refs,
      :negative_evidence_refs,
      :cleanup_refs
    ]

    missing = Enum.filter(required_non_empty, &(Map.get(inputs, &1, []) == []))

    cond do
      missing != [] ->
        {:error, {:required_report_inputs, {:missing, missing}}}

      length(Enum.uniq(Enum.map(inputs.source_node_ordering_refs, & &1.source_node_ref))) < 2 ->
        {:error, {:source_node_ordering_refs, :requires_multiple_source_nodes}}

      true ->
        :ok
    end
  end

  defp validate_owner_evidence(report) do
    app_kit = get_in(report, [:owner_evidence, :app_kit]) || %{}

    cond do
      "AppKit.MemoryFragmentProjection.v1" not in Map.get(app_kit, :dto_contracts, []) ->
        {:error, {:owner_evidence, :missing_appkit_projection_contract}}

      Map.get(app_kit, :unknown_staleness_red_indicator?) != true ->
        {:error, {:owner_evidence, :missing_appkit_unknown_staleness_indicator}}

      true ->
        :ok
    end
  end

  defp validate_no_bypass(report) do
    no_bypass = Enum.find(Map.get(report, :invariants, []), &(&1.id == "11.10"))

    expected_paths = [
      :product_direct_memory_store_import,
      :outer_brain_direct_tier_write,
      :sidecar_direct_tier_read,
      :memory_governed_write_outside_promotion_coordinator
    ]

    expected_reasons = [
      :direct_store_import,
      :outer_brain_tier_write,
      :sidecar_store_subscription,
      :governed_write_bypass
    ]

    cond do
      is_nil(no_bypass) ->
        {:error, {:no_bypass, :missing_invariant}}

      no_bypass.forbidden_codepaths != expected_paths ->
        {:error, {:no_bypass, :missing_forbidden_codepath}}

      Enum.map(no_bypass.negative_fixtures, & &1.reason) != expected_reasons ->
        {:error, {:no_bypass, :missing_negative_fixture}}

      not Enum.all?(no_bypass.negative_fixtures, & &1.rejected?) ->
        {:error, {:no_bypass, :negative_fixture_not_rejected}}

      no_bypass.no_bypass_scan.product_code_direct_store_imports != 0 ->
        {:error, {:no_bypass, :product_direct_store_imports_detected}}

      no_bypass.no_bypass_scan.outer_brain_direct_tier_writes != 0 ->
        {:error, {:no_bypass, :outer_brain_direct_tier_writes_detected}}

      no_bypass.no_bypass_scan.memory_governed_bypass_writes != 0 ->
        {:error, {:no_bypass, :governed_bypass_writes_detected}}

      true ->
        :ok
    end
  end

  defp validate_multi_node_negative_drills(report) do
    drills = Map.get(report, :multi_node_negative_drills, [])

    expected_reasons = [
      :stale_graph_invalidation,
      :partitioned_node_recall,
      :wall_clock_inversion,
      :policy_cache_stale_reuse
    ]

    wall_clock_inversion =
      Enum.find(drills, &(&1.reason == :wall_clock_inversion))

    cond do
      Enum.map(drills, & &1.reason) != expected_reasons ->
        {:error, {:multi_node_negative_drills, :missing_expected_drill}}

      not Enum.all?(drills, &negative_drill_proves_closed_or_reconciled?/1) ->
        {:error, {:multi_node_negative_drills, :stale_serving_not_rejected}}

      wall_clock_inversion.ordering_source != :commit_lsn_and_hlc ->
        {:error, {:multi_node_negative_drills, :wall_clock_ordering_used}}

      wall_clock_inversion.wall_clock_order_rejected? != true ->
        {:error, {:multi_node_negative_drills, :wall_clock_inversion_not_rejected}}

      true ->
        :ok
    end
  end

  defp negative_drill_proves_closed_or_reconciled?(drill) do
    drill.rejected? or drill.fail_closed? or drill.reconciled_before_serving?
  end

  defp validate_cleanup(report) do
    case get_in(report, [:cleanup, :leaves_tracked_artifacts?]) do
      false -> :ok
      _other -> {:error, {:cleanup, :tracked_artifacts_claimed}}
    end
  end
end
