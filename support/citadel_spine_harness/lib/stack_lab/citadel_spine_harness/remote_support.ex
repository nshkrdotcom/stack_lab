defmodule StackLab.CitadelSpineHarness.RemoteSupport do
  @moduledoc false

  alias StackLab.CitadelSpineHarness.RemoteSpine

  @default_timeout_ms 5_000
  @startup_timeout_ms 20_000

  @type remote_spine :: %{
          required(:peer_pid) => pid(),
          required(:remote_node) => node(),
          required(:storage_dir) => String.t()
        }

  @spec start_remote_spine!(atom()) :: remote_spine()
  def start_remote_spine!(case_name) when is_atom(case_name) do
    ensure_distribution_started!()
    {:ok, peer_pid, remote_node} = :peer.start_link(%{name: unique_name(:stack_lab_spine)})
    storage_dir = remote_store_local_dir(case_name)

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

    %{
      peer_pid: peer_pid,
      remote_node: remote_node,
      storage_dir: storage_dir
    }
  end

  @spec stop_remote_spine(remote_spine()) :: :ok
  def stop_remote_spine(%{peer_pid: peer_pid, remote_node: remote_node, storage_dir: storage_dir}) do
    _ = remote_call(remote_node, RemoteSpine, :cleanup_store_local, [storage_dir])

    if Process.alive?(peer_pid) do
      :ok = :peer.stop(peer_pid)
    end

    :ok
  end

  @spec ensure_distribution_started() :: :ok | {:error, term()}
  def ensure_distribution_started do
    if Node.alive?() do
      :ok
    else
      case Node.start(unique_name(:stack_lab_local), name_domain: :shortnames) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
        {:error, reason} -> {:error, reason}
      end
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

  @spec unique_name(atom()) :: atom()
  def unique_name(prefix) do
    token =
      :erlang.phash2(
        {:os.getpid(), System.unique_integer([:positive]), System.monotonic_time(), make_ref()},
        1_000_000_000
      )

    :"#{prefix}_#{token}"
  end

  defp wait_for_remote_node!(remote_node, attempts \\ 40)

  defp wait_for_remote_node!(_remote_node, 0) do
    raise "remote node did not become reachable in time"
  end

  defp wait_for_remote_node!(remote_node, attempts) do
    case remote_call(remote_node, :erlang, :node, []) do
      {:ok, ^remote_node} ->
        :ok

      _other ->
        Process.sleep(25)
        wait_for_remote_node!(remote_node, attempts - 1)
    end
  end

  defp wait_for_remote_spine!(remote_node, attempts \\ 80)

  defp wait_for_remote_spine!(_remote_node, 0) do
    raise "remote spine service did not become callable in time"
  end

  defp wait_for_remote_spine!(remote_node, attempts) do
    case remote_call(remote_node, RemoteSpine, :ping, []) do
      {:ok, :ok} ->
        :ok

      _other ->
        Process.sleep(25)
        wait_for_remote_spine!(remote_node, attempts - 1)
    end
  end

  defp normalize_erpc_error({:erpc, _reason} = reason), do: reason
  defp normalize_erpc_error(reason), do: {:erpc, reason}
end
