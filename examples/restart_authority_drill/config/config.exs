import Config

config :mezzanine_audit_engine,
  ash_domains: [Mezzanine.Audit]

config :jido_integration_v2_store_local,
  storage_dir:
    Path.join(
      System.tmp_dir!(),
      "stack_lab_restart_authority_drill_#{System.unique_integer([:positive, :monotonic])}"
    )
