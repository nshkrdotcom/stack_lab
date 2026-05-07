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

Phase 10 scanner receipts also require complete `:mickey_mouse`,
`:memory_debug`, `:integration_postgres`, and `:full_debug_tracked` profile
coverage; storage behavior must change when switching from memory to durable
profiles; authority semantics must remain stable for the same deterministic
governed provider input; restart-claim classification must stay `:none` for
memory profiles and durable-only for durable tiers; and every `PERSIST-001`
through `PERSIST-020` fixture must map to source, test, scanner, docs, and
receipt evidence.

The scanner does not parse source text. Regex APIs are not allowed in scanner
code or tests, and phase static checks use fixed-string token scans only.

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
