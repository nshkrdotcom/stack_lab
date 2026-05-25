defmodule StackLab.GnTenNodeLab.Peer do
  @moduledoc """
  Local peer lifecycle helpers for node-lab proofs.
  """

  alias StackLab.CommandRunner

  @remote_call_timeout_ms 5_000

  @enforce_keys [:peer_pid, :peer_node, :peer_name]
  defstruct [:peer_pid, :peer_node, :peer_name]

  @type t :: %__MODULE__{peer_pid: pid(), peer_node: node(), peer_name: atom()}

  @spec ensure_epmd_started() :: {:ok, map()} | {:error, map()}
  def ensure_epmd_started do
    case System.find_executable("epmd") do
      nil ->
        {:error, failure("epmd_not_found")}

      epmd ->
        case CommandRunner.run(epmd, ["-daemon"], timeout_ms: 5_000) do
          {:ok, receipt} ->
            {:ok, %{"path" => epmd, "command" => command_summary(receipt)}}

          {:error, receipt} ->
            {:error, failure("epmd_start_failed", command: command_summary(receipt))}
        end
    end
  end

  @spec ensure_distribution_started() :: {:ok, map()} | {:error, map()}
  def ensure_distribution_started do
    if Node.alive?(),
      do: {:ok, distribution_receipt(false)},
      else: start_controller_distribution()
  end

  @spec with_peer((t() -> term()), keyword()) :: {:ok, term()} | {:error, map()}
  def with_peer(fun, opts \\ []) when is_function(fun, 1) and is_list(opts) do
    with {:ok, _epmd} <- ensure_epmd_started(),
         {:ok, _distribution} <- ensure_distribution_started(),
         {:ok, peer} <- start_peer(opts) do
      run_with_cleanup(peer, fun)
    end
  end

  @spec start(keyword()) :: {:ok, t()} | {:error, map()}
  def start(opts \\ []) when is_list(opts) do
    with {:ok, _epmd} <- ensure_epmd_started(),
         {:ok, _distribution} <- ensure_distribution_started() do
      start_peer(opts)
    end
  end

  @spec stop(t()) :: map()
  def stop(%__MODULE__{} = peer), do: cleanup(peer)

  @spec remote_call(t() | node(), module(), atom(), [term()], timeout()) ::
          {:ok, term()} | {:error, term()}
  def remote_call(target, module, function, args),
    do: remote_call(target, module, function, args, @remote_call_timeout_ms)

  def remote_call(%__MODULE__{peer_node: peer_node}, module, function, args, timeout_ms) do
    remote_call(peer_node, module, function, args, timeout_ms)
  end

  def remote_call(peer_node, module, function, args, timeout_ms) when is_atom(peer_node) do
    {:ok, :erpc.call(peer_node, module, function, args, timeout_ms)}
  rescue
    error in ErlangError -> {:error, normalize_erpc_error(error.original)}
  catch
    :exit, reason -> {:error, reason}
  end

  @spec sync_code_paths(t() | node()) :: :ok | {:error, term()}
  def sync_code_paths(%__MODULE__{peer_node: peer_node}), do: sync_code_paths(peer_node)

  def sync_code_paths(peer_node) when is_atom(peer_node) do
    case remote_call(peer_node, :code, :add_paths, [:code.get_path()]) do
      {:ok, :ok} -> :ok
      {:ok, true} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, other} -> {:error, {:unexpected_code_path_result, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec cleanup(t()) :: map()
  def cleanup(%__MODULE__{peer_pid: peer_pid, peer_node: peer_node}) do
    if Process.alive?(peer_pid) do
      _ = :peer.stop(peer_pid)
    end

    %{
      "stopped?" => not Process.alive?(peer_pid),
      "reachable_after_stop?" => :net_adm.ping(peer_node) == :pong
    }
  end

  @spec generated_node_name(:controller | :peer) :: atom()
  def generated_node_name(kind) when kind in [:controller, :peer] do
    :"stack_lab_node_lab_#{kind}_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp start_controller_distribution do
    node_name = generated_node_name(:controller)

    case Node.start(node_name, name_domain: :shortnames) do
      {:ok, _pid} -> {:ok, distribution_receipt(true)}
      {:error, {:already_started, _pid}} -> {:ok, distribution_receipt(false)}
      {:error, reason} -> {:error, failure("distribution_start_failed", reason: inspect(reason))}
    end
  end

  defp start_peer(opts) do
    peer_name = Keyword.get_lazy(opts, :name, fn -> generated_node_name(:peer) end)

    case :peer.start_link(%{name: peer_name}) do
      {:ok, peer_pid, peer_node} ->
        {:ok, %__MODULE__{peer_pid: peer_pid, peer_node: peer_node, peer_name: peer_name}}

      {:error, reason} ->
        {:error, failure("peer_start_failed", reason: inspect(reason))}
    end
  end

  defp run_with_cleanup(%__MODULE__{} = peer, fun) do
    value = fun.(peer)
    cleanup = cleanup(peer)

    if cleanup["stopped?"] do
      {:ok, value}
    else
      {:error, failure("peer_cleanup_failed", cleanup: cleanup)}
    end
  rescue
    exception ->
      {:error,
       failure("peer_callback_failed",
         exception: inspect(exception.__struct__),
         message: Exception.message(exception),
         cleanup: cleanup(peer)
       )}
  catch
    kind, reason ->
      {:error,
       failure("peer_callback_failed",
         kind: kind,
         reason: inspect(reason),
         cleanup: cleanup(peer)
       )}
  end

  defp distribution_receipt(started_by_node_lab?) do
    %{
      "node_alive?" => true,
      "node_name" => Atom.to_string(Node.self()),
      "started_by_node_lab?" => started_by_node_lab?
    }
  end

  defp command_summary(%CommandRunner.Receipt{} = receipt) do
    %{
      "command" => receipt.command,
      "args" => receipt.args,
      "status" => Atom.to_string(receipt.status),
      "exit_status" => receipt.exit_status,
      "duration_ms" => receipt.duration_ms
    }
  end

  defp failure(code, details \\ []) do
    Enum.into(details, %{code: code})
  end

  defp normalize_erpc_error({:erpc, _reason} = reason), do: reason
  defp normalize_erpc_error(reason), do: {:erpc, reason}
end
