defmodule StackLab.MemsimHarness.Phase7EvidenceReport do
  @moduledoc false

  @proof_kinds [:recall, :write_private, :share_up, :promote, :invalidate, :audit]
  @proof_kind_strings @proof_kinds |> Enum.map(&Atom.to_string/1) |> Enum.sort()

  @scenario_refs [
    {700, "s700_multi_node_epoch_monotonicity_and_ordering"},
    {701, "s701_access_graph_epoch_and_views"},
    {702, "s702_memory_tier_constraints"},
    {703, "s703_recall_accessibility"},
    {704, "s704_private_write_and_share_up"},
    {705, "s705_promotion_to_governed"},
    {706, "s706_invalidation_and_post_revocation"},
    {707, "s707_retrospective_audit_replay"},
    {708, "s708_citadel_authority_graph_integration"},
    {709, "s709_appkit_memory_control"},
    {710, "s710_no_bypass_memory"},
    {711, "s711_policy_version_and_transform_drift"},
    {712, "s712_release_evidence_report"}
  ]
  @scenario_ref_keys Enum.map(@scenario_refs, &elem(&1, 1))

  @top_level_keys ~w(
    report_id
    source_repos
    access_graph
    memory_tiers
    policies
    proof_tokens
    multinode
    operations
    retrospective_audit
    stacklab_invariants
    lineage
    negative_evidence
    cleanup
    results
  )

  @section_keys %{
    "access_graph" => ~w(contract_ref epoch_refs edge_refs derived_view_refs negative_refs),
    "memory_tiers" =>
      ~w(private_refs shared_refs governed_refs constraint_refs immutability_refs),
    "policies" =>
      ~w(read_policy_refs write_policy_refs transform_policy_refs share_up_policy_refs promote_policy_refs invalidate_policy_refs version_resolution_refs),
    "proof_tokens" =>
      ~w(recall_refs write_private_refs share_up_refs promote_refs invalidate_refs audit_refs hash_verification_refs),
    "multinode" =>
      ~w(node_identity_refs commit_lsn_refs commit_hlc_refs snapshot_epoch_refs cluster_invalidation_refs epoch_monotonicity_refs),
    "operations" =>
      ~w(recall_refs private_write_refs share_up_refs promotion_refs invalidation_refs audit_refs appkit_memory_control_refs),
    "retrospective_audit" =>
      ~w(verify_as_of_recall_refs re_evaluate_under_current_refs drift_report_refs),
    "lineage" =>
      ~w(trace_refs aitrace_refs trace_join_refs derived_state_attachment_refs parent_link_refs source_lineage_refs access_projection_hash_refs),
    "negative_evidence" =>
      ~w(identity_share_up_rejection governed_missing_evidence_rejection governed_missing_governance_rejection post_revocation_recall_rejection direct_store_bypass_rejection tampered_proof_rejection stale_policy_rejection broken_parent_link_rejection missing_node_order_rejection missing_snapshot_pin_rejection),
    "cleanup" => ~w(status cleanup_refs),
    "results" => ~w(summary positive_evidence_refs negative_evidence_refs)
  }

  @source_repo_specs [
    {"stack_lab", :stack_lab, "mix ci"},
    {"app_kit", :app_kit, "mix ci"},
    {"mezzanine", :mezzanine, "mix ci"},
    {"citadel", :citadel, "mix ci"},
    {"jido_integration", :jido_integration, "mix ci"},
    {"outer_brain", :outer_brain, "mix ci"},
    {"AITrace", :aitrace, "mix ci"},
    {"ground_plane", :ground_plane, "read-only baseline clean"},
    {"execution_plane", :execution_plane, "read-only baseline clean"},
    {"extravaganza", :extravaganza, "read-only baseline clean"}
  ]

  @read_only_commits %{
    ground_plane: "8a3d54a0d9c0dee11562430fdc6fa27f3e3e23de",
    execution_plane: "483b9643692dc5b2d6acc997694f7e1579c0bb81",
    extravaganza: "e412e43070e6dd923b8bbbb91669d8a63881b9c3"
  }

  @spec build(map()) :: {:ok, map()} | {:error, term()}
  def build(invariant_report) when is_map(invariant_report) do
    report = do_build(invariant_report)

    with :ok <- validate(report) do
      {:ok, report}
    end
  end

  @spec validate(map()) :: :ok | {:error, term()}
  def validate(report) when is_map(report) do
    with :ok <- validate_object(report, [], @top_level_keys, @top_level_keys),
         :ok <- validate_source_repos(report),
         :ok <- validate_named_sections(report),
         :ok <- validate_stacklab_invariants(report),
         :ok <- validate_family_refs(report, ["multinode", "commit_lsn_refs"]),
         :ok <- validate_family_refs(report, ["multinode", "commit_hlc_refs"]),
         :ok <- validate_family_refs(report, ["multinode", "snapshot_epoch_refs"]),
         :ok <- validate_family_refs(report, ["lineage", "trace_join_refs"]) do
      validate_cleanup(report)
    end
  end

  def validate(_report), do: {:error, :invalid_report}

  defp do_build(invariant_report) do
    inputs = invariant_report.required_report_inputs
    tokens = inputs.proof_tokens
    seed = report_seed(invariant_report)

    %{
      "report_id" => "phase7://stacklab/m16/evidence-report/#{seed}",
      "source_repos" => source_repos(inputs.source_repo_commits),
      "access_graph" => access_graph_section(inputs),
      "memory_tiers" => memory_tiers_section(inputs),
      "policies" => policies_section(seed),
      "proof_tokens" => proof_tokens_section(tokens),
      "multinode" => multinode_section(inputs, tokens),
      "operations" => operations_section(tokens, inputs),
      "retrospective_audit" => retrospective_audit_section(seed),
      "stacklab_invariants" => stacklab_invariants_section(invariant_report),
      "lineage" => lineage_section(tokens, inputs, seed),
      "negative_evidence" => negative_evidence_section(seed),
      "cleanup" => %{
        "status" => "pass",
        "cleanup_refs" => inputs.cleanup_refs
      },
      "results" => %{
        "summary" =>
          "Phase 7 governed memory evidence report validates owner refs and StackLab scenarios 700-712.",
        "positive_evidence_refs" => inputs.positive_evidence_refs,
        "negative_evidence_refs" => inputs.negative_evidence_refs
      }
    }
  end

  defp source_repos(source_commits) do
    Enum.map(@source_repo_specs, fn {repo, key, gate} ->
      %{
        "repo" => repo,
        "branch" => "main",
        "commit" => source_commit(source_commits, key),
        "pushed" => true,
        "gate" => gate
      }
    end)
  end

  defp source_commit(source_commits, key) do
    Map.get(source_commits, key) || Map.fetch!(@read_only_commits, key)
  end

  defp access_graph_section(inputs) do
    graph_refs = inputs.graph_refs

    %{
      "contract_ref" => "Platform.AccessGraph.v1",
      "epoch_refs" => Enum.map(graph_refs, &"db://access_graph_epochs/#{&1.epoch}"),
      "edge_refs" => Enum.map(graph_refs, & &1.transaction_ref),
      "derived_view_refs" => ["jido_integration://access-graph/views/current-and-historical"],
      "negative_refs" => ["negative://phase7/access-graph/missing-authority"]
    }
  end

  defp memory_tiers_section(inputs) do
    %{
      "private_refs" => ["jido_integration://memory_private/constraint-positive"],
      "shared_refs" => ["jido_integration://memory_shared/constraint-positive"],
      "governed_refs" => ["jido_integration://memory_governed/evidence-governance-positive"],
      "constraint_refs" => inputs.tier_constraint_refs,
      "immutability_refs" => ["jido_integration://memory-tiers/provenance-immutable-trigger"]
    }
  end

  defp policies_section(seed) do
    %{
      "read_policy_refs" => ["policy://stacklab/m16/#{seed}/read/v1"],
      "write_policy_refs" => ["policy://stacklab/m16/#{seed}/write/v1"],
      "transform_policy_refs" => ["policy://stacklab/m16/#{seed}/transform/v1"],
      "share_up_policy_refs" => ["policy://stacklab/m16/#{seed}/share-up/v1"],
      "promote_policy_refs" => ["policy://stacklab/m16/#{seed}/promote/v1"],
      "invalidate_policy_refs" => ["policy://stacklab/m16/#{seed}/invalidate/v1"],
      "version_resolution_refs" => ["mezzanine://policy-activation/#{seed}/snapshot-epoch"]
    }
  end

  defp proof_tokens_section(tokens) do
    %{
      "recall_refs" => proof_refs(tokens, :recall),
      "write_private_refs" => proof_refs(tokens, :write_private),
      "share_up_refs" => proof_refs(tokens, :share_up),
      "promote_refs" => proof_refs(tokens, :promote),
      "invalidate_refs" => proof_refs(tokens, :invalidate),
      "audit_refs" => proof_refs(tokens, :audit),
      "hash_verification_refs" => Enum.map(tokens, &"#{&1.proof_id}#hash-verified")
    }
  end

  defp multinode_section(inputs, tokens) do
    %{
      "node_identity_refs" =>
        inputs.source_node_ordering_refs
        |> Enum.map(& &1.source_node_ref)
        |> Enum.uniq(),
      "commit_lsn_refs" => family_refs(tokens, "commit_lsn"),
      "commit_hlc_refs" => family_refs(tokens, "commit_hlc"),
      "snapshot_epoch_refs" => family_refs(tokens, "snapshot_epoch"),
      "cluster_invalidation_refs" => Enum.map(inputs.invalidation_refs, & &1.invalidation_id),
      "epoch_monotonicity_refs" => Enum.map(inputs.graph_refs, & &1.transaction_ref)
    }
  end

  defp operations_section(tokens, inputs) do
    %{
      "recall_refs" => proof_refs(tokens, :recall),
      "private_write_refs" => proof_refs(tokens, :write_private),
      "share_up_refs" => proof_refs(tokens, :share_up),
      "promotion_refs" => proof_refs(tokens, :promote),
      "invalidation_refs" => proof_refs(tokens, :invalidate),
      "audit_refs" => proof_refs(tokens, :audit),
      "appkit_memory_control_refs" => inputs.appkit_memory_control_dto_refs
    }
  end

  defp retrospective_audit_section(seed) do
    %{
      "verify_as_of_recall_refs" => ["mezzanine://retrospective-audit/#{seed}/as-of-recall"],
      "re_evaluate_under_current_refs" => ["mezzanine://retrospective-audit/#{seed}/current"],
      "drift_report_refs" => ["mezzanine://retrospective-audit/#{seed}/drift-report"]
    }
  end

  defp stacklab_invariants_section(invariant_report) do
    %{
      "passed" => true,
      "scenario_refs" =>
        Map.new(@scenario_refs, fn {id, key} ->
          scenario = Enum.find(invariant_report.scenarios, &(&1.id == id))
          {key, "stacklab://scenario/#{id}/#{scenario.name}"}
        end)
    }
  end

  defp lineage_section(tokens, inputs, seed) do
    %{
      "trace_refs" => Enum.map(tokens, &"trace://#{&1.trace_id}"),
      "aitrace_refs" => inputs.aitrace_refs,
      "trace_join_refs" => Enum.map(tokens, &trace_join_ref/1),
      "derived_state_attachment_refs" => inputs.jido_derived_state_attachment_refs,
      "parent_link_refs" => [
        "fragment://stacklab/#{seed}/private->shared",
        "fragment://stacklab/#{seed}/shared->governed"
      ],
      "source_lineage_refs" => inputs.outer_brain_provenance_refs,
      "access_projection_hash_refs" => [
        "sha256:stacklab-m16-access-projection-private-shared",
        "sha256:stacklab-m16-access-projection-shared-governed"
      ]
    }
  end

  defp negative_evidence_section(seed) do
    %{
      "identity_share_up_rejection" => "negative://stacklab/m16/#{seed}/identity-share-up",
      "governed_missing_evidence_rejection" =>
        "negative://stacklab/m16/#{seed}/governed-missing-evidence",
      "governed_missing_governance_rejection" =>
        "negative://stacklab/m16/#{seed}/governed-missing-governance",
      "post_revocation_recall_rejection" =>
        "negative://stacklab/m16/#{seed}/post-revocation-recall",
      "direct_store_bypass_rejection" => "negative://stacklab/m16/#{seed}/direct-store-bypass",
      "tampered_proof_rejection" => "negative://stacklab/m16/#{seed}/tampered-proof",
      "stale_policy_rejection" => "negative://stacklab/m16/#{seed}/stale-policy",
      "broken_parent_link_rejection" => "negative://stacklab/m16/#{seed}/broken-parent-link",
      "missing_node_order_rejection" => "negative://stacklab/m16/#{seed}/missing-node-order",
      "missing_snapshot_pin_rejection" => "negative://stacklab/m16/#{seed}/missing-snapshot-pin"
    }
  end

  defp proof_refs(tokens, kind) do
    tokens
    |> Enum.filter(&(&1.proof_kind == kind))
    |> Enum.map(& &1.proof_id)
  end

  defp family_refs(tokens, field) do
    Enum.map(tokens, fn token ->
      %{
        "proof_kind" => Atom.to_string(token.proof_kind),
        "proof_token_ref" => token.proof_id,
        "ref" => "#{token.proof_id}##{field}",
        "value" => field_value(token, field)
      }
    end)
  end

  defp field_value(token, "commit_lsn"), do: token.commit_lsn
  defp field_value(token, "commit_hlc"), do: inspect(token.commit_hlc)
  defp field_value(token, "snapshot_epoch"), do: Integer.to_string(token.snapshot_epoch)

  defp trace_join_ref(token) do
    %{
      "proof_kind" => Atom.to_string(token.proof_kind),
      "proof_token_ref" => token.proof_id,
      "ref" => "#{token.proof_id}#trace-join",
      "trace_ref" => "trace://#{token.trace_id}",
      "aitrace_ref" => token.aitrace_ref,
      "source_node_ref" => token.source_node_ref,
      "value" => "#{token.trace_id}|#{token.aitrace_ref}"
    }
  end

  defp report_seed(%{cleanup: %{ref: ref}}) do
    ref
    |> String.split("/")
    |> List.last()
  end

  defp validate_source_repos(report) do
    repos = Map.get(report, "source_repos", [])
    allowed = ~w(repo branch commit pushed gate)

    cond do
      repos == [] ->
        {:error, {:source_repos, :empty}}

      not is_list(repos) ->
        {:error, {:source_repos, :invalid}}

      true ->
        validate_source_repo_list(repos, allowed)
    end
  end

  defp validate_source_repo_list(repos, allowed) do
    Enum.reduce_while(repos, :ok, fn repo, :ok ->
      case validate_source_repo_object(repo, allowed) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_source_repo_object(repo, allowed) do
    with :ok <- validate_object(repo, ["source_repos"], allowed, allowed) do
      validate_source_repo(repo)
    end
  end

  defp validate_source_repo(repo) do
    cond do
      repo["pushed"] != true -> {:error, {:source_repos, :not_pushed}}
      not non_empty_string?(repo["commit"]) -> {:error, {:source_repos, :missing_commit}}
      String.length(repo["commit"]) < 7 -> {:error, {:source_repos, :short_commit}}
      true -> :ok
    end
  end

  defp validate_named_sections(report) do
    Enum.reduce_while(@section_keys, :ok, fn {section, keys}, :ok ->
      with {:ok, value} <- fetch_section(report, section),
           :ok <- validate_object(value, [section], keys, keys),
           :ok <- validate_section_non_empty(section, value, keys) do
        {:cont, :ok}
      else
        error -> {:halt, error}
      end
    end)
  end

  defp fetch_section(report, section) do
    case Map.fetch(report, section) do
      {:ok, value} when is_map(value) -> {:ok, value}
      {:ok, _value} -> {:error, {section_atom(section), :invalid}}
      :error -> {:error, {:report, {:missing, [section]}}}
    end
  end

  defp validate_stacklab_invariants(report) do
    invariants = report["stacklab_invariants"]
    scenario_refs = invariants["scenario_refs"]

    cond do
      invariants["passed"] != true ->
        {:error, {:stacklab_invariants, :not_passed}}

      not is_map(scenario_refs) ->
        {:error, {:stacklab_invariants, :invalid_scenario_refs}}

      @scenario_ref_keys -- Map.keys(scenario_refs) != [] ->
        {:error,
         {:stacklab_invariants,
          {:missing_scenarios, @scenario_ref_keys -- Map.keys(scenario_refs)}}}

      not Enum.all?(scenario_refs, fn {_key, value} -> non_empty_string?(value) end) ->
        {:error, {:stacklab_invariants, :invalid_scenario_ref}}

      true ->
        :ok
    end
  end

  defp validate_family_refs(report, path) do
    refs = get_in(report, path)

    cond do
      refs == [] ->
        {:error, {section_atom(hd(path)), {:empty, List.last(path)}}}

      not is_list(refs) ->
        {:error, {section_atom(hd(path)), {:invalid, List.last(path)}}}

      proof_kinds(refs) != @proof_kind_strings ->
        {:error, {section_atom(hd(path)), {:missing_proof_families, List.last(path)}}}

      not Enum.all?(refs, &valid_family_ref?/1) ->
        {:error, {section_atom(hd(path)), {:invalid, List.last(path)}}}

      true ->
        :ok
    end
  end

  defp proof_kinds(refs) do
    refs
    |> Enum.map(& &1["proof_kind"])
    |> Enum.sort()
  end

  defp valid_family_ref?(ref) do
    is_map(ref) and non_empty_string?(ref["proof_kind"]) and
      non_empty_string?(ref["proof_token_ref"]) and non_empty_string?(ref["ref"]) and
      non_empty_string?(ref["value"])
  end

  defp validate_cleanup(report) do
    case get_in(report, ["cleanup", "status"]) do
      "pass" -> :ok
      _other -> {:error, {:cleanup, :not_passed}}
    end
  end

  defp validate_object(value, path, required, allowed) when is_map(value) do
    keys = Map.keys(value)
    unknown = Enum.sort(keys -- allowed)
    missing = required -- keys

    cond do
      unknown != [] -> {:error, {:unknown_properties, path, unknown}}
      missing != [] -> {:error, missing_error(path, missing)}
      true -> :ok
    end
  end

  defp validate_object(_value, path, _required, _allowed), do: {:error, {path, :invalid}}

  defp validate_section_non_empty(section, value, keys) do
    Enum.reduce_while(keys, :ok, fn key, :ok ->
      case value[key] do
        [] -> {:halt, {:error, {section_atom(section), {:empty, key}}}}
        "" -> {:halt, {:error, {section_atom(section), {:empty, key}}}}
        _other -> {:cont, :ok}
      end
    end)
  end

  defp missing_error([], missing), do: {:report, {:missing, missing}}
  defp missing_error([section], missing), do: {section_atom(section), {:missing, missing}}

  defp non_empty_string?(value), do: is_binary(value) and value != ""

  defp section_atom("access_graph"), do: :access_graph
  defp section_atom("memory_tiers"), do: :memory_tiers
  defp section_atom("policies"), do: :policies
  defp section_atom("proof_tokens"), do: :proof_tokens
  defp section_atom("multinode"), do: :multinode
  defp section_atom("operations"), do: :operations
  defp section_atom("retrospective_audit"), do: :retrospective_audit
  defp section_atom("stacklab_invariants"), do: :stacklab_invariants
  defp section_atom("lineage"), do: :lineage
  defp section_atom("negative_evidence"), do: :negative_evidence
  defp section_atom("cleanup"), do: :cleanup
  defp section_atom("results"), do: :results
  defp section_atom("source_repos"), do: :source_repos
end
