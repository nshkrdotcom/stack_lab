defmodule StackLab.CitadelSpineHarness.MezzanineSubstrate do
  @moduledoc false

  alias Ecto.Migrator
  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.ConfigRegistry.Repo, as: ConfigRegistryRepo
  alias Mezzanine.Decisions.Repo, as: DecisionsRepo
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.Objects.Repo, as: ObjectsRepo
  alias Mezzanine.Pack.Registry, as: PackRegistry
  alias Mezzanine.RuntimeScheduler.Repo, as: RuntimeSchedulerRepo
  alias StackLab.CitadelSpineHarness.CompiledMigrations
  alias StackLab.CitadelSpineHarness.PostgresContainer

  @repo_modules [
    AuditRepo,
    ObjectsRepo,
    ExecutionRepo,
    DecisionsRepo,
    ConfigRegistryRepo,
    RuntimeSchedulerRepo
  ]
  @migration_components [
    {AuditRepo, "audit_engine"},
    {ObjectsRepo, "object_engine"},
    {ExecutionRepo, "execution_engine"},
    {ExecutionRepo, "leasing"},
    {ExecutionRepo, "barriers"},
    {DecisionsRepo, "decision_engine"},
    {ConfigRegistryRepo, "config_registry"},
    {RuntimeSchedulerRepo, "runtime_scheduler"}
  ]

  @spec with_store(atom() | String.t(), (keyword() -> any())) :: any()
  def with_store(label, fun) when is_function(fun, 1) do
    container = PostgresContainer.start!("mezzanine_substrate_#{label}")
    repo_config = PostgresContainer.repo_config(container.port)

    try do
      start_repos!(repo_config)
      migrate_schema!()
      start_oban!()
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
    start_oban!()
    start_pack_registry!()
    :ok
  end

  @spec stop_runtime() :: :ok
  def stop_runtime do
    stop_pack_registry()
    stop_oban()
    Enum.each(Enum.reverse(@repo_modules), &stop_repo/1)
    :ok
  end

  defp migrate_schema! do
    Enum.each(@migration_components, fn {repo, component} ->
      Migrator.run(repo, CompiledMigrations.for_path(migration_path(component)), :up,
        all: true,
        log: false
      )
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
    stop_repo(repo_module)
    put_repo_config!(repo_module, repo_config)

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

  defp put_repo_config!(repo_module, repo_config) do
    Application.put_env(repo_otp_app(repo_module), repo_module, repo_config)
  end

  defp repo_otp_app(repo_module) do
    repo_module.config()
    |> Keyword.fetch!(:otp_app)
  end

  defp start_oban! do
    stop_oban()

    oban_config = Application.fetch_env!(:mezzanine_execution_engine, Oban)
    start_oban_instance!(oban_config)
  end

  defp stop_oban do
    case oban_pid() do
      nil ->
        :ok

      pid ->
        try do
          GenServer.stop(pid)
        catch
          :exit, _reason -> :ok
        end

        wait_for_oban_shutdown()
    end
  end

  defp start_oban_instance!(oban_config) do
    case Oban.start_link(oban_config) do
      {:ok, pid} ->
        Process.unlink(pid)
        pid

      {:error, {:already_started, pid}} ->
        stop_stale_oban!(pid)
        wait_for_oban_shutdown()

        {:ok, restarted_pid} = Oban.start_link(oban_config)
        Process.unlink(restarted_pid)
        restarted_pid
    end
  end

  defp stop_stale_oban!(pid) do
    Process.exit(pid, :shutdown)
    :ok
  end

  defp oban_pid do
    Oban.Registry.whereis(Mezzanine.Execution.Oban)
  end

  defp wait_for_oban_shutdown do
    Enum.reduce_while(1..50, :ok, fn _, _acc ->
      case oban_pid() do
        nil ->
          {:halt, :ok}

        _pid ->
          Process.sleep(10)
          {:cont, :ok}
      end
    end)
  end
end
