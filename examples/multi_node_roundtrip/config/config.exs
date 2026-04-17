import Config

import_config "../../../support/citadel_spine_harness/config/config.exs"

config :ash,
  domains: [Mezzanine.ConfigRegistry, Mezzanine.Execution, Mezzanine.Objects, Mezzanine.Audit]

config :jido_integration_v2_store_local,
  storage_dir:
    Path.join(
      System.tmp_dir!(),
      "stack_lab_multi_node_roundtrip_#{System.unique_integer([:positive, :monotonic])}"
    )
