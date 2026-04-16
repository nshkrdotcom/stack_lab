defmodule StackLab.CitadelSpineHarness.MezzanineSubstrate do
  @moduledoc false

  alias Ecto.Migrator
  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.ConfigRegistry.Repo, as: ConfigRegistryRepo
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.Objects.Repo, as: ObjectsRepo
  alias Mezzanine.Pack.Registry, as: PackRegistry
  alias StackLab.CitadelSpineHarness.PostgresContainer

  @repo_modules [AuditRepo, ObjectsRepo, ExecutionRepo, ConfigRegistryRepo]
  @migration_components [
    {AuditRepo, "audit_engine"},
    {ObjectsRepo, "object_engine"},
    {ExecutionRepo, "execution_engine"},
    {ConfigRegistryRepo, "config_registry"}
  ]

  @spec with_store(atom() | String.t(), (keyword() -> any())) :: any()
  def with_store(label, fun) when is_function(fun, 1) do
    container = PostgresContainer.start!("mezzanine_substrate_#{label}")
    repo_config = PostgresContainer.repo_config(container.port)

    start_repos!(repo_config)

    try do
      migrate_schema!()
      start_pack_registry!()
      fun.(repo_config)
    after
      stop_runtime()
      PostgresContainer.stop!(container)
    end
  end

  @spec restart_runtime!(keyword()) :: :ok
  def restart_runtime!(repo_config) do
    stop_runtime()
    start_repos!(repo_config)
    start_pack_registry!()
    :ok
  end

  @spec stop_runtime() :: :ok
  def stop_runtime do
    stop_pack_registry()
    Enum.each(Enum.reverse(@repo_modules), &stop_repo/1)
    :ok
  end

  defp migrate_schema! do
    Enum.each(@migration_components, fn {repo, component} ->
      Migrator.run(repo, migration_path(component), :up, all: true, log: false)
    end)
  end

  defp migration_path(component) do
    Path.join(
      StackLab.CitadelSpineHarness.repo_roots().mezzanine,
      "core/#{component}/priv/repo/migrations"
    )
  end

  defp start_repos!(repo_config) do
    Enum.each(@repo_modules, &start_repo!(&1, repo_config))
  end

  defp start_repo!(repo_module, repo_config) do
    {:ok, repo_pid} = repo_module.start_link(repo_config)
    Process.unlink(repo_pid)
    repo_pid
  end

  defp stop_repo(repo_module) do
    case Process.whereis(repo_module) do
      nil ->
        :ok

      _pid ->
        try do
          GenServer.stop(repo_module)
        catch
          :exit, _reason -> :ok
        end
    end
  end

  defp start_pack_registry! do
    case Process.whereis(PackRegistry) do
      nil ->
        {:ok, pid} = PackRegistry.start_link()
        Process.unlink(pid)
        pid

      pid ->
        pid
    end
  end

  defp stop_pack_registry do
    case Process.whereis(PackRegistry) do
      nil ->
        :ok

      _pid ->
        try do
          GenServer.stop(PackRegistry)
        catch
          :exit, _reason -> :ok
        end
    end
  end
end
