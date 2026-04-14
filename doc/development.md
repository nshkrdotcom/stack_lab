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

Prepared bundle and projection tracking flow:

```bash
mix release.prepare
mix release.track
mix release.archive
```

`mix release.track` updates the orphan-backed `projection/stack_lab_lab_core`
branch so downstream repos can pin a real generated-source ref before any
formal release boundary exists.
