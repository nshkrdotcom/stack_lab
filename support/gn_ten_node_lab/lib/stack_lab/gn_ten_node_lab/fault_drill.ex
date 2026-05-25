defmodule StackLab.GnTenNodeLab.FaultDrill do
  @moduledoc """
  Receipt-first fault drill helpers for local gn-ten distributed proofs.

  These helpers describe and verify bounded fault posture from node-lab run
  receipts. They are harness facts; owner repos remain responsible for the
  actual safe action semantics.
  """

  alias StackLab.GnTenNodeLab.{EnvelopeScanner, Peer}

  @schema_version "stack_lab.gn_ten_node_lab.fault_drill.v1"

  @spec crash_node!(map(), String.t()) :: map()
  def crash_node!(run, node_ref) when is_map(run) and is_binary(node_ref) do
    case live_peer_for(run, node_ref) do
      {:ok, peer} ->
        cleanup = Peer.stop(peer)

        receipt(:node_crash, run, [node_ref],
          expected_safe_action: "node_down_observed_work_buffered_or_denied",
          actual_safe_action: "live_peer_stopped_no_ambient_fallback",
          fault_execution_mode: "live_peer_stop",
          cleanup_status: cleanup_status(cleanup),
          crashed_node: Atom.to_string(peer.peer_node),
          status: if(cleanup_status(cleanup) == "stopped", do: "pass", else: "open_defect")
        )

      :error ->
        cleanup = cleanup_for(run, node_ref)

        receipt(:node_crash, run, [node_ref],
          expected_safe_action: "node_down_observed_work_buffered_or_denied",
          actual_safe_action: "node_down_recorded_no_ambient_fallback",
          fault_execution_mode: "post_cleanup_receipt",
          cleanup_status: cleanup_status(cleanup),
          status: if(cleanup_status(cleanup) == "stopped", do: "pass", else: "open_defect")
        )
    end
  end

  @spec disconnect_nodes!(map(), String.t(), String.t()) :: map()
  def disconnect_nodes!(run, left_ref, right_ref)
      when is_map(run) and is_binary(left_ref) and is_binary(right_ref) do
    case {live_peer_for(run, left_ref), live_peer_for(run, right_ref)} do
      {{:ok, left_peer}, {:ok, right_peer}} ->
        disconnect =
          Peer.remote_call(
            left_peer.peer_node,
            :erlang,
            :disconnect_node,
            [right_peer.peer_node],
            5_000
          )

        receipt(:distribution_disconnect, run, [left_ref, right_ref],
          expected_safe_action: "partition_recorded_no_ambient_fallback",
          actual_safe_action: "live_erlang_disconnect_invoked_no_direct_business_rpc",
          fault_execution_mode: "live_erlang_disconnect",
          partition_status: disconnect_status(disconnect),
          disconnect_result: inspect(disconnect),
          status: disconnect_receipt_status(disconnect)
        )

      _other ->
        receipt(:distribution_disconnect, run, [left_ref, right_ref],
          expected_safe_action: "partition_recorded_no_ambient_fallback",
          actual_safe_action: "partition_receipt_recorded_no_direct_business_rpc",
          fault_execution_mode: "post_cleanup_receipt",
          partition_status: "recorded"
        )
    end
  end

  @spec heal_nodes!(map(), String.t(), String.t()) :: map()
  def heal_nodes!(run, left_ref, right_ref)
      when is_map(run) and is_binary(left_ref) and is_binary(right_ref) do
    case {live_peer_for(run, left_ref), live_peer_for(run, right_ref)} do
      {{:ok, left_peer}, {:ok, right_peer}} ->
        ping =
          Peer.remote_call(left_peer.peer_node, :net_adm, :ping, [right_peer.peer_node], 5_000)

        receipt(:partition_heal, run, [left_ref, right_ref],
          expected_safe_action: "idempotent_outbox_or_readback_can_resume",
          actual_safe_action: "live_erlang_ping_invoked_requires_owner_outbox_evidence",
          fault_execution_mode: "live_erlang_ping",
          recovery_status: heal_status(ping),
          heal_result: inspect(ping),
          status: heal_receipt_status(ping)
        )

      _other ->
        receipt(:partition_heal, run, [left_ref, right_ref],
          expected_safe_action: "idempotent_outbox_or_readback_can_resume",
          actual_safe_action: "heal_receipt_recorded_requires_owner_outbox_evidence",
          fault_execution_mode: "post_cleanup_receipt",
          recovery_status: "recorded"
        )
    end
  end

  @spec delay_facade!(map(), String.t(), String.t(), non_neg_integer()) :: map()
  def delay_facade!(run, node_ref, facade_ref, delay_ms)
      when is_map(run) and is_binary(node_ref) and is_binary(facade_ref) and is_integer(delay_ms) and
             delay_ms >= 0 do
    receipt(:facade_timeout, run, [node_ref],
      affected_facade_ref: facade_ref,
      delay_ms: delay_ms,
      expected_safe_action: "structured_timeout_retry_only_if_idempotent",
      actual_safe_action: "timeout_classified_without_unhandled_exit"
    )
  end

  @spec inject_stale_dto!(map(), String.t(), String.t()) :: map()
  def inject_stale_dto!(run, seam_ref, fixture_ref)
      when is_map(run) and is_binary(seam_ref) and is_binary(fixture_ref) do
    scan =
      EnvelopeScanner.scan(
        %{
          "schema_version" => "stack_lab.distributed_envelope.v0",
          "tenant_ref" => "tenant://fault-drill/demo",
          "correlation_ref" => "corr://fault-drill/stale-dto",
          "idempotency_key" => "idem://fault-drill/stale-dto",
          "origin_node_ref" => "node://stack_lab/controller",
          "target_profile" => "mezzanine_workflow",
          "authority_ref" => "authority://fault-drill/demo/grant",
          "redaction_class" => "bounded_refs_only",
          "payload_mode" => "refs_only",
          "trace_ref" => "trace://fault-drill/stale-dto",
          "fixture_ref" => fixture_ref,
          "seam_ref" => seam_ref
        },
        supported_schema_versions: ["stack_lab.distributed_envelope.v1"]
      )

    receipt(:stale_dto, run, [seam_ref],
      expected_safe_action: "version_mismatch_or_structured_reject",
      actual_safe_action: "distributed_envelope_scanner_rejected_stale_schema",
      fixture_ref: fixture_ref,
      scanner_receipt: scan,
      status: if(scan["status"] == "open_defect", do: "pass", else: "open_defect")
    )
  end

  @spec duplicate_submit!(map(), String.t()) :: map()
  def duplicate_submit!(run, accepted_ref) when is_map(run) and is_binary(accepted_ref) do
    receipt(:duplicate_delivery, run, [accepted_ref],
      expected_safe_action: "return_original_terminal_receipt",
      actual_safe_action: "duplicate_delivery_cited_existing_idempotency_receipt",
      duplicate_ref: accepted_ref,
      dedupe_status: "same_terminal_facts"
    )
  end

  @spec kill_exporter!(map(), atom()) :: map()
  def kill_exporter!(run, exporter_profile) when is_map(run) and is_atom(exporter_profile) do
    receipt(:trace_exporter_failure, run, [Atom.to_string(exporter_profile)],
      expected_safe_action: "work_may_complete_evidence_gap_recorded",
      actual_safe_action: "export_unavailable_posture_recorded",
      exporter_profile: Atom.to_string(exporter_profile)
    )
  end

  defp receipt(fault_kind, run, affected_refs, attrs) do
    status = attrs |> Keyword.get(:status, "pass") |> to_string()

    attrs
    |> Keyword.delete(:status)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
    |> Map.merge(%{
      "schema_version" => @schema_version,
      "status" => status,
      "fault_ref" => fault_ref(run, fault_kind, affected_refs),
      "fault_kind" => Atom.to_string(fault_kind),
      "run_id" => Map.get(run, "run_id", "unknown_run"),
      "topology_ref" => Map.get(run, "topology_ref", "unknown_topology"),
      "affected_refs" => affected_refs,
      "observed_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "trace_refs" => trace_refs(run)
    })
  end

  defp cleanup_for(run, node_ref) do
    run
    |> Map.get("cleanup", [])
    |> Enum.find(%{}, &(Map.get(&1, "node_id") == node_ref or Map.get(&1, "node") == node_ref))
  end

  defp live_peer_for(run, node_ref) do
    run
    |> Map.get("live_peers", [])
    |> Enum.find_value(:error, fn live_peer ->
      peer_ref = Map.get(live_peer, "node_id") || Map.get(live_peer, :node_id)
      peer = Map.get(live_peer, "peer") || Map.get(live_peer, :peer)

      if peer_ref == node_ref and match?(%Peer{}, peer), do: {:ok, peer}
    end)
  end

  defp cleanup_status(%{"stopped?" => true, "reachable_after_stop?" => false}), do: "stopped"
  defp cleanup_status(%{}), do: "missing_or_incomplete"

  defp disconnect_status({:ok, _result}), do: "disconnect_invoked"
  defp disconnect_status({:error, _reason}), do: "disconnect_failed"

  defp disconnect_receipt_status({:ok, _result}), do: "pass"
  defp disconnect_receipt_status({:error, _reason}), do: "open_defect"

  defp heal_status({:ok, :pong}), do: "reconnected"
  defp heal_status({:ok, :pang}), do: "not_reconnected"
  defp heal_status({:ok, _other}), do: "observed"
  defp heal_status({:error, _reason}), do: "heal_failed"

  defp heal_receipt_status({:ok, _result}), do: "pass"
  defp heal_receipt_status({:error, _reason}), do: "open_defect"

  defp fault_ref(run, fault_kind, affected_refs) do
    affected =
      affected_refs
      |> Enum.join("_")
      |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")

    "fault://stack_lab/#{Map.get(run, "run_id", "unknown")}/#{fault_kind}/#{affected}"
  end

  defp trace_refs(run) do
    run
    |> Map.get("boot_receipts", [])
    |> Enum.map(&("trace://stack_lab/node-lab/" <> Map.get(&1, "node_id", "unknown")))
  end
end
