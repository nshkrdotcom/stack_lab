import Config

config :ash,
  domains: [
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
