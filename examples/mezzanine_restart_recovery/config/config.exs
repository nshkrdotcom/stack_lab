import Config

import_config "../../../support/citadel_spine_harness/config/config.exs"

config :ash,
  domains: [Mezzanine.ConfigRegistry, Mezzanine.Execution, Mezzanine.Objects, Mezzanine.Audit]
