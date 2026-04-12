import Config

config :jido_integration_v2_store_local,
  storage_dir:
    Path.join(
      System.tmp_dir!(),
      "stack_lab_pressure_failover_drill_#{System.unique_integer([:positive, :monotonic])}"
    )
