import Config

config :ash,
  domains: [
    Mezzanine.ConfigRegistry,
    Mezzanine.Execution,
    Mezzanine.Objects,
    Mezzanine.AuditDomain,
    Mezzanine.Decisions,
    Mezzanine.EvidenceLedger,
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

config :mezzanine_object_engine,
  ecto_repos: [Mezzanine.Objects.Repo],
  ash_domains: [Mezzanine.Objects],
  start_runtime_children?: false

config :mezzanine_audit_engine,
  ecto_repos: [Mezzanine.Audit.Repo],
  ash_domains: [Mezzanine.AuditDomain],
  start_runtime_children?: false

config :mezzanine_decision_engine,
  ecto_repos: [Mezzanine.Decisions.Repo],
  ash_domains: [Mezzanine.Decisions],
  start_runtime_children?: false

config :mezzanine_evidence_engine,
  ecto_repos: [Mezzanine.EvidenceLedger.Repo],
  ash_domains: [Mezzanine.EvidenceLedger],
  start_runtime_children?: false

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
