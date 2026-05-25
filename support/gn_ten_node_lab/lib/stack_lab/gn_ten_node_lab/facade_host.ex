defmodule StackLab.GnTenNodeLab.FacadeHost do
  @moduledoc """
  Generic test-harness process that exposes an owner facade module through
  the owner-defined `:pg` group for local distributed proofs.

  This process is StackLab-owned harness infrastructure. It does not define the
  facade contract and it does not move owner semantics into StackLab.
  """

  use GenServer

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec start(keyword()) :: GenServer.on_start()
  def start(opts) when is_list(opts) do
    GenServer.start(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    facade_module = Keyword.fetch!(opts, :facade_module)
    owner_group = Keyword.fetch!(opts, :owner_group)

    with :ok <- ensure_facade_module(facade_module),
         :ok <- ensure_owner_group(facade_module, owner_group),
         :ok <- ensure_pg_started(),
         :ok <- join_owner_group(owner_group) do
      {:ok, %{facade_module: facade_module, owner_group: owner_group}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp ensure_facade_module(facade_module) when is_atom(facade_module) do
    with {:module, ^facade_module} <- Code.ensure_loaded(facade_module),
         true <- function_exported?(facade_module, :owner_group, 0) do
      :ok
    else
      _other -> {:error, {:facade_module_unavailable, facade_module}}
    end
  end

  defp ensure_facade_module(facade_module), do: {:error, {:invalid_facade_module, facade_module}}

  defp ensure_owner_group(facade_module, owner_group) do
    if facade_module.owner_group() == owner_group do
      :ok
    else
      {:error, {:owner_group_mismatch, facade_module, owner_group}}
    end
  end

  defp ensure_pg_started do
    case Process.whereis(:pg) do
      nil ->
        case :pg.start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, {:pg_start_failed, reason}}
        end

      _pid ->
        :ok
    end
  end

  defp join_owner_group(owner_group) do
    case :pg.join(owner_group, self()) do
      :ok -> :ok
      {:error, reason} -> {:error, {:owner_group_join_failed, reason}}
    end
  end
end
