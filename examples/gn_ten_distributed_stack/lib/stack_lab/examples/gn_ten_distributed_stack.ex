defmodule StackLab.Examples.GnTenDistributedStack.Receipt do
  @moduledoc "Distributed gn-ten proof receipt."

  @enforce_keys [
    :receipt_ref,
    :schema_version,
    :status,
    :profile,
    :topology_ref,
    :monolith_baseline_receipt_ref,
    :context_packet_ref,
    :context_packet_hash,
    :authority_ref,
    :trace_refs,
    :node_trace_refs,
    :aitrace_exports,
    :replay_bundle,
    :evidence_status,
    :persistence_profiles,
    :persistence_status,
    :node_lab_run,
    :distributed_envelope_scan,
    :node_placement,
    :does_not_prove
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          receipt_ref: String.t(),
          schema_version: String.t(),
          status: :pass | :open_defect,
          profile: String.t(),
          topology_ref: String.t(),
          monolith_baseline_receipt_ref: String.t(),
          context_packet_ref: String.t(),
          context_packet_hash: String.t(),
          authority_ref: String.t(),
          trace_refs: [String.t()],
          node_trace_refs: [map()],
          aitrace_exports: [map()],
          replay_bundle: map(),
          evidence_status: String.t(),
          persistence_profiles: map(),
          persistence_status: String.t(),
          node_lab_run: map(),
          distributed_envelope_scan: map(),
          node_placement: map(),
          does_not_prove: [String.t()]
        }
end

defmodule StackLab.Examples.GnTenDistributedStack.RouterModelReceipt do
  @moduledoc "Distributed gn-ten router/model proof receipt."

  @enforce_keys [
    :receipt_ref,
    :schema_version,
    :status,
    :profile,
    :topology_ref,
    :monolith_baseline_receipt_ref,
    :context_packet_ref,
    :context_packet_hash,
    :authority_ref,
    :route_decision_ref,
    :selected_model_profile_ref,
    :model_invocation_ref,
    :model_receipt_ref,
    :model_token_summary,
    :model_cost_summary,
    :model_stream_refs,
    :stream_fragment_posture,
    :trace_refs,
    :node_trace_refs,
    :aitrace_exports,
    :replay_bundle,
    :evidence_status,
    :persistence_profiles,
    :persistence_status,
    :node_lab_run,
    :distributed_envelope_scan,
    :node_placement,
    :does_not_prove
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          receipt_ref: String.t(),
          schema_version: String.t(),
          status: :pass | :open_defect,
          profile: String.t(),
          topology_ref: String.t(),
          monolith_baseline_receipt_ref: String.t(),
          context_packet_ref: String.t(),
          context_packet_hash: String.t(),
          authority_ref: String.t(),
          route_decision_ref: String.t(),
          selected_model_profile_ref: String.t(),
          model_invocation_ref: String.t(),
          model_receipt_ref: String.t(),
          model_token_summary: map(),
          model_cost_summary: map(),
          model_stream_refs: [String.t()],
          stream_fragment_posture: String.t(),
          trace_refs: [String.t()],
          node_trace_refs: [map()],
          aitrace_exports: [map()],
          replay_bundle: map(),
          evidence_status: String.t(),
          persistence_profiles: map(),
          persistence_status: String.t(),
          node_lab_run: map(),
          distributed_envelope_scan: map(),
          node_placement: map(),
          does_not_prove: [String.t()]
        }
end

defmodule StackLab.Examples.GnTenDistributedStack.FaultRecoveryReceipt do
  @moduledoc "Distributed gn-ten fault and recovery proof receipt."

  @enforce_keys [
    :receipt_ref,
    :schema_version,
    :status,
    :profile,
    :topology_ref,
    :baseline_receipt_ref,
    :fault_receipts,
    :owner_recovery_evidence,
    :persistence_profiles,
    :persistence_status,
    :trace_refs,
    :node_lab_run,
    :does_not_prove
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          receipt_ref: String.t(),
          schema_version: String.t(),
          status: :pass | :open_defect,
          profile: String.t(),
          topology_ref: String.t(),
          baseline_receipt_ref: String.t(),
          fault_receipts: [map()],
          owner_recovery_evidence: [map()],
          persistence_profiles: map(),
          persistence_status: String.t(),
          trace_refs: [String.t()],
          node_lab_run: map(),
          does_not_prove: [String.t()]
        }
