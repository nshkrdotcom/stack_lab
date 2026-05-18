# StackLab Product No-Bypass Scanner

Phase 15 scanner package for product boundary no-bypass evidence.

The scanner owns `AOC-044` evidence. It checks product surfaces for direct
GEPA framework calls, direct TRINITY framework calls, direct provider SDK
calls, direct generated SDK calls, direct env auth lookup, direct runtime
mutation, direct DB access, and direct trace writes in governed workflows. It
emits ref-only receipts and blocks release when findings remain open.

The foundation gate also protects generic-stack cutovers. In product code, it
allows provider words in command names, fixtures, docs, packs, receipts, and
live examples, but flags provider-shaped implementation API names such as
`publish_linear_source/2`, `fetch_github_pr_evidence/2`, and
`cleanup_github_pr_branch/2`. Product commands may keep operator-facing names
like `live_linear_source`; the implementation below those commands must use
neutral product intent functions and AppKit role refs.

Passing receipts must name approved AppKit facade refs such as
`app-kit-adaptive-control-surface://...`; product code is not allowed to reach
adaptive control by importing GEPA, TRINITY, provider SDKs, lower runtimes,
DB repos, or trace writers directly.

QC:

```bash
mix test
mix format --check-formatted
mix compile --warnings-as-errors
mix stack_lab.foundation_gate.scan --path /home/home/p/g/n/extravaganza/apps/extravaganza_core/lib --path /home/home/p/g/n/extravaganza/apps/extravaganza_web/lib --summary
```

## Persistence Documentation

See `docs/persistence.md` for tiers, defaults, adapters, unsupported selections, config examples, restart claims, durability claims, debug sidecar behavior, redaction guarantees, migration or preflight behavior, and no-bypass scope when applicable.
