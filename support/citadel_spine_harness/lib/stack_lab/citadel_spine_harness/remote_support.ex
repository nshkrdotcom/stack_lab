defmodule StackLab.CitadelSpineHarness.RemoteSupport do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.BoundedNames
  alias StackLab.CitadelSpineHarness.RemoteSpine

  @default_timeout_ms 5_000
  @startup_timeout_ms 20_000

  @type remote_spine :: %{
          required(:peer_pid) => pid(),
          required(:peer_monitor_ref) => reference(),
          required(:remote_node) => node(),
          required(:storage_dir) => String.t()
        }

  @spec start_remote_spine!(atom()) :: remote_spine()
  def start_remote_spine!(case_name) when is_atom(case_name) do
    ensure_distribution_started!()
    _ = Application.ensure_all_started(:telemetry)
    {:ok, peer_pid, remote_node} = start_peer(case_name)
    peer_monitor_ref = Process.monitor(peer_pid)
    storage_dir = remote_store_local_dir(case_name)

    remote = %{
      peer_pid: peer_pid,
      peer_monitor_ref: peer_monitor_ref,
      remote_node: remote_node,
      storage_dir: storage_dir
    }

    try do
      :ok = wait_for_remote_node!(remote_node)
      :ok = sync_remote_code_paths!(remote_node)
      :ok = wait_for_remote_spine!(remote_node)

      :ok =
        remote_call!(
          remote_node,
          RemoteSpine,
          :configure_store_local!,
          [storage_dir],
          @startup_timeout_ms
        )

      remote
    rescue
      error ->
        _ = stop_remote_spine(remote)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        _ = stop_remote_spine(remote)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @spec stop_remote_spine(remote_spine()) :: :ok
  def stop_remote_spine(
        %{peer_pid: peer_pid, remote_node: remote_node, storage_dir: storage_dir} = remote
      ) do
    _ = remote_call(remote_node, RemoteSpine, :cleanup_store_local, [storage_dir])
    demonitor_peer(remote)

    if Process.alive?(peer_pid) do
      _ = :peer.stop(peer_pid)
    end

    File.rm_rf(storage_dir)
    :ok
  end

  @spec ensure_distribution_started() :: :ok | {:error, term()}
  def ensure_distribution_started do
    if Node.alive?() do
      :ok
    else
      start_distribution([])
    end
  end

  @spec ensure_distribution_started!() :: :ok
  def ensure_distribution_started! do
    case ensure_distribution_started() do
      :ok ->
        :ok

      {:error, reason} ->
        raise distribution_start_error_message(reason)
    end
  end

  @spec distribution_start_error_message(term()) :: String.t()
  def distribution_start_error_message({:distribution_start_failed, attempts}) do
    "unable to start local distributed node after #{length(attempts)} generated name attempts: #{inspect(attempts)}"
  end

  def distribution_start_error_message(reason) do
    "unable to start local distributed node: #{inspect(reason)}"
  end

  @spec remote_call!(node(), module(), atom(), [term()]) :: term()
  def remote_call!(node, module, function, args) do
    remote_call!(node, module, function, args, @default_timeout_ms)
  end

  @spec remote_call!(node(), module(), atom(), [term()], timeout()) :: term()
  def remote_call!(node, module, function, args, timeout_ms) when is_integer(timeout_ms) do
    case remote_call(node, module, function, args, timeout_ms) do
      {:ok, value} ->
        value

      {:error, reason} ->
        raise "remote call failed for #{inspect(module)}.#{function}/#{length(args)}: #{inspect(reason)}"
    end
  end

  @spec remote_call(node(), module(), atom(), [term()]) :: {:ok, term()} | {:error, term()}
  def remote_call(node, module, function, args) do
    remote_call(node, module, function, args, @default_timeout_ms)
  end

  @spec remote_call(node(), module(), atom(), [term()], timeout()) ::
          {:ok, term()} | {:error, term()}
  def remote_call(node, module, function, args, timeout_ms) when is_integer(timeout_ms) do
    {:ok, :erpc.call(node, module, function, args, timeout_ms)}
  rescue
    error in ErlangError -> {:error, normalize_erpc_error(error.original)}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec sync_remote_code_paths!(node()) :: :ok
  def sync_remote_code_paths!(remote_node) do
    paths = :code.get_path()

    case :erpc.call(remote_node, :code, :add_paths, [paths], 5_000) do
      :ok -> :ok
      true -> :ok
      {:error, reason} -> raise "unable to add code paths on remote node: #{inspect(reason)}"
      other -> raise "unexpected remote code-path result: #{inspect(other)}"
    end
  catch
    :exit, reason ->
      raise "unable to synchronize remote code paths: #{inspect(reason)}"
  end

  @spec remote_store_local_dir(atom()) :: String.t()
  def remote_store_local_dir(case_name) do
    Path.join(
      System.tmp_dir!(),
      "stack_lab_citadel_spine_remote_store_local_#{case_name}_#{System.unique_integer([:positive])}"
    )
  end

  defp start_peer(case_name) do
    case :peer.start_link(%{name: BoundedNames.peer_node_name(case_name)}) do
      {:ok, _peer_pid, _remote_node} = peer -> peer
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_distribution(failures) when length(failures) >= 128 do
    {:error, {:distribution_start_failed, Enum.reverse(failures)}}
  end

  defp start_distribution(failures) do
    name = BoundedNames.local_node_name()

    case Node.start(name, name_domain: :shortnames) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> start_distribution([{name, reason} | failures])
    end
  end

  defp wait_for_remote_node!(remote_node) do
    Node.monitor(remote_node, true)

    try do
      :ok =
        retry_until!("remote node #{inspect(remote_node)} did not become reachable in time", fn ->
          case remote_call(remote_node, :erlang, :node, []) do
            {:ok, ^remote_node} -> :ok
            other -> {:retry, other}
          end
        end)
    after
      Node.monitor(remote_node, false)
      flush_node_monitor(remote_node)
    end
  end

  defp wait_for_remote_spine!(remote_node) do
    retry_until!("remote spine service did not become callable in time", fn ->
      case remote_call(remote_node, RemoteSpine, :ping, []) do
        {:ok, :ok} -> :ok
        other -> {:retry, other}
      end
    end)
  end

  defp retry_until!(message, fun) do
    deadline = System.monotonic_time(:millisecond) + @startup_timeout_ms
    retry_until!(message, fun, deadline)
  end

  defp retry_until!(message, fun, deadline) do
    case fun.() do
      :ok ->
        :ok

      {:retry, result} ->
        remaining_ms = deadline - System.monotonic_time(:millisecond)

        if remaining_ms <= 0 do
          raise "#{message}; last result: #{inspect(result)}"
        else
          ref = make_ref()
          Process.send_after(self(), {:remote_support_retry, ref}, min(25, remaining_ms))

          receive do
            {:nodeup, _node} ->
              retry_until!(message, fun, deadline)

            {:remote_support_retry, ^ref} ->
              retry_until!(message, fun, deadline)
          after
            remaining_ms ->
              raise "#{message}; last result: #{inspect(result)}"
          end
        end
    end
  end

  defp demonitor_peer(%{peer_monitor_ref: peer_monitor_ref})
       when is_reference(peer_monitor_ref) do
    Process.demonitor(peer_monitor_ref, [:flush])
  end

  defp demonitor_peer(_remote), do: :ok

  defp flush_node_monitor(remote_node) do
    receive do
      {:nodeup, ^remote_node} -> flush_node_monitor(remote_node)
      {:nodedown, ^remote_node} -> flush_node_monitor(remote_node)
    after
      0 -> :ok
    end
  end

  defp normalize_erpc_error({:erpc, _reason} = reason), do: reason
  defp normalize_erpc_error(reason), do: {:erpc, reason}
end
