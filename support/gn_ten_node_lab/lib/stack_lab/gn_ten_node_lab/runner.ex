defmodule StackLab.GnTenNodeLab.Runner do
  @moduledoc """
  Command-facing topology runner for StackLab gn-ten node-lab tasks.
  """

  alias StackLab.GnTenNodeLab.{BootPlan, Peer, RunState, Topology}

  @schema_version "stack_lab.gn_ten_node_lab.run.v1"

  @spec up(Path.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def up(topology_path, opts \\ []) when is_binary(topology_path) and is_list(opts) do
    started_at = DateTime.utc_now()
    run_id = Keyword.get_lazy(opts, :run_id, &run_id/0)
    state_path = Keyword.get(opts, :state_path, RunState.default_path())
    keep? = Keyword.get(opts, :keep?, false)
    artifact_root = Keyword.get_lazy(opts, :artifact_root, &default_artifact_root/0)

    result =
      with {:ok, topology} <- Topology.load_file(topology_path),
           instances <- BootPlan.instances(topology),
           {:ok, peers} <- start_instances(instances),
           {:ok, boot_receipts} <- boot_instances(peers),
           cleanup <- cleanup_peers(peers) do
        log_artifact = write_log_artifact!(artifact_root, run_id, boot_receipts, cleanup, [])

        {:ok,
         receipt("pass", started_at, run_id, topology, topology_path,
           keep?: keep?,
           boot_receipts: boot_receipts,
           cleanup: cleanup,
           failures: [],
           log_artifact: log_artifact
         )}
      else
        {:error, failures} when is_list(failures) ->
          log_artifact = write_log_artifact!(artifact_root, run_id, [], [], failures)

          {:error,
           failure_receipt(started_at, run_id, topology_path, keep?, failures, [], log_artifact)}

        {:error, failure} ->
          log_artifact = write_log_artifact!(artifact_root, run_id, [], [], [failure])

          {:error,
           failure_receipt(started_at, run_id, topology_path, keep?, [failure], [], log_artifact)}
      end

    maybe_write_state(result, state_path)
  end

  @spec status(keyword()) :: {:ok, map()}
  def status(opts \\ []) when is_list(opts) do
    state_path = Keyword.get(opts, :state_path, RunState.default_path())

    case RunState.read(state_path) do
      {:ok, state} ->
        {:ok,
         %{
           "schema_version" => "stack_lab.gn_ten_node_lab.status.v1",
           "status" => "pass",
           "state_path" => state_path,
           "run_state" => scrub_state(state)
         }}

      {:error, %{code: "no_active_run"}} ->
        {:ok,
         %{
           "schema_version" => "stack_lab.gn_ten_node_lab.status.v1",
           "status" => "no_active_run",
           "state_path" => state_path,
           "run_state" => nil
         }}

      {:error, failure} ->
        {:ok,
         %{
           "schema_version" => "stack_lab.gn_ten_node_lab.status.v1",
           "status" => "error",
           "state_path" => state_path,
           "failures" => [failure]
         }}
    end
  end

  @spec probe(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def probe(node_id, opts \\ []) when is_binary(node_id) and is_list(opts) do
    state_path = Keyword.get(opts, :state_path, RunState.default_path())

    with {:ok, state} <- RunState.read(state_path),
         {:ok, node} <- find_node(state, node_id) do
      {:ok,
       %{
         "schema_version" => "stack_lab.gn_ten_node_lab.probe.v1",
         "status" => "pass",
         "state_path" => state_path,
         "node_id" => node_id,
         "node" => node
       }}
    else
      {:error, failure} ->
        {:error,
         %{
           "schema_version" => "stack_lab.gn_ten_node_lab.probe.v1",
           "status" => "fail",
           "state_path" => state_path,
           "node_id" => node_id,
           "failures" => [failure]
         }}
    end
  end

  @spec down(keyword()) :: {:ok, map()} | {:error, map()}
  def down(opts \\ []) when is_list(opts) do
    state_path = Keyword.get(opts, :state_path, RunState.default_path())

    state =
      case RunState.read(state_path) do
        {:ok, state} -> state
        {:error, _failure} -> nil
      end

    case RunState.delete(state_path) do
      :ok ->
        {:ok,
         %{
           "schema_version" => "stack_lab.gn_ten_node_lab.down.v1",
           "status" => "pass",
           "state_path" => state_path,
           "previous_run_state" => scrub_state(state),
           "cleanup" => %{"state_file_removed?" => true}
         }}

      {:error, reason} ->
        {:error,
         %{
           "schema_version" => "stack_lab.gn_ten_node_lab.down.v1",
           "status" => "fail",
           "state_path" => state_path,
           "failures" => [%{code: "run_state_delete_failed", reason: inspect(reason)}]
         }}
    end
  end

  defp start_instances(instances) do
    instances
    |> Enum.reduce_while({:ok, []}, fn instance, {:ok, peers} ->
      start_instance(instance, peers)
    end)
    |> case do
      {:ok, peers} -> {:ok, Enum.reverse(peers)}
      {:error, failure} -> {:error, failure}
    end
  end

  defp start_instance(instance, peers) do
    case Peer.start(name: peer_name(instance)) do
      {:ok, peer} -> sync_started_peer(instance, peer, peers)
      {:error, failure} -> fail_start(instance, peers, failure)
    end
  end

  defp sync_started_peer(instance, peer, peers) do
    case Peer.sync_code_paths(peer) do
      :ok ->
        {:cont, {:ok, [{instance, peer} | peers]}}

      {:error, reason} ->
        cleanup_peers([{instance, peer} | peers])
        {:halt, {:error, %{code: "code_path_sync_failed", reason: inspect(reason)}}}
    end
  end

  defp fail_start(instance, peers, failure) do
    cleanup_peers(peers)
    {:halt, {:error, Map.put(failure, :node_id, instance.node_id)}}
  end

  defp boot_instances(peers) do
    peers
    |> Enum.reduce_while({:ok, []}, fn {instance, peer}, {:ok, receipts} ->
      case BootPlan.boot_instance(peer, instance) do
        {:ok, receipt} ->
          {:cont,
           {:ok, [Map.put(receipt, "peer_node", Atom.to_string(peer.peer_node)) | receipts]}}

        {:error, failure} ->
          cleanup_peers(peers)
          {:halt, {:error, Map.put(failure, :node_id, instance.node_id)}}
      end
    end)
    |> case do
      {:ok, receipts} -> {:ok, Enum.reverse(receipts)}
      {:error, failure} -> {:error, failure}
    end
  end

  defp cleanup_peers(peers) do
    peers
    |> Enum.map(fn {instance, peer} ->
      peer
      |> Peer.stop()
      |> Map.merge(%{
        "node_id" => instance.node_id,
        "node" => Atom.to_string(peer.peer_node)
      })
    end)
  end

  defp maybe_write_state({status, receipt}, state_path) do
    path = RunState.write!(receipt, state_path)
    {status, Map.put(receipt, "state_path", path)}
  end

  defp receipt(status, started_at, run_id, topology, topology_path, attrs) do
    %{
      "schema_version" => @schema_version,
      "status" => status,
      "run_id" => run_id,
      "topology_path" => topology_path,
      "topology_ref" => topology.topology_ref,
      "node_count" => Topology.node_count(topology),
      "started_at" => DateTime.to_iso8601(started_at),
      "finished_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "keep_requested?" => Keyword.fetch!(attrs, :keep?),
      "peers_kept?" => false,
      "keep_mode" => "phase6_task_receipt_only",
      "keep_note" =>
        "cross-command peer retention requires a later daemon or release-path controller",
      "boot_receipts" => Keyword.fetch!(attrs, :boot_receipts),
      "cleanup" => Keyword.fetch!(attrs, :cleanup),
      "failures" => Keyword.fetch!(attrs, :failures),
      "log_artifact" => Keyword.fetch!(attrs, :log_artifact),
      "cookie_posture" => %{
        "posture" => "generated_or_controller_cookie_redacted",
        "secret_value_present?" => false
      }
    }
  end

  defp failure_receipt(started_at, run_id, topology_path, keep?, failures, cleanup, log_artifact) do
    %{
      "schema_version" => @schema_version,
      "status" => "fail",
      "run_id" => run_id,
      "topology_path" => topology_path,
      "started_at" => DateTime.to_iso8601(started_at),
      "finished_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "keep_requested?" => keep?,
      "peers_kept?" => false,
      "keep_mode" => "phase6_task_receipt_only",
      "failures" => failures,
      "cleanup" => cleanup,
      "log_artifact" => log_artifact,
      "cookie_posture" => %{
        "posture" => "generated_or_controller_cookie_redacted",
        "secret_value_present?" => false
      }
    }
  end

  defp find_node(state, node_id) do
    nodes =
      state
      |> Map.get("boot_receipts", [])
      |> Enum.filter(&(Map.get(&1, "node_id") == node_id))

    case nodes do
      [node | _rest] -> {:ok, Map.get(node, "node")}
      [] -> {:error, %{code: "node_not_found", node_id: node_id}}
    end
  end

  defp scrub_state(nil), do: nil

  defp scrub_state(state) when is_map(state) do
    state
    |> Map.delete("cookie")
    |> Map.delete("cookie_value")
  end

  defp peer_name(instance) do
    suffix = System.unique_integer([:positive, :monotonic])
    :"#{instance.node_id}_#{suffix}"
  end

  defp run_id do
    "run-#{System.system_time(:millisecond)}-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp write_log_artifact!(artifact_root, run_id, boot_receipts, cleanup, failures) do
    log_path = Path.join([artifact_root, safe_path_component(run_id), "logs", "distributed.log"])
    File.mkdir_p!(Path.dirname(log_path))

    lines =
      boot_lines(run_id, boot_receipts) ++
        cleanup_lines(run_id, cleanup) ++
        failure_lines(run_id, failures)

    File.write!(log_path, Enum.join(lines, "\n") <> "\n")

    %{
      "schema_version" => "stack_lab.gn_ten_node_lab.log_artifact.v1",
      "path" => log_path,
      "line_count" => length(lines),
      "redaction" => "cookies_secrets_and_raw_payloads_redacted",
      "contains_cookie?" => false,
      "contains_raw_payload?" => false
    }
  end

  defp boot_lines(run_id, boot_receipts) do
    Enum.map(boot_receipts, fn receipt ->
      log_line(%{
        run_id: run_id,
        profile: Map.get(receipt, "profile", "unknown_profile"),
        node_id: Map.get(receipt, "node_id", "unknown_node"),
        node: Map.get(receipt, "node", "unknown@node"),
        stream: "lifecycle",
        correlation_ref: "corr://#{run_id}/#{Map.get(receipt, "node_id", "unknown_node")}/boot",
        message: "node booted and owner facade readiness passed"
      })
    end)
  end

  defp cleanup_lines(run_id, cleanup) do
    Enum.map(cleanup, fn receipt ->
      log_line(%{
        run_id: run_id,
        profile: "cleanup",
        node_id: Map.get(receipt, "node_id", "unknown_node"),
        node: Map.get(receipt, "node", "unknown@node"),
        stream: "lifecycle",
        correlation_ref:
          "corr://#{run_id}/#{Map.get(receipt, "node_id", "unknown_node")}/cleanup",
        message: "peer stopped and reachability checked"
      })
    end)
  end

  defp failure_lines(run_id, failures) do
    Enum.map(failures, fn failure ->
      log_line(%{
        run_id: run_id,
        profile: "failure",
        node_id:
          to_string(Map.get(failure, :node_id, Map.get(failure, "node_id", "unknown_node"))),
        node: "unknown@node",
        stream: "stderr",
        correlation_ref: "corr://#{run_id}/failure",
        message: "node lab failure #{safe_failure_code(failure)}"
      })
    end)
  end

  defp log_line(attrs) do
    [
      DateTime.utc_now() |> DateTime.to_iso8601(),
      attrs.profile,
      attrs.node_id,
      attrs.node,
      attrs.stream,
      attrs.correlation_ref,
      redact_message(attrs.message)
    ]
    |> Enum.join(" ")
  end

  defp safe_failure_code(failure) when is_map(failure) do
    failure
    |> Map.get(:code, Map.get(failure, "code", "unknown"))
    |> to_string()
    |> redact_message()
  end

  defp redact_message(message) do
    message
    |> to_string()
    |> String.replace(
      ~r/(?i)(cookie|secret|authorization|auth_header|credential)[^ ]*/,
      "[REDACTED]"
    )
    |> String.replace(~r/(?i)(raw_prompt|raw_memory|provider_payload)[^ ]*/, "[REDACTED]")
  end

  defp safe_path_component(value) do
    value
    |> to_string()
    |> String.replace(~r/[^A-Za-z0-9_.-]/, "_")
  end

  defp default_artifact_root do
    Path.join(System.tmp_dir!(), "stack_lab/gn_ten_node_lab")
  end
end
