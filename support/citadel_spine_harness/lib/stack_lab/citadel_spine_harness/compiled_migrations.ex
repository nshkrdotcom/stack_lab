defmodule StackLab.CitadelSpineHarness.CompiledMigrations do
  @moduledoc false

  @cache_key {__MODULE__, :migration_modules}

  @spec for_path(String.t()) :: [{integer(), module()}]
  def for_path(migration_dir) when is_binary(migration_dir) do
    StackLab.CitadelSpineHarness.RuntimeResourceOwner.transaction(fn ->
      do_for_path(migration_dir)
    end)
  end

  defp do_for_path(migration_dir) do
    cache = :persistent_term.get(@cache_key, %{})

    case Map.fetch(cache, migration_dir) do
      {:ok, migrations} ->
        migrations

      :error ->
        migrations =
          migration_dir
          |> migration_files()
          |> Enum.map(&compile_migration!/1)
          |> Enum.sort_by(&elem(&1, 0))

        :persistent_term.put(@cache_key, Map.put(cache, migration_dir, migrations))
        migrations
    end
  end

  defp migration_files(migration_dir) do
    migration_dir
    |> Path.join("**/*.exs")
    |> Path.wildcard()
  end

  defp compile_migration!(file) do
    version = migration_version!(file)

    case migration_module(file) do
      nil ->
        raise ArgumentError,
              "migration file #{Path.relative_to_cwd(file)} does not define an Ecto migration"

      module ->
        {version, module}
    end
  end

  defp migration_module(file) do
    file
    |> Code.compile_file()
    |> Enum.find_value(fn {module, _bytecode} ->
      if function_exported?(module, :__migration__, 0), do: module
    end)
  end

  defp migration_version!(file) do
    file
    |> Path.basename()
    |> Path.rootname()
    |> Integer.parse()
    |> case do
      {version, "_" <> _name} ->
        version

      _other ->
        raise ArgumentError, "invalid migration filename: #{Path.relative_to_cwd(file)}"
    end
  end
end
