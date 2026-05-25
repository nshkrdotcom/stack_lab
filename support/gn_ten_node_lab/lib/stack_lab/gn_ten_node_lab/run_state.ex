defmodule StackLab.GnTenNodeLab.RunState do
  @moduledoc """
  File-backed run-state helpers for node-lab Mix commands.

  The state file records receipts and node names only. It never stores the
  Erlang cookie or any domain payload.
  """

  @default_state_path "tmp/stack_lab/gn_ten_node_lab/current_run.json"

  @spec default_path() :: Path.t()
  def default_path, do: @default_state_path

  @spec read(Path.t()) :: {:ok, map()} | {:error, map()}
  def read(path \\ @default_state_path) when is_binary(path) do
    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, state} -> {:ok, state}
          {:error, error} -> {:error, failure("run_state_decode_failed", inspect(error))}
        end

      {:error, :enoent} ->
        {:error, failure("no_active_run", path)}

      {:error, reason} ->
        {:error, failure("run_state_read_failed", inspect(reason))}
    end
  end

  @spec write!(map(), Path.t()) :: Path.t()
  def write!(state, path \\ @default_state_path) when is_map(state) and is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(state, pretty: true) <> "\n")
    path
  end

  @spec delete(Path.t()) :: :ok | {:error, term()}
  def delete(path \\ @default_state_path) when is_binary(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp failure(code, reason), do: %{code: code, reason: reason}
end
