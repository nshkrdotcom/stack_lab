# Development

The workspace uses:

- Elixir `~> 1.19`
- `blitz` for workspace orchestration
- `weld` for deterministic projection verification
- `just` as the operator entrypoint for harness commands

Standard flow:

```bash
mix deps.get
mix ci
```

Workspace commands:

```bash
mix monorepo.test
mix monorepo.credo --strict
mix monorepo.docs
mix weld.verify
```
