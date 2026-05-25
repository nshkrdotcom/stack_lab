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

    result =
      with {:ok, topology} <- Topology.load_file(topology_path),
           instances <- BootPlan.instances(topology),
           {:ok, peers} <- start_instances(instances),
           {:ok, boot_receipts} <- boot_instances(peers),
           cleanup <- cleanup_peers(peers) do
        {:ok,
         receipt("pass", started_at, run_id, topology, topology_path,
           keep?: keep?,
           boot_receipts: boot_receipts,
           cleanup: cleanup,
           failures: []
         )}
      else
        {:error, failures} when is_list(failures) ->
          {:error, failure_receipt(started_at, run_id, topology_path, keep?, failures, [])}

        {:error, failure} ->
          {:error, failure_receipt(started_at, run_id, topology_path, keep?, [failure], [])}
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
      "cookie_posture" => %{
        "posture" => "generated_or_controller_cookie_redacted",
        "secret_value_present?" => false
      }
    }
  end

  defp failure_receipt(started_at, run_id, topology_path, keep?, failures, cleanup) do
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
end
