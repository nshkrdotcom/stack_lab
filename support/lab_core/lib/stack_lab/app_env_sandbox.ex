defmodule StackLab.AppEnvSandbox do
  @moduledoc """
  Scoped application environment mutation helper for StackLab harnesses.

  Application environment is process-global, so proof harnesses that need to
  override runtime adapters must snapshot and restore through one boundary.
  This module preserves missing keys and present `nil` values distinctly.
  """

  @opaque snapshot :: %{optional({atom(), atom()}) => {:present, term()} | :missing}

  @type app_key :: {atom(), atom()}
  @type operation :: {:put, atom(), atom(), term()} | {:delete, atom(), atom()} | app_key()

  @spec with_env([operation()], (-> result)) :: result when result: var
  def with_env(operations, fun) when is_list(operations) and is_function(fun, 0) do
    app_keys = Enum.map(operations, &app_key!/1)

    :global.trans({__MODULE__, :application_env}, fn ->
      previous = snapshot(app_keys)

      try do
        Enum.each(operations, &apply_operation/1)
        fun.()
      after
        restore(previous)
      end
    end)
  end

  @spec snapshot([app_key()]) :: snapshot()
  def snapshot(app_keys) when is_list(app_keys) do
    Map.new(app_keys, fn {app, key} ->
      validate_app_key!(app, key)

      value =
        case Application.fetch_env(app, key) do
          {:ok, value} -> {:present, value}
          :error -> :missing
        end

      {{app, key}, value}
    end)
  end

  @spec restore(snapshot()) :: :ok
  def restore(snapshot) when is_map(snapshot) do
    Enum.each(snapshot, fn
      {{app, key}, :missing} -> delete(app, key)
      {{app, key}, {:present, value}} -> put(app, key, value)
    end)

    :ok
  end

  @spec get(atom(), atom(), term()) :: term()
  def get(app, key, default \\ nil) do
    validate_app_key!(app, key)
    Application.get_env(app, key, default)
  end

  @spec fetch!(atom(), atom()) :: term()
  def fetch!(app, key) do
    validate_app_key!(app, key)
    Application.fetch_env!(app, key)
  end

  @spec put(atom(), atom(), term()) :: :ok
  def put(app, key, value) do
    validate_app_key!(app, key)
    Application.put_env(app, key, value)
  end

  @spec delete(atom(), atom()) :: :ok
  def delete(app, key) do
    validate_app_key!(app, key)
    Application.delete_env(app, key)
  end

  defp apply_operation({:put, app, key, value}), do: put(app, key, value)
  defp apply_operation({:delete, app, key}), do: delete(app, key)
  defp apply_operation({_app, _key}), do: :ok

  defp app_key!({:put, app, key, _value}) do
    validate_app_key!(app, key)
    {app, key}
  end

  defp app_key!({:delete, app, key}) do
    validate_app_key!(app, key)
    {app, key}
  end

  defp app_key!({app, key}) do
    validate_app_key!(app, key)
    {app, key}
  end

  defp validate_app_key!(app, key) when is_atom(app) and is_atom(key), do: :ok

  defp validate_app_key!(app, key) do
    raise ArgumentError,
          "expected application env key as {atom_app, atom_key}, got #{inspect({app, key})}"
  end
end
