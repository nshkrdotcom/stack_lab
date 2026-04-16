import Config

config :ash,
  domains: [Mezzanine.Execution, Mezzanine.Objects, Mezzanine.Audit]

config :mezzanine_execution_engine,
  ash_domains: [Mezzanine.Execution]

config :mezzanine_object_engine,
  ash_domains: [Mezzanine.Objects]

config :mezzanine_audit_engine,
  ash_domains: [Mezzanine.Audit]
