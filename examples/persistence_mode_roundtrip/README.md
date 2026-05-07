# StackLab Persistence Mode Roundtrip

`stack_lab_persistence_mode_roundtrip` proves the deterministic persistence
profile matrix over GroundPlane policy contracts. It covers memory default,
memory debug, gated Postgres durability, full debug tracking with redacted
events, gn-ten receipt fields, and scanner receipts without live provider,
Postgres, Temporal, object store, network, or optional external substrate
requirements.

Phase 10 receipts cover `:mickey_mouse`, `:memory_debug`,
`:integration_postgres`, and `:full_debug_tracked`. Each per-profile receipt
records selected profile, selected tier, store set, capture level, proof
command, durable opt-in tag, preflight result, storage behavior ref, stable
authority semantics ref, restart-claim classification, redacted debug
event/result, and gn-ten receipt fields.

The top-level receipt carries complete `PERSIST-001` through `PERSIST-020`
fixture mappings to source, test, scanner, docs, and receipt evidence. The
harness uses structured GroundPlane policy data only; it does not read process
environment, application config, provider credentials, network state, Postgres,
Temporal, object stores, optional external substrates, or raw debug payloads.
Regex APIs are not allowed in this package.
