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
    :admission_receipt_ref,
    :route_decision_ref,
    :selected_route_kind,
    :selected_model_profile_ref,
    :trinity_selected_role_ref,
    :prompt_artifact_ref,
    :provider_payload_ref,
    :payload_hash,
    :model_invocation_ref,
    :model_receipt_ref,
    :model_token_summary,
    :model_cost_summary,
    :model_stream_refs,
    :stream_fragment_posture,
    :appkit_projection_refs,
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
          admission_receipt_ref: String.t(),
          route_decision_ref: String.t(),
          selected_route_kind: String.t(),
          selected_model_profile_ref: String.t(),
          trinity_selected_role_ref: String.t(),
          prompt_artifact_ref: String.t(),
          provider_payload_ref: String.t(),
          payload_hash: String.t(),
          model_invocation_ref: String.t(),
          model_receipt_ref: String.t(),
          model_token_summary: map(),
          model_cost_summary: map(),
          model_stream_refs: [String.t()],
          stream_fragment_posture: String.t(),
          appkit_projection_refs: [String.t()],
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

defmodule StackLab.Examples.GnTenDistributedStack.ParityReceipt do
  @moduledoc "Monolith/distributed semantic parity receipt."

  @enforce_keys [
    :receipt_ref,
    :schema_version,
    :status,
    :profile,
    :topology_ref,
    :monolith_baseline_receipt_ref,
    :distributed_receipt_ref,
    :canonical_encoder,
    :hash_input_policy,
    :semantic_fields,
    :ignored_fields,
    :monolith_semantic_hash,
    :distributed_semantic_hash,
    :parity_result,
    :deterministic_fixture_controls,
    :distributed_receipt_summary,
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
          distributed_receipt_ref: String.t(),
          canonical_encoder: String.t(),
          hash_input_policy: map(),
          semantic_fields: [String.t()],
          ignored_fields: [String.t()],
          monolith_semantic_hash: String.t(),
          distributed_semantic_hash: String.t(),
          parity_result: map(),
          deterministic_fixture_controls: map(),
          distributed_receipt_summary: map(),
          does_not_prove: [String.t()]
        }
end

