defmodule StackLab.GnTenNodeLab.Preflight do
  @moduledoc """
  Node-lab preflight receipt generation.
  """

  alias StackLab.GnTenNodeLab.{Cookie, Peer}

  @schema_version "stack_lab.gn_ten_node_lab.preflight.v1"
  @receipt_ref "receipt://stack_lab/gn_ten_node_lab_preflight/latest"

  @spec run(keyword()) :: {:ok, map()} | {:error, map()}
  def run(opts \\ []) when is_list(opts) do
    cookie = Keyword.get_lazy(opts, :cookie, &Cookie.generate/0)
    started_at = DateTime.utc_now()

    result =
      with {:ok, epmd} <- Peer.ensure_epmd_started(),
           {:ok, distribution} <- Peer.ensure_distribution_started(),
           {:ok, peer_probe} <- peer_probe() do
        {:ok,
         receipt("pass", started_at, epmd, distribution, Cookie.posture(cookie), peer_probe, [])}
      else
        {:error, failure} ->
          {:error, receipt("fail", started_at, %{}, %{}, Cookie.posture(cookie), %{}, [failure])}
      end

    maybe_write(result, opts)
  end

  @spec write_receipt!(map(), Path.t()) :: Path.t()
  def write_receipt!(receipt, path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(receipt, pretty: true) <> "\n")
    path
  end

  defp peer_probe do
    Peer.with_peer(fn peer ->
      :ok = sync_or_raise(peer)

      case Peer.remote_call(peer, :erlang, :node, []) do
        {:ok, peer_node} ->
          %{
            "started?" => true,
            "peer_node" => Atom.to_string(peer_node),
            "code_paths_synced?" => true,
            "remote_call" => "ok"
          }

        {:error, reason} ->
          raise "remote call failed: #{inspect(reason)}"
      end
    end)
    |> case do
      {:ok, probe} ->
        {:ok, Map.merge(probe, %{"stopped?" => true, "reachable_after_stop?" => false})}

      {:error, failure} ->
        {:error, failure}
    end
  end

  defp sync_or_raise(peer) do
    case Peer.sync_code_paths(peer) do
      :ok -> :ok
      {:error, reason} -> raise "code path sync failed: #{inspect(reason)}"
    end
  end

  defp receipt(status, started_at, epmd, distribution, cookie_posture, peer_probe, failures) do
    %{
      "schema_version" => @schema_version,
      "receipt_ref" => @receipt_ref,
      "status" => status,
      "started_at" => DateTime.to_iso8601(started_at),
      "finished_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "epmd" => epmd,
      "distribution" => distribution,
      "cookie_posture" => cookie_posture,
      "peer_probe" => peer_probe,
      "failures" => failures,
      "does_not_prove" => [
        "owner facade availability",
        "domain business semantics",
        "monolith/distributed parity",
        "production distribution security",
        "release artifact boot"
      ]
    }
  end

  defp maybe_write({status, receipt}, opts) do
    case Keyword.get(opts, :receipt_path) do
      nil -> {status, receipt}
      path -> {status, Map.put(receipt, "receipt_path", write_receipt!(receipt, path))}
    end
  end
end
