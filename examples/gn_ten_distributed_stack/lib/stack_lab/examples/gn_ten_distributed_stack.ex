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
          node_lab_run: map(),
          distributed_envelope_scan: map(),
          node_placement: map(),
          does_not_prove: [String.t()]
        }
end

defmodule StackLab.Examples.GnTenDistributedStack do
  @moduledoc """
  Local distributed gn-ten proof scenarios.
  """

  alias StackLab.Examples.GnTenDistributedStack.Receipt

  @schema_version "stack_lab.gn_ten_distributed_stack.context_6_node.v1"
  @profile "context_6_node"
  @envelope_schema_version "stack_lab.distributed_envelope.v1"
  @context_roundtrip Module.concat([StackLab, Examples, ContextABIRoundtrip])
  @envelope_scanner Module.concat([StackLab, GnTenNodeLab, EnvelopeScanner])
  @runner Module.concat([StackLab, GnTenNodeLab, Runner])
  @json Module.concat([Jason])

  @spec run_context_6_node(keyword()) :: {:ok, Receipt.t()} | {:error, term()}
  def run_context_6_node(opts \\ []) when is_list(opts) do
    topology_path = Keyword.get_lazy(opts, :topology_path, &default_context_topology_path/0)
    state_path = Keyword.get_lazy(opts, :state_path, &default_state_path/0)

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

      {:ok,
       %Receipt{
         receipt_ref: receipt_ref(baseline),
         schema_version: @schema_version,
         status: status(baseline, node_lab_run, envelope_scan),
         profile: @profile,
         topology_ref: node_lab_run["topology_ref"],
         monolith_baseline_receipt_ref: baseline.receipt_ref,
         context_packet_ref: baseline.context_packet_ref,
         context_packet_hash: baseline.context_packet_hash,
         authority_ref: baseline.authority_ref,
         trace_refs: baseline.trace_refs,
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

  @spec to_map(Receipt.t()) :: map()
  def to_map(%Receipt{} = receipt), do: json_safe(receipt)

  @spec to_json!(Receipt.t()) :: String.t()
  def to_json!(%Receipt{} = receipt) do
    call(@json, :encode!, [to_map(receipt), [pretty: true]])
  end

  defp envelopes(baseline, node_lab_run) do
    node_lab_run
    |> Map.fetch!("boot_receipts")
    |> Enum.map(fn node ->
      %{
        envelope_ref: "distributed-envelope://#{node["node_id"]}",
        schema_version: @envelope_schema_version,
        tenant_ref: "tenant://context-abi/demo",
        correlation_ref: "corr://context-abi/distributed/#{node["node_id"]}",
        idempotency_key: "idem://context-abi/distributed/#{node["node_id"]}",
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
    end)
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

  defp status(baseline, node_lab_run, envelope_scan) do
    if baseline.status == :pass and node_lab_run["status"] == "pass" and
         envelope_scan["status"] == "pass" do
      :pass
    else
      :open_defect
    end
  end

  defp receipt_ref(baseline) do
    suffix =
      baseline.context_packet_hash
      |> String.replace_prefix("sha256:", "")
      |> String.slice(0, 16)

    "gn-ten-distributed-context://#{suffix}"
  end

  defp default_context_topology_path do
    Path.expand("../../../priv/topologies/context_6_node.exs", __DIR__)
  end

  defp default_state_path do
    Path.join(System.tmp_dir!(), "stack_lab_gn_ten_distributed_context_6_node.json")
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
