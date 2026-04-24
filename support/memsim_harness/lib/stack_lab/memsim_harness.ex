defmodule StackLab.MemsimHarness do
  @moduledoc """
  Deterministic memory-substrate simulations for StackLab Phase 7.

  The harness models the evidence shape required by M7A without claiming that
  local simulations are release evidence. Owner-repo tests remain the authority
  for access graph, memory tiers, proof-token storage, AITrace export, and
  cluster invalidation publishers.
  """

  alias StackLab.LabCore
  alias StackLab.MemsimHarness.{InvariantReport, Phase7EvidenceReport}

  @scenario_id 700
  @scenario_name :multi_node_epoch_monotonicity_and_ordering
  @default_tenant_ref "tenant://stacklab/memsim"
  @base_wall_ns 1_775_000_000_000_000_000

  @spec scenario() :: map()
  def scenario do
    %{
      id: @scenario_id,
      name: @scenario_name,
      compose: LabCore.compose_file(:multi),
      runbook: LabCore.runbook(:up_multi),
      toxiproxy_config: LabCore.toxiproxy_config(),
      concurrency_class: :simulated_multi_node,
      local_only?: true,
      release_evidence?: false,
      cleanup_class: :deterministic_truncate,
      owner_gate_required?: true
    }
  end

  @spec memory_invariant_scenarios() :: [map()]
  def memory_invariant_scenarios, do: InvariantReport.scenario_families()

  @spec run_memory_invariants(keyword()) :: {:ok, map()} | {:error, term()}
  def run_memory_invariants(opts \\ []) do
    with {:ok, m7a_result} <- run_epoch_monotonicity(opts) do
      InvariantReport.run(m7a_result, opts)
    end
  end

  @spec validate_memory_invariant_report(map()) :: :ok | {:error, term()}
  def validate_memory_invariant_report(report), do: InvariantReport.validate(report)

  @spec phase7_evidence_report(keyword()) :: {:ok, map()} | {:error, term()}
  def phase7_evidence_report(opts \\ []) do
    with {:ok, invariant_report} <- run_memory_invariants(opts) do
      Phase7EvidenceReport.build(invariant_report)
    end
  end

  @spec validate_phase7_evidence_report(map()) :: :ok | {:error, term()}
  def validate_phase7_evidence_report(report), do: Phase7EvidenceReport.validate(report)

  @spec seed!(keyword()) :: map()
  def seed!(opts \\ []) do
    tenant_ref = Keyword.get(opts, :tenant_ref, @default_tenant_ref)
    seed = Keyword.get(opts, :seed, @scenario_id)
    node_identities = node_identities(seed)
    [writer_a, writer_b | _] = memory_writers(node_identities)

    stores = %{
      access_graph: [
        graph_edge(tenant_ref, writer_a, seed, 1, :user_agent),
        graph_edge(tenant_ref, writer_b, seed, 1, :agent_scope)
      ],
      tiers: %{
        private: [tier_fragment(:private, tenant_ref, writer_a, seed)],
        shared: [tier_fragment(:shared, tenant_ref, writer_b, seed)],
        governed: [tier_fragment(:governed, tenant_ref, writer_a, seed)]
      },
      policies: [
        policy_record(tenant_ref, seed, :read),
        policy_record(tenant_ref, seed, :invalidate)
      ],
      proof_tokens: [seed_proof_token(tenant_ref, writer_a, seed)],
      invalidations: [seed_invalidation(tenant_ref, writer_b, seed)]
    }

    %{
      scenario: scenario(),
      tenant_ref: tenant_ref,
      seed: seed,
      node_identities: node_identities,
      postgres_truth_store: postgres_truth_store(seed, stores),
      stores: stores,
      observations: empty_observations(),
      partition_hooks: partition_hooks(seed),
      cleanup: cleanup_plan(seed)
    }
  end

  @spec truncate!(map()) :: map()
  def truncate!(fixture) when is_map(fixture) do
    fixture
    |> put_in([:postgres_truth_store, :seeded?], false)
    |> put_in([:postgres_truth_store, :tables], empty_tables())
    |> Map.put(:stores, empty_stores())
    |> Map.put(:observations, empty_observations())
  end

  @spec run_epoch_monotonicity(keyword()) :: {:ok, map()}
  def run_epoch_monotonicity(opts \\ []) do
    fixture = seed!(opts)
    [writer_a, writer_b | _] = memory_writers(fixture.node_identities)
    tenant_ref = fixture.tenant_ref
    seed = fixture.seed

    graph_commits = [
      graph_commit(tenant_ref, writer_a, seed, 1, :activate_user_agent),
      graph_commit(tenant_ref, writer_b, seed, 2, :activate_agent_scope),
      graph_commit(tenant_ref, writer_a, seed, 3, :revoke_agent_scope)
    ]

    evidence = evidence_for(tenant_ref, graph_commits, seed)

    result =
      fixture
      |> Map.merge(%{
        graph_commits: graph_commits,
        evidence: evidence,
        observations:
          Map.take(evidence, [
            :aitrace_receipts,
            :cluster_invalidation_observations,
            :db_row_refs,
            :proof_tokens
          ]),
        snapshot_pin: snapshot_pin(tenant_ref, writer_b, seed),
        negative_failures: negative_failures(),
        runtime_envelope: runtime_envelope(fixture, graph_commits)
      })

    {:ok, result}
  end

  @spec partition_hooks(map() | integer()) :: [map()]
  def partition_hooks(%{partition_hooks: hooks}), do: hooks

  def partition_hooks(seed) when is_integer(seed) do
    [
      %{
        name: :writer_b_partition,
        kind: :toxiproxy,
        toxiproxy_config: LabCore.toxiproxy_config(),
        target_node_shortname: "m7a-writer-b",
        local_only?: true,
        release_evidence?: false,
        owner_gate_required?: true,
        deterministic_ref: "toxiproxy://m7a/#{seed}/writer-b"
      }
    ]
  end

  @spec aitrace_receipts_by_node(map()) :: %{optional(String.t()) => [map()]}
  def aitrace_receipts_by_node(%{evidence: %{aitrace_receipts: receipts}}) do
    Enum.group_by(receipts, & &1.source_node_ref)
  end

  @spec validate_evidence(map()) :: :ok | {:error, term()}
  def validate_evidence(result) when is_map(result) do
    with :ok <- validate_scenario(result),
         :ok <- validate_graph_commits(result.graph_commits),
         :ok <- validate_proof_tokens(result.evidence.proof_tokens),
         :ok <- validate_aitrace_receipts(result),
         :ok <- validate_db_row_refs(result.evidence.db_row_refs),
         :ok <- validate_cluster_invalidations(result.evidence.cluster_invalidation_observations),
         :ok <- validate_snapshot_pin(result.snapshot_pin),
         :ok <- validate_negative_failures(result.negative_failures),
         :ok <- validate_partition_hooks(result.partition_hooks) do
      validate_cleanup(result.cleanup)
    end
  end

  defp node_identities(seed) do
    [
      node_identity("m7a-writer-a", "memsim-a.local", :memory_writer, 0, seed),
      node_identity("m7a-writer-b", "memsim-b.local", :memory_writer, 1, seed),
      node_identity("m7a-probe", "memsim-probe.local", :stacklab_probe, 0, seed)
    ]
  end

  defp node_identity(shortname, host, role, slot, seed) do
    persistent_uuid = uuid_for("#{seed}:#{shortname}:persistent")
    instance_id = uuid_for("#{seed}:#{shortname}:instance")

    %{
      node_ref: "node://#{shortname}@#{host}/#{persistent_uuid}",
      shortname: shortname,
      host: host,
      node_role: role,
      instance_slot: slot,
      persistent_identity_path: "/var/lib/memsim/node_id/#{shortname}.id",
      node_instance_id: instance_id,
      boot_generation: seed + slot + 1,
      deployment_ref: "deployment://stacklab/m7a",
      cluster_ref: "cluster://stacklab/memsim",
      release_manifest_ref: "phase7-release-manifest"
    }
  end

  defp memory_writers(nodes), do: Enum.filter(nodes, &(&1.node_role == :memory_writer))

  defp graph_edge(tenant_ref, node, seed, epoch, family) do
    %{
      row_ref: "db://access_graph_edges/#{seed}/#{family}/#{epoch}",
      tenant_ref: tenant_ref,
      edge_family: family,
      epoch_start: epoch,
      epoch_end: nil,
      source_node_ref: node.node_ref
    }
  end

  defp tier_fragment(tier, tenant_ref, node, seed) do
    %{
      row_ref: "db://memory_#{tier}/#{seed}",
      fragment_ref: "fragment://#{tier}/#{seed}",
      tier: tier,
      tenant_ref: tenant_ref,
      t_epoch: 1,
      source_node_ref: node.node_ref,
      evidence_refs: ["evidence://stacklab/m7a/#{seed}"],
      governance_refs: ["governance://stacklab/m7a/#{seed}"]
    }
  end

  defp policy_record(tenant_ref, seed, kind) do
    %{
      row_ref: "db://memory_policies/#{seed}/#{kind}",
      tenant_ref: tenant_ref,
      policy_ref: "policy://stacklab/m7a/#{kind}",
      kind: kind,
      version: 1
    }
  end

  defp seed_proof_token(tenant_ref, node, seed) do
    %{
      proof_id: "proof://stacklab/m7a/#{seed}/seed",
      trace_id: "trace-m7a-#{seed}-seed",
      tenant_ref: tenant_ref,
      proof_kind: :write_private,
      proof_hash_version: "m7a.v1",
      source_node_ref: node.node_ref,
      commit_lsn: lsn(seed, 0),
      commit_hlc: hlc(node, seed, 0)
    }
  end

  defp seed_invalidation(tenant_ref, node, seed) do
    %{
      invalidation_id: "invalidation://stacklab/m7a/#{seed}/seed",
      tenant_ref: tenant_ref,
      fragment_ref: "fragment://private/#{seed}",
      effective_at_epoch: 3,
      source_node_ref: node.node_ref,
      commit_lsn: lsn(seed, 3),
      commit_hlc: hlc(node, seed, 3)
    }
  end

  defp postgres_truth_store(seed, stores) do
    %{
      kind: :postgres_truth_store,
      lifecycle: :deterministic_seed_truncate,
      seeded?: true,
      seed_ref: "postgres://stacklab/memsim/#{seed}",
      tables: %{
        access_graph_edges: stores.access_graph,
        memory_private: stores.tiers.private,
        memory_shared: stores.tiers.shared,
        memory_governed: stores.tiers.governed,
        memory_policies: stores.policies,
        memory_proof_tokens: stores.proof_tokens,
        memory_invalidations: stores.invalidations
      },
      truncate_order: [
        :memory_invalidations,
        :memory_proof_tokens,
        :memory_governed,
        :memory_shared,
        :memory_private,
        :memory_policies,
        :access_graph_edges
      ]
    }
  end

  defp graph_commit(tenant_ref, node, seed, epoch, operation) do
    commit_lsn = lsn(seed, epoch)
    commit_hlc = hlc(node, seed, epoch)

    %{
      transaction_ref: "tx://access_graph/#{seed}/#{epoch}",
      tenant_ref: tenant_ref,
      operation: operation,
      concurrency_group: "simulated-concurrent-#{seed}",
      epoch: epoch,
      source_node_ref: node.node_ref,
      commit_lsn: commit_lsn,
      commit_hlc: commit_hlc,
      edge_rows: edge_rows(tenant_ref, node, seed, epoch, operation),
      db_row_refs: [
        "db://access_graph_epochs/#{seed}/#{epoch}",
        "db://access_graph_edges/#{seed}/#{epoch}/0"
      ]
    }
  end

  defp edge_rows(tenant_ref, node, seed, 1, operation) do
    [
      graph_edge_row(tenant_ref, node, seed, 1, operation, 0),
      graph_edge_row(tenant_ref, node, seed, 1, operation, 1)
    ]
  end

  defp edge_rows(tenant_ref, node, seed, epoch, operation) do
    [graph_edge_row(tenant_ref, node, seed, epoch, operation, 0)]
  end

  defp graph_edge_row(tenant_ref, node, seed, epoch, operation, offset) do
    %{
      row_ref: "db://access_graph_edges/#{seed}/#{epoch}/#{offset}",
      tenant_ref: tenant_ref,
      operation: operation,
      epoch_start: epoch,
      epoch_end: if(operation == :revoke_agent_scope, do: epoch, else: nil),
      source_node_ref: node.node_ref
    }
  end

  defp evidence_for(tenant_ref, graph_commits, seed) do
    %{
      proof_tokens: Enum.map(graph_commits, &proof_token_for(&1, seed)),
      aitrace_receipts: Enum.map(graph_commits, &aitrace_receipt_for(&1, seed)),
      db_row_refs: graph_commits |> Enum.flat_map(& &1.db_row_refs) |> Enum.uniq(),
      cluster_invalidation_observations:
        Enum.flat_map(graph_commits, &cluster_invalidation_observations(tenant_ref, &1, seed))
    }
  end

  defp proof_token_for(commit, seed) do
    %{
      proof_id: "proof://stacklab/m7a/#{seed}/#{commit.epoch}",
      trace_id: trace_id(seed, commit.epoch),
      tenant_ref: commit.tenant_ref,
      proof_kind: proof_kind(commit.operation),
      proof_hash_version: "m7a.v1",
      snapshot_epoch: if(commit.epoch == 3, do: 2, else: commit.epoch),
      source_node_ref: commit.source_node_ref,
      commit_lsn: commit.commit_lsn,
      commit_hlc: commit.commit_hlc,
      db_row_refs: commit.db_row_refs
    }
  end

  defp proof_kind(:revoke_agent_scope), do: :invalidate
  defp proof_kind(_operation), do: :audit

  defp aitrace_receipt_for(commit, seed) do
    %{
      receipt_ref: "aitrace://receipt/#{seed}/#{commit.epoch}",
      trace_id: trace_id(seed, commit.epoch),
      source_node_ref: commit.source_node_ref,
      node_order_evidence: %{
        trace_id: trace_id(seed, commit.epoch),
        source_node_ref: commit.source_node_ref,
        commit_lsn: commit.commit_lsn,
        commit_hlc: commit.commit_hlc
      },
      spans: [
        %{
          span_id: "span-#{seed}-#{commit.epoch}-graph",
          trace_id: trace_id(seed, commit.epoch),
          name: Atom.to_string(commit.operation),
          source_node_ref: commit.source_node_ref,
          commit_lsn: commit.commit_lsn,
          commit_hlc: commit.commit_hlc
        }
      ]
    }
  end

  defp cluster_invalidation_observations(tenant_ref, commit, seed) do
    tenant_hash = hash_segment(tenant_ref)

    graph_observation = %{
      topic: "memory.graph.#{tenant_hash}.epoch.#{commit.epoch}",
      subscriber_node_ref: "node://m7a-probe@memsim-probe.local/#{uuid_for("#{seed}:probe")}",
      source_node_ref: commit.source_node_ref,
      commit_lsn: commit.commit_lsn,
      commit_hlc: commit.commit_hlc,
      observed?: true
    }

    if commit.operation == :revoke_agent_scope do
      [
        graph_observation,
        %{
          topic: "memory.invalidation.#{tenant_hash}.#{hash_segment("invalidation:#{seed}")}",
          invalidation_id: "invalidation://stacklab/m7a/#{seed}/revoke",
          source_node_ref: commit.source_node_ref,
          commit_lsn: commit.commit_lsn,
          commit_hlc: commit.commit_hlc,
          observed?: true
        }
      ]
    else
      [graph_observation]
    end
  end

  defp snapshot_pin(tenant_ref, node, seed) do
    snapshot_epoch = 2

    %{
      tenant_ref: tenant_ref,
      snapshot_epoch: snapshot_epoch,
      recall_trace_id: "trace-m7a-#{seed}-recall",
      read_epochs: %{
        access_graph: snapshot_epoch,
        tier_private: snapshot_epoch,
        tier_shared: snapshot_epoch,
        tier_governed: snapshot_epoch,
        policy_resolution: snapshot_epoch,
        proof_token: snapshot_epoch
      },
      concurrent_revocation: %{
        epoch: 3,
        source_node_ref: node.node_ref,
        commit_lsn: lsn(seed, 3),
        commit_hlc: hlc(node, seed, 3)
      },
      split_epoch?: false,
      admitted_fragment_refs: ["fragment://private/#{seed}"],
      invalidation_effective_at_epoch: 3
    }
  end

  defp negative_failures do
    [
      %{fixture: :duplicate_epoch_fixture, reason: :duplicate_epoch, rejected?: true},
      %{fixture: :missing_node_ref_fixture, reason: :missing_source_node_ref, rejected?: true},
      %{fixture: :reused_epoch_fixture, reason: :reused_epoch, rejected?: true}
    ]
  end

  defp runtime_envelope(fixture, graph_commits) do
    %{
      tenant_count: 1,
      user_count: 1,
      agent_count: 1,
      resource_count: 1,
      scope_count: 1,
      fragment_count_by_tier: %{private: 1, shared: 1, governed: 1},
      policy_versions: [1],
      graph_epoch_range: {1, 3},
      node_count: length(fixture.node_identities),
      node_roles: fixture.node_identities |> Enum.map(& &1.node_role) |> Enum.uniq(),
      source_node_refs: graph_commits |> Enum.map(& &1.source_node_ref) |> Enum.uniq(),
      commit_lsn_range: {hd(graph_commits).commit_lsn, List.last(graph_commits).commit_lsn},
      commit_hlc_range: {hd(graph_commits).commit_hlc, List.last(graph_commits).commit_hlc},
      snapshot_epoch: 2,
      invalidation_fanout: :cluster_invalidation_topic,
      reconciliation_mode: :durable_row_replay,
      concurrency_class: :simulated_multi_node,
      cleanup_class: :deterministic_truncate,
      local_only?: true,
      release_evidence?: false
    }
  end

  defp validate_scenario(%{scenario: %{id: @scenario_id, name: @scenario_name}}), do: :ok
  defp validate_scenario(_result), do: {:error, {:scenario, :not_700}}

  defp validate_graph_commits([]), do: {:error, {:graph_commits, :missing}}

  defp validate_graph_commits(commits) do
    epochs = Enum.map(commits, & &1.epoch)
    source_nodes = Enum.map(commits, & &1.source_node_ref)

    cond do
      Enum.any?(source_nodes, &(&1 in [nil, ""])) ->
        {:error, {:graph_commits, :missing_source_node_ref}}

      Enum.uniq(epochs) != epochs ->
        {:error, {:graph_epochs, :not_unique}}

      Enum.sort(epochs) != epochs ->
        {:error, {:graph_epochs, :not_monotonic}}

      length(Enum.uniq(source_nodes)) < 2 ->
        {:error, {:graph_commits, :requires_multiple_source_nodes}}

      not Enum.all?(commits, &has_order_evidence?/1) ->
        {:error, {:graph_commits, :missing_order_evidence}}

      true ->
        :ok
    end
  end

  defp validate_proof_tokens([]), do: {:error, {:proof_tokens, :missing}}

  defp validate_proof_tokens(tokens) do
    if Enum.all?(tokens, &has_order_evidence?/1) do
      :ok
    else
      {:error, {:proof_tokens, :missing_order_evidence}}
    end
  end

  defp validate_aitrace_receipts(result) do
    receipts_by_node = aitrace_receipts_by_node(result)

    cond do
      map_size(receipts_by_node) < 2 ->
        {:error, {:aitrace_receipts_by_node, :requires_multiple_source_nodes}}

      not Enum.all?(Map.values(receipts_by_node), &receipts_have_node_evidence?/1) ->
        {:error, {:aitrace_receipts, :missing_node_order_evidence}}

      true ->
        :ok
    end
  end

  defp receipts_have_node_evidence?(receipts) do
    Enum.all?(receipts, fn receipt ->
      node_ref = receipt.source_node_ref

      has_order_evidence?(receipt.node_order_evidence) and
        receipt.node_order_evidence.source_node_ref == node_ref and
        Enum.all?(receipt.spans, &(&1.source_node_ref == node_ref))
    end)
  end

  defp validate_db_row_refs([]), do: {:error, {:db_row_refs, :missing}}
  defp validate_db_row_refs(row_refs) when is_list(row_refs), do: :ok

  defp validate_cluster_invalidations([]) do
    {:error, {:cluster_invalidations, :missing_observations}}
  end

  defp validate_cluster_invalidations(observations) do
    if Enum.all?(observations, & &1.observed?) do
      :ok
    else
      {:error, {:cluster_invalidations, :unobserved}}
    end
  end

  defp validate_snapshot_pin(%{split_epoch?: true}), do: {:error, {:snapshot_pin, :split_epoch}}

  defp validate_snapshot_pin(%{
         snapshot_epoch: snapshot_epoch,
         read_epochs: read_epochs,
         concurrent_revocation: %{epoch: revocation_epoch}
       }) do
    cond do
      not Enum.all?(read_epochs, fn {_read, epoch} -> epoch == snapshot_epoch end) ->
        {:error, {:snapshot_pin, :inconsistent_read_epoch}}

      revocation_epoch <= snapshot_epoch ->
        {:error, {:snapshot_pin, :revocation_not_after_pin}}

      true ->
        :ok
    end
  end

  defp validate_negative_failures(failures) do
    reasons = Enum.map(failures, & &1.reason)

    if reasons == [:duplicate_epoch, :missing_source_node_ref, :reused_epoch] do
      :ok
    else
      {:error, {:negative_failures, :missing_expected_fixture}}
    end
  end

  defp validate_partition_hooks(hooks) do
    if Enum.all?(hooks, &(&1.local_only? and not &1.release_evidence?)) do
      :ok
    else
      {:error, {:partition_hooks, :release_evidence_claimed_before_owner_gate}}
    end
  end

  defp validate_cleanup(%{leaves_tracked_artifacts?: false}), do: :ok
  defp validate_cleanup(_cleanup), do: {:error, {:cleanup, :tracked_artifacts_claimed}}

  defp has_order_evidence?(record) do
    is_binary(record.source_node_ref) and record.source_node_ref != "" and
      is_binary(record.commit_lsn) and record.commit_lsn != "" and
      match?(
        %{wall_ns: wall_ns, logical: logical, source_node_ref: node_ref}
        when is_integer(wall_ns) and is_integer(logical) and is_binary(node_ref),
        record.commit_hlc
      )
  end

  defp cleanup_plan(seed) do
    %{
      ref: "cleanup://stacklab/memsim/#{seed}",
      class: :deterministic_truncate,
      leaves_tracked_artifacts?: false,
      tracked_artifacts: []
    }
  end

  defp empty_stores do
    %{
      access_graph: [],
      tiers: %{private: [], shared: [], governed: []},
      policies: [],
      proof_tokens: [],
      invalidations: []
    }
  end

  defp empty_observations do
    %{
      aitrace_receipts: [],
      cluster_invalidation_observations: [],
      db_row_refs: [],
      proof_tokens: []
    }
  end

  defp empty_tables do
    %{
      access_graph_edges: [],
      memory_private: [],
      memory_shared: [],
      memory_governed: [],
      memory_policies: [],
      memory_proof_tokens: [],
      memory_invalidations: []
    }
  end

  defp trace_id(seed, epoch), do: "trace-m7a-#{seed}-#{epoch}"

  defp lsn(seed, offset) do
    upper = Integer.to_string(seed, 16) |> String.upcase()
    lower = Integer.to_string(seed * 16 + offset, 16) |> String.upcase()

    "#{upper}/#{lower}"
  end

  defp hlc(node, seed, offset) do
    %{
      wall_ns: @base_wall_ns + seed * 1_000 + offset,
      logical: offset,
      source_node_ref: node.node_ref
    }
  end

  defp uuid_for(value) do
    hash = :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

    [
      binary_part(hash, 0, 8),
      binary_part(hash, 8, 4),
      binary_part(hash, 12, 4),
      binary_part(hash, 16, 4),
      binary_part(hash, 20, 12)
    ]
    |> Enum.join("-")
  end

  defp hash_segment(value) do
    :crypto.hash(:sha256, value)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end
end