end

defmodule StackLab.Examples.GnTenDistributedStack do
  @moduledoc """
  Local distributed gn-ten proof scenarios.
  """

  alias StackLab.Examples.GnTenDistributedStack.{
    FaultRecoveryReceipt,
    Receipt,
    RouterModelReceipt
  }

  @context_schema_version "stack_lab.gn_ten_distributed_stack.context_6_node.v1"
  @router_model_schema_version "stack_lab.gn_ten_distributed_stack.router_model_6_node.v1"
  @fault_recovery_schema_version "stack_lab.gn_ten_distributed_stack.partition_recovery.v1"
  @context_profile "context_6_node"
  @router_model_profile "router_model_6_node"
  @fault_recovery_profile "partition_recovery"
  @envelope_schema_version "stack_lab.distributed_envelope.v1"
  @context_roundtrip Module.concat([StackLab, Examples, ContextABIRoundtrip])
  @router_roundtrip Module.concat([StackLab, Examples, NSHKRRouterFabricRoundtrip])
  @persistence_roundtrip Module.concat([StackLab, Examples, PersistenceModeRoundtrip])
  @aitrace_evidence Module.concat([AITrace, RemoteFacade, Evidence])
  @aitrace_fixture_transport Module.concat([AITrace, NSHKR, ExportTransport, Fixture])
  @replay_bundle Module.concat([AITrace, Trace, ReplayBundle])
  @envelope_scanner Module.concat([StackLab, GnTenNodeLab, EnvelopeScanner])
  @fault_drill Module.concat([StackLab, GnTenNodeLab, FaultDrill])
  @runner Module.concat([StackLab, GnTenNodeLab, Runner])
  @json Module.concat([Jason])

  @spec run_context_6_node(keyword()) :: {:ok, Receipt.t()} | {:error, term()}
  def run_context_6_node(opts \\ []) when is_list(opts) do
    topology_path = Keyword.get_lazy(opts, :topology_path, &default_context_topology_path/0)
    state_path = Keyword.get_lazy(opts, :state_path, &default_state_path/0)
    evidence_opts = Keyword.get(opts, :evidence_opts, [])

    with {:ok, _started} <- Application.ensure_all_started(:aitrace),
         {:ok, baseline} <- call(@context_roundtrip, :run, []),
         {:ok, node_lab_run} <-
           call(@runner, :up, [
             topology_path,
             [
               state_path: state_path,
               run_id: "context-6-node",
               keep?: false
             ]
           ]) do
      envelope_scan =
        call(@envelope_scanner, :scan_many, [
          envelopes(baseline, node_lab_run),
          [supported_schema_versions: [@envelope_schema_version]]
        ])

      node_trace_refs = node_trace_refs(baseline, node_lab_run, :context)
      aitrace_exports = export_trace_evidence(node_trace_refs, :context, evidence_opts)
      replay_bundle = replay_bundle(baseline, :context)
      persistence_profiles = persistence_profiles()

      {:ok,
       %Receipt{
         receipt_ref: receipt_ref(baseline),
         schema_version: @context_schema_version,
         status:
           status(baseline, node_lab_run, envelope_scan, aitrace_exports, persistence_profiles),
         profile: @context_profile,
         topology_ref: node_lab_run["topology_ref"],
         monolith_baseline_receipt_ref: baseline.receipt_ref,
         context_packet_ref: baseline.context_packet_ref,
         context_packet_hash: baseline.context_packet_hash,
         authority_ref: baseline.authority_ref,
         trace_refs: baseline.trace_refs,
         node_trace_refs: node_trace_refs,
         aitrace_exports: aitrace_exports,
         replay_bundle: replay_bundle,
         evidence_status: evidence_status(aitrace_exports),
         persistence_profiles: persistence_profiles,
         persistence_status: persistence_status(persistence_profiles),
         node_lab_run: node_lab_run,
         distributed_envelope_scan: envelope_scan,
         node_placement: node_placement(node_lab_run),
         does_not_prove: [
           "production distribution security",
           "release artifact boot",
           "live provider behavior",
           "fault recovery",
           "TRINITY or GEPA quality"
         ]
       }}
    end
  end

  @spec run_router_model_6_node(keyword()) ::
          {:ok, RouterModelReceipt.t()} | {:error, term()}
  def run_router_model_6_node(opts \\ []) when is_list(opts) do
    topology_path = Keyword.get_lazy(opts, :topology_path, &default_router_model_topology_path/0)
    state_path = Keyword.get_lazy(opts, :state_path, &default_router_model_state_path/0)
    evidence_opts = Keyword.get(opts, :evidence_opts, [])

    with {:ok, _started} <- Application.ensure_all_started(:aitrace),
         {:ok, baseline} <- call(@router_roundtrip, :run, []),
         {:ok, node_lab_run} <-
           call(@runner, :up, [
             topology_path,
             [
               state_path: state_path,
               run_id: "router-model-6-node",
               keep?: false
             ]
           ]) do
      envelope_scan =
        call(@envelope_scanner, :scan_many, [
          envelopes(baseline, node_lab_run, :router_model),
          [supported_schema_versions: [@envelope_schema_version]]
        ])

      node_trace_refs = node_trace_refs(baseline, node_lab_run, :router_model)
      aitrace_exports = export_trace_evidence(node_trace_refs, :router_model, evidence_opts)
      replay_bundle = replay_bundle(baseline, :router_model)
      persistence_profiles = persistence_profiles()

      {:ok,
       %RouterModelReceipt{
         receipt_ref: router_model_receipt_ref(baseline),
         schema_version: @router_model_schema_version,
         status:
           router_model_status(
             baseline,
             node_lab_run,
             envelope_scan,
             aitrace_exports,
             persistence_profiles
           ),
         profile: @router_model_profile,
         topology_ref: node_lab_run["topology_ref"],
         monolith_baseline_receipt_ref: baseline.receipt_ref,
         context_packet_ref: baseline.context_packet_ref,
         context_packet_hash: baseline.context_packet_hash,
         authority_ref: baseline.authority_ref,
         route_decision_ref: baseline.route_decision_ref,
         selected_model_profile_ref: baseline.selected_model_profile_ref,
         model_invocation_ref: baseline.model_invocation_ref,
         model_receipt_ref: baseline.model_receipt_ref,
         model_token_summary: baseline.model_token_summary,
         model_cost_summary: baseline.model_cost_summary,
         model_stream_refs: baseline.model_stream_refs,
         stream_fragment_posture: baseline.stream_fragment_posture,
         trace_refs: baseline.trace_refs,
         node_trace_refs: node_trace_refs,
         aitrace_exports: aitrace_exports,
         replay_bundle: replay_bundle,
         evidence_status: evidence_status(aitrace_exports),
         persistence_profiles: persistence_profiles,
         persistence_status: persistence_status(persistence_profiles),
         node_lab_run: node_lab_run,
         distributed_envelope_scan: envelope_scan,
         node_placement: node_placement(node_lab_run),
         does_not_prove: [
           "production distribution security",
           "release artifact boot",
           "live provider behavior",
           "fault recovery",
           "Execution Plane lower-lane execution"
         ]
       }}
    end
  end

  @spec run_partition_recovery(keyword()) ::
          {:ok, FaultRecoveryReceipt.t()} | {:error, term()}
  def run_partition_recovery(opts \\ []) when is_list(opts) do
    with {:ok, baseline} <- run_router_model_6_node(opts) do
      fault_receipts = fault_receipts(baseline)

      {:ok,
       %FaultRecoveryReceipt{
         receipt_ref: fault_recovery_receipt_ref(baseline),
         schema_version: @fault_recovery_schema_version,
         status: fault_recovery_status(fault_receipts),
         profile: @fault_recovery_profile,
         topology_ref: baseline.topology_ref,
         baseline_receipt_ref: baseline.receipt_ref,
         fault_receipts: fault_receipts,
         owner_recovery_evidence: owner_recovery_evidence(),
         persistence_profiles: baseline.persistence_profiles,
         persistence_status: baseline.persistence_status,
         trace_refs: baseline.trace_refs,
         node_lab_run: baseline.node_lab_run,
         does_not_prove: [
           "WAN partition behavior",
           "production service discovery",
           "release artifact boot",
           "live provider retry semantics",
           "Execution Plane lower-lane partition behavior"
         ]
       }}
    end
  end

  @spec to_map(Receipt.t() | RouterModelReceipt.t() | FaultRecoveryReceipt.t()) :: map()
  def to_map(%Receipt{} = receipt), do: json_safe(receipt)
  def to_map(%RouterModelReceipt{} = receipt), do: json_safe(receipt)
  def to_map(%FaultRecoveryReceipt{} = receipt), do: json_safe(receipt)

  @spec to_json!(Receipt.t() | RouterModelReceipt.t() | FaultRecoveryReceipt.t()) :: String.t()
  def to_json!(%Receipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  def to_json!(%RouterModelReceipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  def to_json!(%FaultRecoveryReceipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  defp envelopes(baseline, node_lab_run, scenario \\ :context) do
    node_lab_run
    |> Map.fetch!("boot_receipts")
    |> Enum.map(fn node ->
      baseline_envelope = %{
        envelope_ref: "distributed-envelope://#{node["node_id"]}",
        schema_version: @envelope_schema_version,
        tenant_ref: tenant_ref(scenario),
        correlation_ref: "corr://#{scenario_ref(scenario)}/distributed/#{node["node_id"]}",
        idempotency_key: "idem://#{scenario_ref(scenario)}/distributed/#{node["node_id"]}",
        origin_node_ref: "node://stack_lab/controller",
        target_profile: node["profile"],
        authority_ref: baseline.authority_ref,
        redaction_class: "bounded_refs_only",
        payload_mode: "refs_only",
        trace_ref: List.first(baseline.trace_refs),
        issued_at: "2026-05-25T00:00:00Z",
        context_packet_ref: baseline.context_packet_ref,
        context_packet_hash: baseline.context_packet_hash,
        owner_group_membership: node["owner_group_membership"]
      }

      Map.merge(baseline_envelope, router_model_envelope_attrs(baseline, scenario))
    end)
  end

  defp tenant_ref(:context), do: "tenant://context-abi/demo"
  defp tenant_ref(:router_model), do: "tenant://router-fabric/demo"

  defp scenario_ref(:context), do: "context-abi"
  defp scenario_ref(:router_model), do: "router-fabric"

  defp router_model_envelope_attrs(_baseline, :context), do: %{}

  defp router_model_envelope_attrs(baseline, :router_model) do
    %{
      route_decision_ref: baseline.route_decision_ref,
      selected_model_profile_ref: baseline.selected_model_profile_ref,
      model_invocation_ref: baseline.model_invocation_ref,
      model_receipt_ref: baseline.model_receipt_ref,
      model_token_summary: baseline.model_token_summary,
      model_cost_summary: baseline.model_cost_summary,
      model_stream_refs: baseline.model_stream_refs,
      stream_fragment_posture: baseline.stream_fragment_posture
    }
  end

  defp node_placement(node_lab_run) do
    boot_receipts = Map.fetch!(node_lab_run, "boot_receipts")
    node_names = Enum.map(boot_receipts, &Map.fetch!(&1, "node"))

    %{
      controller_included?: true,
      domain_node_count: length(node_names),
      distinct_domain_nodes?: length(node_names) == length(Enum.uniq(node_names)),
      nodes: node_names
    }
  end

  defp status(baseline, node_lab_run, envelope_scan, aitrace_exports, persistence_profiles) do
    if baseline.status == :pass and node_lab_run["status"] == "pass" and
         envelope_scan["status"] == "pass" and evidence_status(aitrace_exports) == "pass" and
         persistence_status(persistence_profiles) == "pass" do
      :pass
    else
      :open_defect
    end
  end

  defp router_model_status(
         baseline,
         node_lab_run,
         envelope_scan,
         aitrace_exports,
         persistence_profiles
       ) do
    if baseline.status == :pass and node_lab_run["status"] == "pass" and
         envelope_scan["status"] == "pass" and route_and_model_refs_present?(baseline) and
         model_accounting_present?(baseline) and evidence_status(aitrace_exports) == "pass" and
         persistence_status(persistence_profiles) == "pass" do
      :pass
    else
      :open_defect
    end
  end

  defp route_and_model_refs_present?(baseline) do
    present?(baseline.route_decision_ref) and present?(baseline.selected_model_profile_ref) and
      present?(baseline.model_invocation_ref) and present?(baseline.model_receipt_ref)
  end

  defp model_accounting_present?(baseline) do
    is_map(baseline.model_token_summary) and map_size(baseline.model_token_summary) > 0 and
      is_map(baseline.model_cost_summary) and map_size(baseline.model_cost_summary) > 0 and
      is_list(baseline.model_stream_refs) and present?(baseline.stream_fragment_posture)
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp receipt_ref(baseline) do
    suffix =
      baseline.context_packet_hash
      |> String.replace_prefix("sha256:", "")
      |> String.slice(0, 16)

    "gn-ten-distributed-context://#{suffix}"
  end

  defp router_model_receipt_ref(baseline) do
    suffix =
      baseline.model_receipt_ref
      |> String.replace_prefix("jido-model-invocation-receipt/", "")
      |> String.replace_prefix("sha256:", "")
      |> String.slice(0, 16)

    "gn-ten-distributed-router-model://#{suffix}"
  end

  defp fault_recovery_receipt_ref(baseline) do
    baseline.receipt_ref
    |> String.replace_prefix("gn-ten-distributed-router-model://", "")
    |> then(&"gn-ten-distributed-partition-recovery://#{&1}")
  end

  defp default_context_topology_path do
    Path.expand("../../../priv/topologies/context_6_node.exs", __DIR__)
  end

  defp default_router_model_topology_path do
    Path.expand("../../../priv/topologies/router_model_6_node.exs", __DIR__)
  end

  defp default_state_path do
    Path.join(System.tmp_dir!(), "stack_lab_gn_ten_distributed_context_6_node.json")
  end

  defp default_router_model_state_path do
    Path.join(System.tmp_dir!(), "stack_lab_gn_ten_distributed_router_model_6_node.json")
  end

  defp node_trace_refs(baseline, node_lab_run, scenario) do
    root_trace_ref = baseline.trace_refs |> List.wrap() |> List.first()

    node_lab_run
    |> Map.fetch!("boot_receipts")
    |> Enum.map(fn node ->
      %{
        "source_node_ref" => "node://#{node["node_id"]}",
        "node_id" => node["node_id"],
        "profile" => node["profile"],
        "trace_ref" => root_trace_ref,
        "correlation_ref" => "corr://#{scenario_ref(scenario)}/trace/#{node["node_id"]}"
      }
    end)
  end

  defp export_trace_evidence(node_trace_refs, scenario, evidence_opts) do
    Enum.map(node_trace_refs, fn node_trace_ref ->
      request = %{
        "schema_ref" => "schema://stack_lab/aitrace/distributed-export/v1",
        "tenant_ref" => tenant_ref(scenario),
        "correlation_ref" => node_trace_ref["correlation_ref"],
        "idempotency_key" =>
          "idem://#{scenario_ref(scenario)}/aitrace/#{node_trace_ref["node_id"]}",
        "trace_ref" => node_trace_ref["trace_ref"],
        "redaction_class" => "bounded_refs_only",
        "source_node_ref" => node_trace_ref["source_node_ref"]
      }

      case call(@aitrace_evidence, :export_trace, [
             request,
             Keyword.merge([transport: @aitrace_fixture_transport], evidence_opts)
           ]) do
        {:ok, export} ->
          Map.merge(node_trace_ref, %{"status" => "pass", "export" => export})

        {:error, reason} ->
          Map.merge(node_trace_ref, %{"status" => "open_defect", "export_error" => reason})
      end
    end)
  end

  defp evidence_status(exports) do
    if Enum.all?(exports, &(Map.get(&1, "status") == "pass")), do: "pass", else: "open_defect"
  end

  defp persistence_profiles do
    case call(@persistence_roundtrip, :run, []) do
      {:ok, receipt} ->
        profile_receipts = Enum.map(receipt.profile_receipts, &profile_receipt_fact/1)
        deterministic_profile_ids = ["mickey_mouse", "memory_debug"]

        deterministic_profiles =
          Enum.filter(profile_receipts, &(&1["profile_id"] in deterministic_profile_ids))

        %{
          "status" => Atom.to_string(receipt.status),
          "source_receipt_ref" => receipt.receipt_ref,
          "deterministic_profiles" => deterministic_profiles,
          "opt_in_external_profiles" => opt_in_external_profiles(profile_receipts),
          "matrix_scan" => json_safe(receipt.matrix_scan),
          "substrate_started_by_stack_lab?" => false,
          "temporal_started_by_stack_lab?" => false,
          "postgres_started_by_stack_lab?" => false,
          "raw_debug_payloads_persisted?" => false
        }

      {:error, reason} ->
        %{
          "status" => "open_defect",
          "reason" => inspect(reason),
          "deterministic_profiles" => [],
          "opt_in_external_profiles" => [],
          "substrate_started_by_stack_lab?" => false,
          "temporal_started_by_stack_lab?" => false,
          "postgres_started_by_stack_lab?" => false,
          "raw_debug_payloads_persisted?" => false
        }
    end
  end

  defp persistence_status(%{
         "status" => "pass",
         "deterministic_profiles" => deterministic_profiles
       }) do
    profile_ids =
      deterministic_profiles
      |> Enum.map(&Map.fetch!(&1, "profile_id"))
      |> MapSet.new()

    if MapSet.subset?(MapSet.new(["mickey_mouse", "memory_debug"]), profile_ids) do
      "pass"
    else
      "open_defect"
    end
  end

  defp persistence_status(_profiles), do: "open_defect"

  defp profile_receipt_fact(profile_receipt) do
    %{
      "profile_id" => profile_receipt.profile_id |> Atom.to_string(),
      "selected_tier" => profile_receipt.selected_tier |> Atom.to_string(),
      "store_set_id" => profile_receipt.store_set_id |> Atom.to_string(),
      "capture_level" => profile_receipt.capture_level |> Atom.to_string(),
      "restart_claim" => profile_receipt.restart_claim |> Atom.to_string(),
      "durable_opt_in?" => profile_receipt.durable_opt_in?,
      "durable_tag" => profile_receipt.durable_tag,
      "proof_command" => profile_receipt.proof_command,
      "storage_behavior_ref" => profile_receipt.storage_behavior_ref,
      "authority_semantics_ref" => profile_receipt.authority_semantics_ref
    }
  end

  defp opt_in_external_profiles(profile_receipts) do
    postgres_profiles =
      profile_receipts
      |> Enum.filter(&(&1["profile_id"] in ["integration_postgres", "full_debug_tracked"]))
      |> Enum.map(fn profile ->
        Map.merge(profile, %{
          "proof_mode" => "opt_in_preflight_only",
          "compose_ref" => "tools/compose/multi-node.yml",
          "toxiproxy_ref" => "tools/toxiproxy/toxiproxy.json",
          "substrate_started_by_stack_lab?" => false
        })
      end)

    postgres_profiles ++
      [
        %{
          "profile_id" => "ops_durable_temporal",
          "selected_tier" => "ops_durable",
          "store_set_id" => "temporal_workflow_runtime",
          "capture_level" => "metadata",
          "restart_claim" => "durable_restart",
          "durable_opt_in?" => true,
          "durable_tag" => "persistence-durable-opt-in",
          "proof_mode" => "blocked_until_repo_owned_just",
          "just_command" => "cd /home/home/p/g/n/mezzanine && just dev-status",
          "substrate_started_by_stack_lab?" => false
        }
      ]
  end

  defp replay_bundle(baseline, scenario) do
    attrs =
      %{
        bundle_ref: "replay-bundle://stack_lab/#{scenario_ref(scenario)}/distributed",
        source_trace_ref: baseline.trace_refs |> List.wrap() |> List.first(),
        replay_trace_ref: "trace://stack_lab/#{scenario_ref(scenario)}/replay",
        divergence_list_ref: "divergence://stack_lab/#{scenario_ref(scenario)}/none",
        audit_ref: "audit://stack_lab/#{scenario_ref(scenario)}/phase10",
        redaction_policy_ref: "redaction-policy://stack_lab/bounded-refs-only",
        release_manifest_ref:
          "release-manifest://stack_lab/local-distributed/#{scenario_ref(scenario)}",
        context_packet_ref: baseline.context_packet_ref,
        context_packet_hash: baseline.context_packet_hash
      }
      |> maybe_put(:route_decision_ref, Map.get(baseline, :route_decision_ref))
      |> maybe_put(:model_invocation_ref, Map.get(baseline, :model_invocation_ref))
      |> maybe_put(:model_receipt_ref, Map.get(baseline, :model_receipt_ref))

    case call(@replay_bundle, :new, [attrs]) do
      {:ok, bundle} ->
        bundle
        |> Map.from_struct()
        |> Map.take([
          :bundle_ref,
          :source_trace_ref,
          :replay_trace_ref,
          :divergence_list_ref,
          :audit_ref,
          :redaction_policy_ref,
          :release_manifest_ref,
          :context_packet_ref,
          :context_packet_hash,
          :route_decision_ref,
          :model_invocation_ref,
          :model_receipt_ref
        ])

      {:error, reason} ->
        %{"status" => "open_defect", "reason" => inspect(reason)}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fault_receipts(baseline) do
    run = baseline.node_lab_run

    [
      call(@fault_drill, :crash_node!, [run, "jido_model_runtime_0"]),
      call(@fault_drill, :disconnect_nodes!, [
        run,
        "mezzanine_workflow_0",
        "jido_model_runtime_0"
      ]),
      call(@fault_drill, :heal_nodes!, [run, "mezzanine_workflow_0", "jido_model_runtime_0"]),
      call(@fault_drill, :delay_facade!, [
        run,
        "jido_model_runtime_0",
        "JidoIntegration.RemoteFacade.ModelRuntime",
        5_001
      ]),
      call(@fault_drill, :inject_stale_dto!, [
        run,
        "seam://mezzanine/jido/model-invocation",
        "fixture://stack_lab/partition_recovery/stale-model-invocation"
      ]),
      call(@fault_drill, :duplicate_submit!, [run, baseline.model_invocation_ref]),
      call(@fault_drill, :kill_exporter!, [run, :aitrace_evidence])
    ]
  end

  defp fault_recovery_status(fault_receipts) do
    if Enum.all?(fault_receipts, &(Map.get(&1, "status") == "pass")),
      do: :pass,
      else: :open_defect
  end

  defp owner_recovery_evidence do
    [
      %{
        "owner" => "citadel",
        "package" => "surfaces/citadel_domain_surface",
        "evidence_ref" => "citadel_domain_surface_fault_injection_and_operability_test",
        "safe_action" => "bounded duplicate, timeout, and dead-letter posture"
      },
      %{
        "owner" => "mezzanine",
        "package" => "core/workflow_runtime",
        "evidence_ref" => "Mezzanine.WorkflowRuntime.TemporalDispatchContract",
        "safe_action" => "workflow start outbox and retry visibility contracts"
      },
      %{
        "owner" => "stack_lab",
        "package" => "examples/pressure_failover_drill",
        "evidence_ref" => "PressureFailoverDrill duplicate_delivery and transport_interruption",
        "safe_action" =>
          "duplicate delivery converges and transport interruption remains pending until replay"
      },
      %{
        "owner" => "aitrace",
        "package" => "AITrace",
        "evidence_ref" => "AITrace.RemoteFacade.Evidence",
        "safe_action" => "export unavailable posture remains bounded"
      }
    ]
  end

  defp json_safe(%_struct{} = value), do: value |> Map.from_struct() |> json_safe()

  defp json_safe(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), json_safe(nested)} end)
  end

  defp json_safe(values) when is_list(values), do: Enum.map(values, &json_safe/1)
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value), do: value

  defp call(module, function, args)
       when is_atom(module) and is_atom(function) and is_list(args) do
    unless Code.ensure_loaded?(module) do
      raise ArgumentError, "required module is unavailable: #{inspect(module)}"
    end

    apply(module, function, args)
  end
end