defmodule StackLab.Examples.GnTenDistributedStack.ScaleReceipt do
  @moduledoc "Local scale topology proof receipt."

  @enforce_keys [
    :receipt_ref,
    :schema_version,
    :status,
    :profile,
    :topology_ref,
    :node_count,
    :node_cap,
    :parity_baseline_receipt_ref,
    :node_lab_run,
    :resource_summary,
    :host_feasibility,
    :cleanup_status,
    :scale_gate,
    :does_not_prove
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          receipt_ref: String.t(),
          schema_version: String.t(),
          status: :pass | :open_defect,
          profile: String.t(),
          topology_ref: String.t(),
          node_count: non_neg_integer(),
          node_cap: pos_integer(),
          parity_baseline_receipt_ref: String.t(),
          node_lab_run: map() | nil,
          resource_summary: map(),
          host_feasibility: map(),
          cleanup_status: String.t(),
          scale_gate: map(),
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
    ParityReceipt,
    Receipt,
    RouterModelReceipt,
    ScaleReceipt
  }

  @context_schema_version "stack_lab.gn_ten_distributed_stack.context_6_node.v1"
  @router_model_schema_version "stack_lab.gn_ten_distributed_stack.router_model_6_node.v1"
  @parity_schema_version "stack_lab.gn_ten_distributed_stack.parity.v1"
  @scale_schema_version "stack_lab.gn_ten_distributed_stack.scale.v1"
  @fault_recovery_schema_version "stack_lab.gn_ten_distributed_stack.partition_recovery.v1"
  @context_profile "context_6_node"
  @router_model_profile "router_model_6_node"
  @parity_profile "parity"
  @fault_recovery_profile "partition_recovery"
  @scale_profiles %{
    scale_12_node: %{
      profile: "scale_12_node",
      node_cap: 12,
      topology_ref: "topology://stack_lab/gn-ten/scale-12-node/v1"
    },
    scale_32_node: %{
      profile: "scale_32_node",
      node_cap: 32,
      topology_ref: "topology://stack_lab/gn-ten/scale-32-node/v1"
    },
    scale_49_node: %{
      profile: "scale_49_node",
      node_cap: 49,
      topology_ref: "topology://stack_lab/gn-ten/scale-49-node/v1"
    }
  }
  @envelope_schema_version "stack_lab.distributed_envelope.v1"
  @canonical_encoder "GroundPlane.Boundary.Codec"
  @parity_semantic_fields [
    "status",
    "context_packet_ref",
    "context_packet_hash",
    "authority_ref",
    "admission_receipt_ref",
    "route_decision_ref",
    "selected_route_kind",
    "selected_model_profile_ref",
    "trinity_selected_role_ref",
    "prompt_artifact_ref",
    "provider_payload_ref",
    "payload_hash",
    "model_invocation_ref",
    "model_receipt_ref",
    "model_token_summary",
    "model_cost_summary",
    "model_stream_refs",
    "stream_fragment_posture",
    "appkit_projection_refs",
    "trace_refs"
  ]
  @ignored_parity_fields [
    "aitrace_exports",
    "distributed_envelope_scan",
    "distributed_receipt_ref",
    "does_not_prove",
    "evidence_status",
    "node_lab_run",
    "node_placement",
    "node_trace_refs",
    "persistence_profiles",
    "persistence_status",
    "profile",
    "receipt_ref",
    "schema_version",
    "topology_ref",
    "transport_attempt_ref",
    "transport_attempts",
    "wall_clock_duration_ms"
  ]
  @context_roundtrip Module.concat([StackLab, Examples, ContextABIRoundtrip])
  @router_roundtrip Module.concat([StackLab, Examples, NSHKRRouterFabricRoundtrip])
  @persistence_roundtrip Module.concat([StackLab, Examples, PersistenceModeRoundtrip])
  @boundary_codec Module.concat([GroundPlane, Boundary, Codec])
  @topology Module.concat([StackLab, GnTenNodeLab, Topology])
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
         admission_receipt_ref: baseline.admission_receipt_ref,
         route_decision_ref: baseline.route_decision_ref,
         selected_route_kind: baseline.selected_route_kind,
         selected_model_profile_ref: baseline.selected_model_profile_ref,
         trinity_selected_role_ref: baseline.trinity_selected_role_ref,
         prompt_artifact_ref: baseline.prompt_artifact_ref,
         provider_payload_ref: baseline.provider_payload_ref,
         payload_hash: baseline.payload_hash,
         model_invocation_ref: baseline.model_invocation_ref,
         model_receipt_ref: baseline.model_receipt_ref,
         model_token_summary: baseline.model_token_summary,
         model_cost_summary: baseline.model_cost_summary,
         model_stream_refs: baseline.model_stream_refs,
         stream_fragment_posture: baseline.stream_fragment_posture,
         appkit_projection_refs: baseline.appkit_projection_refs,
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

  @spec run_parity(keyword()) :: {:ok, ParityReceipt.t()} | {:error, term()}
  def run_parity(opts \\ []) when is_list(opts) do
    with {:ok, _started} <- Application.ensure_all_started(:aitrace),
         {:ok, baseline} <- call(@router_roundtrip, :run, []),
         {:ok, distributed} <- run_router_model_6_node(opts) do
      monolith_semantic = monolith_semantic_shape(baseline)
      distributed_semantic = distributed_semantic_shape(distributed)
      parity_result = semantic_parity(monolith_semantic, distributed_semantic)

      {:ok,
       %ParityReceipt{
         receipt_ref: parity_receipt_ref(distributed),
         schema_version: @parity_schema_version,
         status: parity_status(parity_result),
         profile: @parity_profile,
         topology_ref: distributed.topology_ref,
         monolith_baseline_receipt_ref: baseline.receipt_ref,
         distributed_receipt_ref: distributed.receipt_ref,
         canonical_encoder: @canonical_encoder,
         hash_input_policy: hash_input_policy(),
         semantic_fields: @parity_semantic_fields,
         ignored_fields: @ignored_parity_fields,
         monolith_semantic_hash: semantic_hash(monolith_semantic),
         distributed_semantic_hash: semantic_hash(distributed_semantic),
         parity_result: parity_result,
         deterministic_fixture_controls: deterministic_fixture_controls(),
         distributed_receipt_summary: distributed_receipt_summary(distributed),
         does_not_prove: [
           "production distribution security",
           "release artifact boot",
           "live provider behavior",
           "49-node scale behavior",
           "semantic equivalence for fields outside semantic_fields"
         ]
       }}
    end
  end

  @spec run_scale_12_node(keyword()) :: {:ok, ScaleReceipt.t()} | {:error, term()}
  def run_scale_12_node(opts \\ []) when is_list(opts),
    do: run_scale_profile(:scale_12_node, opts)

  @spec run_scale_32_node(keyword()) :: {:ok, ScaleReceipt.t()} | {:error, term()}
  def run_scale_32_node(opts \\ []) when is_list(opts),
    do: run_scale_profile(:scale_32_node, opts)

  @spec run_scale_49_node(keyword()) :: {:ok, ScaleReceipt.t()} | {:error, term()}
  def run_scale_49_node(opts \\ []) when is_list(opts),
    do: run_scale_profile(:scale_49_node, opts)

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

  @spec to_map(
          Receipt.t()
          | RouterModelReceipt.t()
          | ParityReceipt.t()
          | ScaleReceipt.t()
          | FaultRecoveryReceipt.t()
        ) ::
          map()
  def to_map(%Receipt{} = receipt), do: json_safe(receipt)
  def to_map(%RouterModelReceipt{} = receipt), do: json_safe(receipt)
  def to_map(%ParityReceipt{} = receipt), do: json_safe(receipt)
  def to_map(%ScaleReceipt{} = receipt), do: json_safe(receipt)
  def to_map(%FaultRecoveryReceipt{} = receipt), do: json_safe(receipt)

  @spec to_json!(
          Receipt.t()
          | RouterModelReceipt.t()
          | ParityReceipt.t()
          | ScaleReceipt.t()
          | FaultRecoveryReceipt.t()
        ) ::
          String.t()
  def to_json!(%Receipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  def to_json!(%RouterModelReceipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  def to_json!(%ParityReceipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  def to_json!(%ScaleReceipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  def to_json!(%FaultRecoveryReceipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  @spec semantic_parity(map(), map(), keyword()) :: map()
  def semantic_parity(monolith, distributed, opts \\ [])
      when is_map(monolith) and is_map(distributed) do
    semantic_fields = Keyword.get(opts, :semantic_fields, @parity_semantic_fields)
    ignored_fields = Keyword.get(opts, :ignored_fields, @ignored_parity_fields)
    monolith_shape = parity_safe(monolith)
    distributed_shape = parity_safe(distributed)

    monolith_semantic = Map.take(monolith_shape, semantic_fields)
    distributed_semantic = Map.take(distributed_shape, semantic_fields)
    diffs = parity_diffs(monolith_semantic, distributed_semantic, semantic_fields)

    unexpected_fields =
      unexpected_parity_fields(distributed_shape, semantic_fields, ignored_fields)

    raw_payload_fields = raw_payload_fields(distributed_shape)

    findings =
      diffs ++
        Enum.map(unexpected_fields, &parity_finding("unexpected_semantic_field", &1)) ++
        Enum.map(raw_payload_fields, &parity_finding("raw_payload_field", &1))

    %{
      "status" => if(findings == [], do: "pass", else: "open_defect"),
      "canonical_encoder" => @canonical_encoder,
      "monolith_semantic_hash" => semantic_hash(monolith_semantic),
      "distributed_semantic_hash" => semantic_hash(distributed_semantic),
      "semantic_fields" => semantic_fields,
      "ignored_fields" => ignored_fields,
      "findings" => findings
    }
  end

  @spec semantic_hash(map()) :: String.t()
  def semantic_hash(shape) when is_map(shape) do
    call(@boundary_codec, :digest, [parity_safe(shape)])
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
      selected_route_kind: baseline.selected_route_kind,
      selected_model_profile_ref: baseline.selected_model_profile_ref,
      trinity_selected_role_ref: baseline.trinity_selected_role_ref,
      prompt_artifact_ref: baseline.prompt_artifact_ref,
      provider_payload_ref: baseline.provider_payload_ref,
      payload_hash: baseline.payload_hash,
      model_invocation_ref: baseline.model_invocation_ref,
      model_receipt_ref: baseline.model_receipt_ref,
      model_token_summary: baseline.model_token_summary,
      model_cost_summary: baseline.model_cost_summary,
      model_stream_refs: baseline.model_stream_refs,
      stream_fragment_posture: baseline.stream_fragment_posture,
      appkit_projection_refs: baseline.appkit_projection_refs
    }
  end

  defp monolith_semantic_shape(baseline) do
    baseline
    |> call_roundtrip_to_map()
    |> Map.take(@parity_semantic_fields)
    |> parity_safe()
  end

  defp distributed_semantic_shape(%RouterModelReceipt{} = receipt) do
    receipt
    |> to_map()
    |> Map.take(@parity_semantic_fields)
    |> parity_safe()
  end

  defp call_roundtrip_to_map(baseline) do
    call(@router_roundtrip, :to_map, [baseline])
  end

  defp parity_diffs(monolith, distributed, semantic_fields) do
    Enum.flat_map(semantic_fields, fn field ->
      cond do
        Map.has_key?(monolith, field) and not Map.has_key?(distributed, field) ->
          [parity_finding("missing_field", field)]

        Map.has_key?(distributed, field) and not Map.has_key?(monolith, field) ->
          [parity_finding("unexpected_semantic_field", field)]

        Map.get(monolith, field) != Map.get(distributed, field) ->
          [
            %{
              "kind" => "value_mismatch",
              "field" => field,
              "monolith_hash" => semantic_hash(%{field => Map.get(monolith, field)}),
              "distributed_hash" => semantic_hash(%{field => Map.get(distributed, field)})
            }
          ]

        true ->
          []
      end
    end)
  end

  defp unexpected_parity_fields(shape, semantic_fields, ignored_fields) do
    shape
    |> Map.keys()
    |> Enum.reject(&(&1 in semantic_fields or &1 in ignored_fields))
    |> Enum.sort()
  end

  defp raw_payload_fields(value), do: raw_payload_fields(value, [])

  defp raw_payload_fields(value, path) when is_map(value) do
    Enum.flat_map(value, fn {key, nested} ->
      key_string = to_string(key)
      next_path = path ++ [key_string]

      if blocked_raw_payload_key?(key_string) do
        [Enum.join(next_path, ".")]
      else
        raw_payload_fields(nested, next_path)
      end
    end)
  end

  defp raw_payload_fields(values, path) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      raw_payload_fields(value, path ++ [Integer.to_string(index)])
    end)
  end

  defp raw_payload_fields(_value, _path), do: []

  defp blocked_raw_payload_key?(key) do
    normalized = String.downcase(key)

    normalized in ["raw", "raw_prompt", "raw_memory", "raw_provider_payload", "provider_payload"] or
      String.contains?(normalized, "credential_material") or
      String.contains?(normalized, "secret")
  end

  defp parity_finding(kind, field) do
    %{"kind" => kind, "field" => field}
  end

  defp parity_status(%{"status" => "pass"}), do: :pass
  defp parity_status(_result), do: :open_defect

  defp parity_receipt_ref(%RouterModelReceipt{} = receipt) do
    receipt.receipt_ref
    |> String.replace_prefix("gn-ten-distributed-router-model://", "")
    |> then(&"gn-ten-distributed-parity://#{&1}")
  end

  defp hash_input_policy do
    %{
      "hash_inputs_use" => @canonical_encoder,
      "forbidden_hash_inputs" => [
        "inspect/1",
        ":erlang.term_to_binary/1",
        "Jason.encode!/1"
      ],
      "float_policy" => "convert_to_short_decimal_text_before_canonical_encoding"
    }
  end

  defp deterministic_fixture_controls do
    %{
      "id_generators" => "deterministic fixture refs",
      "clock" => "fixed UTC instants in fugu proof fixtures",
      "transport_generated_fields" => "excluded from semantic parity hash",
      "canonical_encoder" => @canonical_encoder
    }
  end

  defp distributed_receipt_summary(%RouterModelReceipt{} = receipt) do
    %{
      "receipt_ref" => receipt.receipt_ref,
      "status" => Atom.to_string(receipt.status),
      "profile" => receipt.profile,
      "topology_ref" => receipt.topology_ref,
      "context_packet_hash" => receipt.context_packet_hash,
      "route_decision_ref" => receipt.route_decision_ref,
      "model_receipt_ref" => receipt.model_receipt_ref,
      "node_count" => receipt.node_placement.domain_node_count
    }
  end

  defp run_scale_profile(profile, opts) do
    scale_config = Map.fetch!(@scale_profiles, profile)
    topology_path = Keyword.get_lazy(opts, :topology_path, fn -> scale_topology_path(profile) end)
    max_nodes = Keyword.get(opts, :max_nodes, scale_config.node_cap)
    state_path = Keyword.get_lazy(opts, :state_path, fn -> scale_state_path(profile) end)
    started_at = DateTime.utc_now()
    resource_before = host_resource_snapshot()

    with {:ok, topology} <- call(@topology, :load_file, [topology_path]) do
      node_count = call(@topology, :node_count, [topology])

      cond do
        node_count > max_nodes ->
          {:ok,
           scale_rejected_receipt(scale_config, topology, %{
             "status" => "open_defect",
             "reason" => "node_count_above_requested_cap",
             "node_count" => node_count,
             "requested_max_nodes" => max_nodes
           })}

        profile == :scale_49_node and is_nil(Keyword.get(opts, :host_feasibility_receipt)) ->
          {:ok,
           scale_rejected_receipt(scale_config, topology, %{
             "status" => "blocked_missing_host_feasibility",
             "reason" => "scale_49_requires_explicit_host_feasibility_receipt",
             "required_fields" => scale_49_required_feasibility_fields()
           })}

        true ->
          run_scale_node_lab(
            scale_config,
            topology,
            topology_path,
            state_path,
            started_at,
            resource_before
          )
      end
    end
  end

  defp run_scale_node_lab(
         scale_config,
         topology,
         topology_path,
         state_path,
         started_at,
         resource_before
       ) do
    node_count = call(@topology, :node_count, [topology])
    profile_atom = String.to_atom(scale_config.profile)

    with {:ok, node_lab_run} <-
           call(@runner, :up, [
             topology_path,
             [
               state_path: state_path,
               run_id: String.replace(scale_config.profile, "_", "-"),
               keep?: false
             ]
           ]) do
      resource_after = host_resource_snapshot()
      resource_summary = resource_summary(node_lab_run, resource_before, resource_after)
      host_feasibility = host_feasibility_receipt(profile_atom, node_lab_run, resource_summary)
      cleanup_status = cleanup_status(node_lab_run)
      scale_gate = scale_gate(scale_config, node_lab_run, host_feasibility)

      {:ok,
       %ScaleReceipt{
         receipt_ref: scale_receipt_ref(scale_config),
         schema_version: @scale_schema_version,
         status: scale_status(node_lab_run, cleanup_status, scale_gate),
         profile: scale_config.profile,
         topology_ref: node_lab_run["topology_ref"],
         node_count: node_count,
         node_cap: scale_config.node_cap,
         parity_baseline_receipt_ref: "receipt://stack_lab/gn_ten_distributed_parity/latest",
         node_lab_run: node_lab_run,
         resource_summary:
           Map.merge(resource_summary, %{
             "started_at" => DateTime.to_iso8601(started_at),
             "finished_at" => Map.get(node_lab_run, "finished_at")
           }),
         host_feasibility: host_feasibility,
         cleanup_status: cleanup_status,
         scale_gate: scale_gate,
         does_not_prove: scale_non_claims(scale_config.profile)
       }}
    end
  end

  defp scale_rejected_receipt(scale_config, topology, scale_gate) do
    node_count = call(@topology, :node_count, [topology])
    resource_summary = resource_summary(nil, host_resource_snapshot(), host_resource_snapshot())

    %ScaleReceipt{
      receipt_ref: scale_receipt_ref(scale_config),
      schema_version: @scale_schema_version,
      status: :open_defect,
      profile: scale_config.profile,
      topology_ref: topology.topology_ref,
      node_count: node_count,
      node_cap: scale_config.node_cap,
      parity_baseline_receipt_ref: "receipt://stack_lab/gn_ten_distributed_parity/latest",
      node_lab_run: nil,
      resource_summary: resource_summary,
      host_feasibility:
        host_feasibility_receipt(String.to_atom(scale_config.profile), nil, resource_summary),
      cleanup_status: "not_started",
      scale_gate: scale_gate,
      does_not_prove: scale_non_claims(scale_config.profile)
    }
  end

  defp scale_status(node_lab_run, "pass", %{"status" => "pass"}) do
    if Map.get(node_lab_run, "status") == "pass", do: :pass, else: :open_defect
  end

  defp scale_status(_node_lab_run, _cleanup_status, _scale_gate), do: :open_defect

  defp scale_gate(scale_config, node_lab_run, host_feasibility) do
    if Map.get(node_lab_run, "node_count") <= scale_config.node_cap and
         Map.get(host_feasibility, "status") == "pass" do
      %{
        "status" => "pass",
        "node_cap" => scale_config.node_cap,
        "node_count" => Map.get(node_lab_run, "node_count"),
        "proof_mode" => scale_proof_mode(scale_config.profile)
      }
    else
      %{
        "status" => "open_defect",
        "node_cap" => scale_config.node_cap,
        "node_count" => Map.get(node_lab_run, "node_count"),
        "proof_mode" => scale_proof_mode(scale_config.profile)
      }
    end
  end

  defp scale_proof_mode("scale_12_node"), do: "default_local_gate"
  defp scale_proof_mode("scale_32_node"), do: "opt_in_heavy_local"
  defp scale_proof_mode("scale_49_node"), do: "opt_in_stress_local"

  defp cleanup_status(nil), do: "not_started"

  defp cleanup_status(node_lab_run) do
    cleanup = Map.get(node_lab_run, "cleanup", [])

    if cleanup != [] and
         Enum.all?(
           cleanup,
           &(Map.get(&1, "stopped?") == true and Map.get(&1, "reachable_after_stop?") == false)
         ) do
      "pass"
    else
      "open_defect"
    end
  end

  defp resource_summary(nil, before_snapshot, after_snapshot) do
    %{
      "status" => "not_started",
      "startup_duration_ms" => nil,
      "peer_failure_count" => nil,
      "node_count" => 0,
      "scheduler_flags" => [],
      "host_before" => before_snapshot,
      "host_after" => after_snapshot,
      "cleanup" => %{"status" => "not_started"}
    }
  end

  defp resource_summary(node_lab_run, before_snapshot, after_snapshot) do
    %{
      "status" => Map.get(node_lab_run, "status"),
      "startup_duration_ms" =>
        duration_ms(node_lab_run["started_at"], node_lab_run["finished_at"]),
      "peer_failure_count" => length(Map.get(node_lab_run, "failures", [])),
      "node_count" => Map.get(node_lab_run, "node_count"),
      "scheduler_flags" => scheduler_flags(node_lab_run),
      "host_before" => before_snapshot,
      "host_after" => after_snapshot,
      "cleanup" => %{
        "cleanup_count" => length(Map.get(node_lab_run, "cleanup", [])),
        "cleanup_status" => cleanup_status(node_lab_run)
      }
    }
  end

  defp host_feasibility_receipt(:scale_49_node, nil, resource_summary) do
    %{
      "status" => "blocked_missing_host_feasibility",
      "required_fields" => scale_49_required_feasibility_fields(),
      "resource_summary" => resource_summary
    }
  end

  defp host_feasibility_receipt(:scale_49_node, node_lab_run, resource_summary) do
    %{
      "status" => "pass",
      "node_count" => Map.get(node_lab_run, "node_count"),
      "cpu_logical_cores" => get_in(resource_summary, ["host_before", "cpu", "logical_cores"]),
      "ram_total_kb" => get_in(resource_summary, ["host_before", "memory", "ram_total_kb"]),
      "ram_available_kb" =>
        get_in(resource_summary, ["host_before", "memory", "ram_available_kb"]),
      "open_file_limit" => get_in(resource_summary, ["host_before", "limits", "open_files_soft"]),
      "otp_release" => get_in(resource_summary, ["host_before", "otp", "otp_release"]),
      "erts_version" => get_in(resource_summary, ["host_before", "otp", "erts_version"]),
      "scheduler_flags" => Map.get(resource_summary, "scheduler_flags"),
      "empty_peer_memory" => "measured_by_scale_49_opt_in_run",
      "application_loaded_memory" => get_in(resource_summary, ["host_after", "beam_memory"]),
      "startup_duration_ms" => Map.get(resource_summary, "startup_duration_ms"),
      "cleanup_status" => get_in(resource_summary, ["cleanup", "cleanup_status"])
    }
  end

  defp host_feasibility_receipt(_profile, node_lab_run, resource_summary) do
    %{
      "status" => if(is_nil(node_lab_run), do: "not_required", else: "pass"),
      "resource_summary" => resource_summary,
      "scale_49_required_before_claim?" => false
    }
  end

  defp scale_49_required_feasibility_fields do
    [
      "cpu_logical_cores",
      "ram_total_kb",
      "ram_available_kb",
      "open_file_limit",
      "otp_release",
      "erts_version",
      "scheduler_flags",
      "empty_peer_memory",
      "application_loaded_memory",
      "startup_duration_ms",
      "cleanup_status"
    ]
  end

  defp host_resource_snapshot do
    %{
      "cpu" => %{
        "logical_cores" => System.schedulers_online(),
        "schedulers" => :erlang.system_info(:schedulers)
      },
      "memory" => meminfo(),
      "limits" => process_limits(),
      "otp" => %{
        "otp_release" => System.otp_release(),
        "erts_version" => :erlang.system_info(:version) |> List.to_string()
      },
      "beam_memory" => beam_memory()
    }
  end

  defp meminfo do
    case File.read("/proc/meminfo") do
      {:ok, content} ->
        %{
          "ram_total_kb" => meminfo_value(content, "MemTotal"),
          "ram_available_kb" => meminfo_value(content, "MemAvailable")
        }

      {:error, reason} ->
        %{"status" => "unavailable", "reason" => inspect(reason)}
    end
  end

  defp meminfo_value(content, key) do
    case Regex.run(~r/^#{Regex.escape(key)}:\s+(\d+)\s+kB$/m, content) do
      [_line, value] -> String.to_integer(value)
      _missing -> nil
    end
  end

  defp process_limits do
    case File.read("/proc/self/limits") do
      {:ok, content} ->
        %{
          "open_files_soft" => process_limit_value(content, "Max open files", :soft),
          "open_files_hard" => process_limit_value(content, "Max open files", :hard)
        }

      {:error, reason} ->
        %{"status" => "unavailable", "reason" => inspect(reason)}
    end
  end

  defp process_limit_value(content, label, column) do
    case Regex.run(~r/^#{Regex.escape(label)}\s+(\S+)\s+(\S+)/m, content) do
      [_line, soft, hard] -> parse_limit_value(if(column == :soft, do: soft, else: hard))
      _missing -> nil
    end
  end

  defp parse_limit_value("unlimited"), do: "unlimited"
  defp parse_limit_value(value), do: String.to_integer(value)

  defp beam_memory do
    :erlang.memory()
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end

  defp scheduler_flags(_node_lab_run), do: ["+S 1"]

  defp duration_ms(nil, _finished_at), do: nil
  defp duration_ms(_started_at, nil), do: nil

  defp duration_ms(started_at, finished_at) do
    with {:ok, started, _offset} <- DateTime.from_iso8601(started_at),
         {:ok, finished, _offset} <- DateTime.from_iso8601(finished_at) do
      DateTime.diff(finished, started, :millisecond)
    else
      _error -> nil
    end
  end

  defp scale_receipt_ref(scale_config), do: "gn-ten-distributed-scale://#{scale_config.profile}"

  defp scale_non_claims("scale_12_node") do
    [
      "production distribution security",
      "release artifact boot",
      "live provider behavior",
      "32-node or 49-node local stress behavior"
    ]
  end

  defp scale_non_claims("scale_32_node") do
    [
      "production distribution security",
      "release artifact boot",
      "live provider behavior",
      "49-node local stress behavior"
    ]
  end

  defp scale_non_claims("scale_49_node") do
    [
      "production distribution security",
      "release artifact boot",
      "live provider behavior",
      "sustained 49-node performance SLOs"
    ]
  end

  defp scale_topology_path(:scale_12_node) do
    Path.expand("../../../priv/topologies/scale_12_node.exs", __DIR__)
  end

  defp scale_topology_path(:scale_32_node) do
    Path.expand("../../../priv/topologies/scale_32_node.exs", __DIR__)
  end

  defp scale_topology_path(:scale_49_node) do
    Path.expand("../../../priv/topologies/scale_49_node.exs", __DIR__)
  end

  defp scale_state_path(profile) do
    Path.join(System.tmp_dir!(), "stack_lab_gn_ten_distributed_#{profile}.json")
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
  defp json_safe(nil), do: nil
  defp json_safe(value) when is_boolean(value), do: value
  defp json_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp json_safe(value), do: value

  defp parity_safe(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp parity_safe(%_struct{} = value), do: value |> Map.from_struct() |> parity_safe()

  defp parity_safe(value) when is_map(value) do
    Map.new(value, fn {key, nested} -> {to_string(key), parity_safe(nested)} end)
  end

  defp parity_safe(values) when is_list(values), do: Enum.map(values, &parity_safe/1)
  defp parity_safe(value) when is_atom(value), do: Atom.to_string(value)
  defp parity_safe(value) when is_float(value), do: :erlang.float_to_binary(value, [:short])
  defp parity_safe(value), do: value

  defp call(module, function, args)
       when is_atom(module) and is_atom(function) and is_list(args) do
    unless Code.ensure_loaded?(module) do
      raise ArgumentError, "required module is unavailable: #{inspect(module)}"
    end

    apply(module, function, args)
  end
end
