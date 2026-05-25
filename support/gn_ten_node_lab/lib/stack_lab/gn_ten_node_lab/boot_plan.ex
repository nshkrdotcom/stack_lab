defmodule StackLab.GnTenNodeLab.BootPlan do
  @moduledoc """
  Peer-node app boot and owner-facade readiness probes for topology instances.
  """

  alias StackLab.GnTenNodeLab.{FacadeHost, Peer, Topology}

  @remote_call_timeout_ms 5_000

  @spec instances(Topology.t()) :: [map()]
  def instances(%Topology{} = topology), do: Topology.instance_specs(topology)

  @spec boot_instance(Peer.t() | node(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  def boot_instance(target, instance, opts \\ []) when is_map(instance) and is_list(opts) do
    node = target_node(target)

    with {:ok, started_apps} <- start_required_apps(node, Map.get(instance, :required_apps, [])),
         {:ok, facade_hosts} <-
           maybe_start_facade_hosts(node, Map.get(instance, :owner_groups, []), opts),
         {:ok, owner_group_membership} <-
           probe_owner_groups(node, Map.get(instance, :owner_groups, [])) do
      {:ok,
       %{
         "node_id" => Map.fetch!(instance, :node_id),
         "profile" => instance.profile |> Atom.to_string(),
         "node" => Atom.to_string(node),
         "started_apps" => started_apps,
         "facade_hosts" => facade_hosts,
         "owner_group_membership" => owner_group_membership,
         "ready?" => true
       }}
    end
  end

  @spec probe_owner_groups(Peer.t() | node(), [tuple()]) :: {:ok, [map()]} | {:error, map()}
  def probe_owner_groups(target, owner_groups) when is_list(owner_groups) do
    node = target_node(target)

    owner_groups
    |> Enum.reduce_while({:ok, []}, fn owner_group, {:ok, receipts} ->
      case owner_group_members(node, owner_group) do
        {:ok, members} when members != [] ->
          {:cont, {:ok, [membership_receipt(owner_group, members) | receipts]}}

        {:ok, []} ->
          {:halt,
           {:error, failure("owner_group_not_registered", owner_group: inspect(owner_group))}}

        {:error, reason} ->
          {:halt, {:error, failure("owner_group_probe_failed", reason: inspect(reason))}}
      end
    end)
    |> case do
      {:ok, receipts} -> {:ok, Enum.reverse(receipts)}
      {:error, failure} -> {:error, failure}
    end
  end

  defp maybe_start_facade_hosts(_node, _owner_groups, start_facade_hosts?: false), do: {:ok, []}

  defp maybe_start_facade_hosts(node, owner_groups, _opts) do
    owner_groups
    |> Enum.reduce_while({:ok, []}, fn owner_group, {:ok, receipts} ->
      case start_facade_host(node, owner_group) do
        {:ok, receipt} -> {:cont, {:ok, [receipt | receipts]}}
        {:error, failure} -> {:halt, {:error, failure}}
      end
    end)
    |> case do
      {:ok, receipts} -> {:ok, Enum.reverse(receipts)}
      {:error, failure} -> {:error, failure}
    end
  end

  defp start_required_apps(node, required_apps) do
    required_apps
    |> Enum.reduce_while({:ok, []}, fn app, {:ok, receipts} ->
      case Peer.remote_call(
             node,
             Application,
             :ensure_all_started,
             [app],
             @remote_call_timeout_ms
           ) do
        {:ok, {:ok, apps}} ->
          {:cont,
           {:ok, [%{"app" => Atom.to_string(app), "started" => apps_to_strings(apps)} | receipts]}}

        {:ok, {:error, reason}} ->
          {:halt,
           {:error,
            failure("app_start_failed", app: Atom.to_string(app), reason: inspect(reason))}}

        {:error, reason} ->
          {:halt,
           {:error,
            failure("app_start_probe_failed", app: Atom.to_string(app), reason: inspect(reason))}}
      end
    end)
    |> case do
      {:ok, receipts} -> {:ok, Enum.reverse(receipts)}
      {:error, failure} -> {:error, failure}
    end
  end

  defp start_facade_host(node, {facade_module, _name} = owner_group) do
    args = [[facade_module: facade_module, owner_group: owner_group]]

    case Peer.remote_call(node, FacadeHost, :start, args, @remote_call_timeout_ms) do
      {:ok, {:ok, pid}} ->
        {:ok,
         %{
           "facade_module" => inspect(facade_module),
           "owner_group" => inspect(owner_group),
           "pid" => inspect(pid)
         }}

      {:ok, {:error, reason}} ->
        {:error,
         failure("facade_host_start_failed",
           owner_group: inspect(owner_group),
           reason: inspect(reason)
         )}

      {:error, reason} ->
        {:error,
         failure("facade_host_start_probe_failed",
           owner_group: inspect(owner_group),
           reason: inspect(reason)
         )}
    end
  end

  defp owner_group_members(node, owner_group) do
    Peer.remote_call(node, :pg, :get_members, [owner_group], @remote_call_timeout_ms)
  end

  defp target_node(%Peer{peer_node: peer_node}), do: peer_node
  defp target_node(node) when is_atom(node), do: node

  defp membership_receipt(owner_group, members) do
    %{
      "owner_group" => inspect(owner_group),
      "member_count" => length(members),
      "members" => Enum.map(members, &inspect/1)
    }
  end

  defp apps_to_strings(apps), do: Enum.map(apps, &Atom.to_string/1)

  defp failure(code, attrs), do: Enum.into(attrs, %{code: code})
end
