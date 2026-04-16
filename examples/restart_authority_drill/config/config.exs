import Config

config :ash,
  domains: [Mezzanine.ConfigRegistry, Mezzanine.Execution, Mezzanine.Objects, Mezzanine.Audit]

config :mezzanine_config_registry,
  ash_domains: [Mezzanine.ConfigRegistry]

config :mezzanine_execution_engine,
  ash_domains: [Mezzanine.Execution]

config :mezzanine_object_engine,
  ash_domains: [Mezzanine.Objects]

config :mezzanine_audit_engine,
  ash_domains: [Mezzanine.Audit]

config :jido_integration_v2_store_local,
  storage_dir:
    Path.join(
      System.tmp_dir!(),
      "stack_lab_restart_authority_drill_#{System.unique_integer([:positive, :monotonic])}"
    )
