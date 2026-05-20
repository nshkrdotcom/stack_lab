defmodule StackLab.CitadelSpineHarness.MezzanineSubstrate do
  @moduledoc false

  alias Ecto.Migrator
  alias Mezzanine.Archival.Repo, as: ArchivalRepo
  alias Mezzanine.Audit.Repo, as: AuditRepo
  alias Mezzanine.ConfigRegistry.Repo, as: ConfigRegistryRepo
  alias Mezzanine.Decisions.Repo, as: DecisionsRepo
  alias Mezzanine.Execution.Repo, as: ExecutionRepo
  alias Mezzanine.Execution.RuntimeStack
  alias Mezzanine.Objects.Repo, as: ObjectsRepo
  alias Mezzanine.Pack.Registry, as: PackRegistry
  alias Mezzanine.RuntimeScheduler.Repo, as: RuntimeSchedulerRepo
  alias StackLab.AppEnvSandbox
  alias StackLab.CitadelSpineHarness.CompiledMigrations
  alias StackLab.CitadelSpineHarness.PostgresContainer
  alias StackLab.CitadelSpineHarness.RuntimeResourceOwner

  @ops_domain_repo RuntimeStack.ops_domain_repo()
  @repo_modules [
    AuditRepo,
    @ops_domain_repo,
    ObjectsRepo,
    ExecutionRepo,
    DecisionsRepo,
    ConfigRegistryRepo,
    RuntimeSchedulerRepo,
    ArchivalRepo
  ]
  @migration_components [
    {AuditRepo, "audit_engine"},
    {@ops_domain_repo, "ops_domain"},
    {ObjectsRepo, "object_engine"},
    {ExecutionRepo, "execution_engine"},
    {ExecutionRepo, "leasing"},
    {ExecutionRepo, "barriers"},
    {DecisionsRepo, "decision_engine"},
    {ConfigRegistryRepo, "config_registry"},
    {RuntimeSchedulerRepo, "runtime_scheduler"},
    {ArchivalRepo, "archival_engine"}
  ]

  @spec with_store(atom() | String.t(), (keyword() -> any())) :: any()
  def with_store(label, fun) when is_function(fun, 1) do
    RuntimeResourceOwner.transaction(fn ->
      do_with_store(label, fun)
    end)
  end

  defp do_with_store(label, fun) do
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

    case repo_module.start_link(repo_config) do
      {:ok, repo_pid} ->
        Process.unlink(repo_pid)
        repo_pid

      {:error, {:already_started, repo_pid}} ->
        stop_pid!(repo_pid, repo_module)
        {:ok, restarted_pid} = repo_module.start_link(repo_config)
        Process.unlink(restarted_pid)
        restarted_pid
    end
  end

  defp stop_repo(repo_module) do
    case Process.whereis(repo_module) do
      nil ->
        :ok

      pid ->
        stop_pid!(pid, repo_module)
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

      pid ->
        stop_pid!(pid, PackRegistry)
    end
  end

  defp put_repo_config!(repo_module, repo_config) do
    AppEnvSandbox.put(repo_otp_app(repo_module), repo_module, repo_config)
  end

  defp repo_otp_app(repo_module) do
    repo_module.config()
    |> Keyword.fetch!(:otp_app)
  end

  defp start_oban! do
    stop_oban()

    oban_config = AppEnvSandbox.fetch!(:mezzanine_execution_engine, Oban)
    start_oban_instance!(oban_config)
  end

  defp stop_oban do
    case oban_pid() do
      nil ->
        :ok

      pid ->
        stop_pid!(pid, Oban)
    end
  end

  defp start_oban_instance!(oban_config) do
    case Oban.start_link(oban_config) do
      {:ok, pid} ->
        Process.unlink(pid)
        pid

      {:error, {:already_started, pid}} ->
        stop_stale_oban!(pid)

        {:ok, restarted_pid} = Oban.start_link(oban_config)
        Process.unlink(restarted_pid)
        restarted_pid
    end
  end

  defp stop_stale_oban!(pid) do
    stop_pid!(pid, Oban)
  end

  defp oban_pid do
    Oban.Registry.whereis(Mezzanine.Execution.Oban)
  end

  defp stop_pid!(pid, name) when is_pid(pid) do
    monitor_ref = Process.monitor(pid)

    try do
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal, 5_000)
      end
    catch
      :exit, _reason -> :ok
    after
      receive do
        {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
          :ok
      after
        0 ->
          Process.demonitor(monitor_ref, [:flush])
      end
    end

    case Process.whereis(name) do
      ^pid -> raise "unable to stop #{inspect(name)}"
      _other -> :ok
    end
  end
end
