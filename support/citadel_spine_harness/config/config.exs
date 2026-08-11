import Config

local_store_capability = %{
  store_ref: :jido_integration_store_local,
  tier: :local_restart_safe,
  data_classes: [:auth_truth, :control_plane_truth, :submission_ledger],
  adapter: :jido_integration_store_local,
  restart_safe?: true,
  durable?: true,
  partitions: []
}

config :jido_integration_v2_auth,
  persistence: [
    profile: :local_restart_safe,
    capabilities: [local_store_capability],
    store_modules: %{
      credential_store: Jido.Integration.V2.StoreLocal.CredentialStore,
      lease_store: Jido.Integration.V2.StoreLocal.LeaseStore,
      connection_store: Jido.Integration.V2.StoreLocal.ConnectionStore,
      install_store: Jido.Integration.V2.StoreLocal.InstallStore
    }
  ]

config :jido_integration_v2_control_plane,
  persistence: [
    profile: :local_restart_safe,
    capabilities: [local_store_capability],
    store_modules: %{
      run_store: Jido.Integration.V2.StoreLocal.RunStore,
      attempt_store: Jido.Integration.V2.StoreLocal.AttemptStore,
      recovery_task_store: Jido.Integration.V2.StoreLocal.RecoveryTaskStore,
      event_store: Jido.Integration.V2.StoreLocal.EventStore,
      artifact_store: Jido.Integration.V2.StoreLocal.ArtifactStore,
      claim_check_store: Jido.Integration.V2.StoreLocal.ClaimCheckStore,
      target_store: Jido.Integration.V2.StoreLocal.TargetStore,
      ingress_store: Jido.Integration.V2.StoreLocal.IngressStore,
      profile_registry_store: Jido.Integration.V2.StoreLocal.ProfileRegistryStore
    }
  ]

config :ash,
  domains: [
    Mezzanine.Projections,
    Mezzanine.ConfigRegistry,
    Mezzanine.Execution,
    Mezzanine.Objects,
    Mezzanine.Audit,
    Mezzanine.Decisions,
    Mezzanine.EvidenceLedger,
    Mezzanine.Archival,
    Mezzanine.Programs,
    Mezzanine.Work,
    Mezzanine.Runs,
    Mezzanine.Review,
    Mezzanine.Evidence,
    Mezzanine.Control
  ]

config :mezzanine_projection_engine,
  ecto_repos: [Mezzanine.Projections.Repo],
  ash_domains: [Mezzanine.Projections],
  start_runtime_children?: true

config :mezzanine_projection_engine, Mezzanine.Projections.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mezzanine_projection_engine_test",
  pool_size: 4

config :mezzanine_config_registry,
  ecto_repos: [Mezzanine.ConfigRegistry.Repo],
  ash_domains: [Mezzanine.ConfigRegistry],
  start_runtime_children?: false

config :mezzanine_execution_engine,
  ecto_repos: [Mezzanine.Execution.Repo],
  ash_domains: [Mezzanine.Execution],
  start_runtime_children?: false

config :mezzanine_execution_engine, Oban,
  name: Mezzanine.Execution.Oban,
  repo: Mezzanine.Execution.Repo,
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.Isolated,
  peer: false,
  queues: false,
  plugins: false,
  testing: :manual

config :mezzanine_object_engine,
  ecto_repos: [Mezzanine.Objects.Repo],
  ash_domains: [Mezzanine.Objects],
  start_runtime_children?: false

config :mezzanine_audit_engine,
  ecto_repos: [Mezzanine.Audit.Repo],
  ash_domains: [Mezzanine.Audit],
  start_runtime_children?: false

config :mezzanine_decision_engine,
  ecto_repos: [Mezzanine.Decisions.Repo],
  ash_domains: [Mezzanine.Decisions],
  start_runtime_children?: false

config :mezzanine_evidence_engine,
  ecto_repos: [Mezzanine.EvidenceLedger.Repo],
  ash_domains: [Mezzanine.EvidenceLedger],
  start_runtime_children?: false

config :mezzanine_archival_engine,
  ecto_repos: [Mezzanine.Archival.Repo],
  ash_domains: [Mezzanine.Archival],
  start_runtime_children?: false,
  cold_store: [
    module: Mezzanine.Archival.FileSystemColdStore,
    root: Path.join(System.tmp_dir!(), "stack_lab_citadel_spine_harness_archival_store")
  ],
  scheduler: [
    enabled?: false,
    interval_ms: :timer.minutes(5)
  ]

config :mezzanine_ops_domain,
  ecto_repos: [Mezzanine.OpsDomain.Repo],
  ash_domains: [
    Mezzanine.Programs,
    Mezzanine.Work,
    Mezzanine.Runs,
    Mezzanine.Review,
    Mezzanine.Evidence,
    Mezzanine.Control
  ],
  start_runtime_children?: false
