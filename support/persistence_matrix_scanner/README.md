# StackLab Persistence Matrix Scanner

`stack_lab_persistence_matrix_scanner` verifies persistence profile matrix
facts for the overlay release path. It checks memory default posture, durable
opt-in tags, no default Postgres requirement, Temporal disabled-by-default
posture, optional external substrate disabled-by-default posture, redacted
debug capture, package knob docs, product no-bypass facts, and gn-ten receipt
fields for profile, tier, store set, capture level, and proof command.

The scanner consumes structured fact maps. It does not read environment,
application config, provider credentials, network state, Postgres, Temporal, or
object stores.
