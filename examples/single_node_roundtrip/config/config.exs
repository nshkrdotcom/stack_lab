import Config

config :ash,
  domains: [Mezzanine.Execution, Mezzanine.Objects, Mezzanine.Audit]

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
      "stack_lab_single_node_roundtrip_#{System.unique_integer([:positive, :monotonic])}"
    )
