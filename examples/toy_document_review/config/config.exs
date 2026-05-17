import Config

config :stack_lab_toy_document_review,
  ecto_repos: [
    Mezzanine.ConfigRegistry.Repo,
    Mezzanine.Execution.Repo
  ]

config :ash,
  domains: [Mezzanine.ConfigRegistry]

config :spark,
  formatter: [
    remove_parens?: true,
    "Ash.Resource": [
      section_order: [
        :postgres,
        :code_interface,
        :actions,
        :multitenancy,
        :attributes,
        :relationships,
        :identities
      ]
    ],
    "Ash.Domain": [
      section_order: [:resources]
    ]
  ]

config :mezzanine_config_registry,
  ecto_repos: [Mezzanine.ConfigRegistry.Repo],
  ash_domains: [Mezzanine.ConfigRegistry],
  generators: [timestamp_type: :utc_datetime]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
