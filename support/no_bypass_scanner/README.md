# StackLab Product No-Bypass Scanner

Phase 15 scanner package for product boundary no-bypass evidence.

The scanner owns `AOC-044` evidence. It checks product surfaces for direct
GEPA framework calls, direct TRINITY framework calls, direct provider SDK
calls, direct generated SDK calls, direct env auth lookup, direct runtime
mutation, direct DB access, and direct trace writes in governed workflows. It
emits ref-only receipts and blocks release when findings remain open.

Passing receipts must name approved AppKit facade refs such as
`app-kit-adaptive-control-surface://...`; product code is not allowed to reach
adaptive control by importing GEPA, TRINITY, provider SDKs, lower runtimes,
DB repos, or trace writers directly.

QC:

```bash
mix test
mix format --check-formatted
mix compile --warnings-as-errors
```

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
